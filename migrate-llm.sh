#!/usr/bin/env bash
#
# migrate-llm.sh - move Strata, its model data and the Huihui download to one new place
#
#   ~/Strata        ->  /AI/LLM/Strata         (the program, its .venv, engine, configs, run-*.sh)
#   ~/Strata-data   ->  /AI/LLM/Strata-data    (packs, models, MTP layer: the big stuff)
#   ~/huihui-qfn    ->  /AI/LLM/huihui-qfn     (the GGUF files you downloaded from Hugging Face)
#
# Strata keeps ABSOLUTE paths in its configs, run scripts, venv and settings, so a plain `mv` breaks it.
# This script copies first, then rewrites those paths in the NEW copy, then checks that nothing still
# points at the old place. Your old folders are only renamed (.migrated), never deleted.
#
# usage:   bash migrate-llm.sh [DESTINATION]          (default: /AI/LLM)
# options (environment variables, all optional):
#   YES=1         do not ask for confirmation
#   MOVE=1        low-disk mode: delete each source file as soon as it is copied (NO way back, see the warning)
#   CHECKSUM=1    after copying, compare file CONTENTS too (reads everything twice: slow, very safe)
#   OLD_STRATA=...  OLD_DATA=...  OLD_HUIHUI=...   where things are now (defaults: ~/Strata, Strata's own
#                 memory of its data folder or ~/Strata-data, ~/huihui-qfn)
#
# Safe to run again if it was interrupted (Ctrl-C, reboot): it resumes where it stopped.

set -u -o pipefail

DEST="${1:-${DEST:-/AI/LLM}}"
MOVE="${MOVE:-0}"
YES="${YES:-0}"
CHECKSUM="${CHECKSUM:-0}"

if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else B=''; G=''; Y=''; R=''; N=''; fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s== %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '%s  ok%s  %s\n' "$G" "$N" "$*"; }
warn() { printf '%s  !!%s  %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%sSTOP:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
human(){ numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s B' "$1"; }
rp()   { readlink -f -- "$1"; }
reesc(){ printf '%s' "$1" | sed 's#[][\.*^$+?(){}|\\/]#\\&#g'; }

case "${1:-}" in -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0;; esac

# ------------------------------------------------------------------------------------------ 0. the basics
step "0. Checking the basics"
[ "$(id -u)" -ne 0 ] || die "run it as your normal user, without sudo (the files must stay yours)."
command -v rsync >/dev/null || die "rsync is missing: sudo apt install rsync"
for c in python3 find grep df du numfmt readlink pgrep sed; do
  command -v "$c" >/dev/null || die "missing command: $c"
done

OLD_STRATA="${OLD_STRATA:-$HOME/Strata}"
OLD_HUIHUI="${OLD_HUIHUI:-$HOME/huihui-qfn}"
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/strata/settings.json"
if [ -z "${OLD_DATA:-}" ]; then
  OLD_DATA=""
  if [ -r "$SETTINGS" ]; then      # Strata remembers where its data folder is
    OLD_DATA=$(python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("data_dir") or "")
except Exception: pass' "$SETTINGS")
  fi
  OLD_DATA="${OLD_DATA:-$HOME/Strata-data}"
fi

[ -f "$OLD_STRATA/setup.py" ] || die "no Strata folder at $OLD_STRATA (set OLD_STRATA=/where/it/is)."

NAMES=(); OLDS=(); NEWS=(); OLDRP=()
add_item() { NAMES+=("$1"); OLDS+=("$2"); NEWS+=("$3"); OLDRP+=("$(rp "$2")"); }

mkdir -p -- "$DEST" 2>/dev/null || die "cannot create $DEST. Once, as root:  sudo mkdir -p '$DEST' && sudo chown '$USER': '$DEST'"
[ -w "$DEST" ] || die "$DEST is not writable for you. Once, as root:  sudo chown '$USER': '$DEST'"
DEST=$(rp "$DEST")
case "$(stat -f -c %T -- "$DEST" 2>/dev/null)" in
  msdos|vfat|exfat|ntfs*|fuseblk)
    warn "$DEST looks like a Windows-type disk (NTFS/exFAT/FAT): it cannot hold Linux permissions and symlinks, so Strata's venv would break. Use an ext4/btrfs/xfs disk." ;;
esac

add_item "Strata" "$OLD_STRATA" "$DEST/Strata"
if [ -d "$OLD_DATA" ] && [ "$(rp "$OLD_DATA")" != "$(rp "$OLD_STRATA")" ]; then
  add_item "Strata-data" "$OLD_DATA" "$DEST/Strata-data"
else
  warn "no separate Strata-data folder found ($OLD_DATA): skipping it (set OLD_DATA=... if it lives elsewhere)."
fi
if [ -d "$OLD_HUIHUI" ]; then
  add_item "huihui-qfn" "$OLD_HUIHUI" "$DEST/huihui-qfn"
else
  warn "no Huihui folder at $OLD_HUIHUI: skipping it (set OLD_HUIHUI=... if it lives elsewhere)."
fi

ALLOLD=(); declare -A seen_old=()
for i in "${!NAMES[@]}"; do
  for p in "${OLDS[$i]}" "${OLDRP[$i]}"; do
    [ -n "${seen_old[$p]:-}" ] || { seen_old[$p]=1; ALLOLD+=("$p"); }
  done
done

# nothing may contain anything else
for i in "${!NAMES[@]}"; do
  case "$DEST/" in "${OLDRP[$i]}"/*) die "the destination $DEST is inside ${OLDS[$i]}.";; esac
  case "${OLDRP[$i]}/" in "$DEST"/*) die "${OLDS[$i]} is already under $DEST: nothing to migrate.";; esac
done

# a leftover half-finished run is fine (marker file); somebody else's folder is not
MARK="$DEST/.migration-in-progress"
for i in "${!NAMES[@]}"; do
  n="${NEWS[$i]}"
  if [ -e "$n" ] && [ -n "$(ls -A -- "$n" 2>/dev/null)" ] && [ ! -e "$MARK" ]; then
    die "$n already exists and is not empty, and it does not come from an earlier run of this script. Move it away, or pick another destination."
  fi
done
ok "destination: $DEST"

# a terminal standing inside an old folder would end up inside the renamed one
for p in "${ALLOLD[@]}"; do
  case "$(pwd -P)/" in "$p"/*) die "this terminal is inside $p: type  cd ~  and run the script again.";; esac
done

# ------------------------------------------------------------------------------------------ 1. is Strata stopped?
step "1. Is anything using those folders?"
busy=0
for p in "${ALLOLD[@]}"; do
  while read -r pid; do
    [ -n "$pid" ] || continue
    [ "$pid" = "$$" ] || [ "$pid" = "$PPID" ] && continue
    busy=1; warn "running: $(ps -o pid=,args= -p "$pid" | cut -c1-140)"
  done < <(pgrep -f -- "$(reesc "$p")/" 2>/dev/null; pgrep -f -- "$(reesc "$p")\$" 2>/dev/null)
done
[ "$busy" = 0 ] || die "stop Strata (and any download) first: Ctrl-C in its terminal, or  pkill -f serve/server.py  - then run this again."
ok "nothing running from the old folders"

# ------------------------------------------------------------------------------------------ 2. space and plan
step "2. The plan"
total=0; largest=0; have=0
for i in "${!NAMES[@]}"; do
  sz=$(du -sb -- "${OLDS[$i]}" | cut -f1); SIZES[$i]=$sz; total=$((total + sz))
  big=$(find "${OLDS[$i]}" -type f -printf '%s\n' 2>/dev/null | sort -n | tail -1); big=${big:-0}
  [ "$big" -gt "$largest" ] && largest=$big
  [ -d "${NEWS[$i]}" ] && have=$((have + $(du -sb -- "${NEWS[$i]}" | cut -f1)))
  printf '  %-12s %9s   %s  ->  %s\n' "${NAMES[$i]}" "$(human "$sz")" "${OLDS[$i]}" "${NEWS[$i]}"
done
avail=$(df -B1 --output=avail -- "$DEST" | tail -1 | tr -d ' ')
if [ "$MOVE" = 1 ]; then
  need=$((largest + 5 * 1024**3))
  say "  mode: MOVE (each source file is deleted once copied). Free space needed: about $(human "$need"); free: $(human "$avail")"
else
  rest=$((total - have)); [ "$rest" -lt 0 ] && rest=0
  need=$((rest + rest / 50 + 2 * 1024**3))
  say "  mode: COPY (the old folders are kept, renamed to .migrated at the end)."
  say "  total $(human "$total"); free on $DEST: $(human "$avail"); needed: about $(human "$need")"
fi
if [ "$avail" -lt "$need" ]; then
  if [ "$MOVE" = 1 ]; then die "not even enough room for one big file. Free some space on $DEST."; fi
  die "not enough free space on $DEST. Free up $(human $((need - avail))), or run again with MOVE=1 (see the warning at the top of this script)."
fi
if [ "$MOVE" = 1 ]; then
  warn "MOVE=1: sources are deleted as they are copied. If the machine dies half-way, rerun this script and it finishes the job."
fi
[ -e "$MARK" ] && say "  (resuming an earlier run)"

if [ "$YES" != 1 ]; then
  [ -t 0 ] || die "no terminal to ask on: run it with YES=1."
  printf '\nGo ahead? It can take a while (about 1 minute per 8 GB from a hard disk). [y/N] '
  read -r a; case "$a" in y|Y|yes|YES) ;; *) say "Nothing done."; exit 0;; esac
fi

# ------------------------------------------------------------------------------------------ 3. copy
step "3. Copying"
: > "$MARK" || die "cannot write $MARK"
for i in "${!NAMES[@]}"; do
  old="${OLDS[$i]}"; new="${NEWS[$i]}"
  say "  ${NAMES[$i]}: $old  ->  $new"
  mkdir -p -- "$new"
  # --chmod=Du+w: a read-only source folder (the doc makes the Huihui model folder read-only) is first created
  # writable, or rsync could not put files into it; a second quick pass puts the original modes back
  opts=(-a --partial --info=progress2 -h --chmod=Du+w)
  ro_list=""
  if [ "$MOVE" = 1 ]; then
    # read-only folders (the doc makes the Huihui model folder read-only) cannot be emptied: lift that while
    # moving, put it back afterwards
    ro_list=$(mktemp); find "$old" -type d ! -perm -u+w -printf '%P\n' > "$ro_list"
    find "$old" -type d ! -perm -u+w -exec chmod u+w {} +
    opts+=(--remove-source-files)
  fi
  rsync "${opts[@]}" -- "$old"/ "$new"/ || die "rsync failed on ${NAMES[$i]} (disk full? unplugged?). Fix it and run this script again: it resumes."
  if [ "$MOVE" != 1 ]; then
    rsync -a -- "$old"/ "$new"/ || die "rsync failed while restoring the folder permissions of ${NAMES[$i]}."
  else
    while IFS= read -r rel; do chmod a-w "$new/$rel"; done < "$ro_list"; rm -f "$ro_list"
    find "$old" -depth -type d -empty -delete 2>/dev/null
    [ -e "$old" ] && warn "$old still has files in it (not copied?): look at it before deleting anything."
  fi
  ok "${NAMES[$i]} copied"
done

if [ "$MOVE" != 1 ]; then
  step "3b. Comparing the copy with the original"
  bad=0
  for i in "${!NAMES[@]}"; do
    vopts=(-an --itemize-changes); [ "$CHECKSUM" = 1 ] && vopts+=(-c)
    diffs=$(rsync "${vopts[@]}" -- "${OLDS[$i]}"/ "${NEWS[$i]}"/ 2>&1 | head -10)
    if [ -n "$diffs" ]; then bad=1; warn "${NAMES[$i]} differs from the original:"; printf '%s\n' "$diffs" | sed 's/^/        /'
    else ok "${NAMES[$i]}: identical$([ "$CHECKSUM" = 1 ] && echo ' (contents compared)' || echo ' (names, sizes, dates)')"; fi
  done
  [ "$bad" = 0 ] || die "the copy is not identical to the original. Run this script again (it fixes what is missing); if it keeps saying that, tell me what is printed above."
fi

# ------------------------------------------------------------------------------------------ 4. rewrite the paths
step "4. Rewriting the old paths in the new copy"
NEW_STRATA="${NEWS[0]}"
PAIRS=""; ROOTS=""; FILES=""
for i in "${!NAMES[@]}"; do
  PAIRS+="${OLDS[$i]}"$'\t'"${NEWS[$i]}"$'\n'
  [ "${OLDRP[$i]}" != "${OLDS[$i]}" ] && PAIRS+="${OLDRP[$i]}"$'\t'"${NEWS[$i]}"$'\n'
  [ "${NAMES[$i]}" = huihui-qfn ] || ROOTS+="${NEWS[$i]}"$'\n'     # the Huihui download has no paths inside
done
if [ -f "$SETTINGS" ]; then
  [ -e "$SETTINGS.pre-migrate.bak" ] || cp -p -- "$SETTINGS" "$SETTINGS.pre-migrate.bak"
  FILES+="$SETTINGS"$'\n'
  ok "Strata's settings backed up to $SETTINGS.pre-migrate.bak"
fi

MIG_PAIRS="$PAIRS" MIG_ROOTS="$ROOTS" MIG_FILES="$FILES" python3 -I - <<'PY'
import os, re, stat, sys

pairs = [l.split("\t") for l in os.environ["MIG_PAIRS"].split("\n") if l]
roots = [l for l in os.environ["MIG_ROOTS"].split("\n") if l]
files = [l for l in os.environ["MIG_FILES"].split("\n") if l]
mapping = dict(pairs)
olds = sorted(mapping, key=len, reverse=True)
alt = "|".join(re.escape(o) for o in olds)
# an old path only counts when it is a whole path prefix: not part of a longer name (Strata vs Strata-data)
pat_s = re.compile(r"(?<![\w.\-])(" + alt + r")(?![\w.\-])")
olds_b = [os.fsencode(o) for o in olds]
pat_b = re.compile(rb"(?<![\w.\-])(" + b"|".join(re.escape(o) for o in olds_b) + rb")(?![\w.\-])")
map_b = {os.fsencode(k): os.fsencode(v) for k, v in mapping.items()}

SKIP_DIRS = {".git", "__pycache__"}
SKIP_PARTS = (".gguf", ".bin", ".safetensors", ".pyc", ".so", ".log", ".zip", ".whl", ".npy", ".pt",
              ".png", ".jpg", ".jpeg", ".gz", ".xz", ".zst", ".tar", ".a", ".o")
MAX = 64 << 20

patched, links, bins, fails, dangling = [], [], [], [], []

def fix_link(p):
    t = os.readlink(p)
    n = pat_s.sub(lambda m: mapping[m.group(1)], t)
    if n != t:
        tmp = p + ".migtmp"
        if os.path.lexists(tmp):
            os.remove(tmp)
        os.symlink(n, tmp)
        os.replace(tmp, p)
        links.append((p, t, n))
    if not os.path.exists(p):
        dangling.append((p, os.readlink(p)))

def fix_file(p):
    st = os.lstat(p)
    if stat.S_ISLNK(st.st_mode):
        return fix_link(p)
    if not stat.S_ISREG(st.st_mode) or st.st_size > MAX:
        return
    low = os.path.basename(p).lower()
    if any(low.endswith(e) or (e + ".") in low for e in SKIP_PARTS):
        return
    with open(p, "rb") as f:
        data = f.read()
    if not any(o in data for o in olds_b):
        return
    if b"\0" in data[:8192]:
        bins.append(p)
        return
    new = pat_b.sub(lambda m: map_b[m.group(1)], data)
    if new == data:
        return
    tmp = p + ".migtmp"
    try:
        with open(tmp, "wb") as f:
            f.write(new)
        os.chmod(tmp, st.st_mode & 0o7777)
        os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))   # keep dates: Strata picks the newest strata-*.json
        os.replace(tmp, p)
    finally:
        if os.path.lexists(tmp):
            os.remove(tmp)
    patched.append(p)

def guarded(p):
    try:
        fix_file(p)
    except Exception as e:                      # one bad file must not stop the rest
        fails.append((p, repr(e)))

for root in roots:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for d in dirnames:
            q = os.path.join(dirpath, d)
            if os.path.islink(q):               # a link to a folder: os.walk lists it but does not enter it
                guarded(q)
        for f in filenames:
            guarded(os.path.join(dirpath, f))
for p in files:
    guarded(p)

def show(title, items, fmt=str, n=8):
    if items:
        print("  %s: %d" % (title, len(items)))
        for x in items[:n]:
            print("        " + fmt(x))
        if len(items) > n:
            print("        ... and %d more" % (len(items) - n))

print("  text files rewritten: %d" % len(patched))
print("  symlinks re-pointed:  %d" % len(links))
show("symlinks that point nowhere", dangling, lambda x: "%s -> %s" % x)
show("BINARY files that still contain an old path (not touched; usually just a build-time string, harmless unless Strata fails to start)", bins)
show("FAILED", fails, lambda x: "%s: %s" % x)
sys.exit(2 if fails else 0)
PY
rc=$?
[ "$rc" = 0 ] && ok "paths rewritten" || warn "some files could not be rewritten (see FAILED above)"
PATCH_RC=$rc

# ------------------------------------------------------------------------------------------ 5. check
step "5. Checking the result"
CHECK_RC=0
NEWROOTS=""; for n in "${NEWS[@]}"; do NEWROOTS+="$n"$'\n'; done
MIG_PAIRS="$PAIRS" MIG_NEWROOTS="$NEWROOTS" MIG_STRATA="$NEW_STRATA" MIG_SETTINGS="$SETTINGS" python3 -I - <<'PY' || CHECK_RC=1
import glob, json, os, re, sys

pairs = [l.split("\t") for l in os.environ["MIG_PAIRS"].split("\n") if l]
newroots = [l for l in os.environ["MIG_NEWROOTS"].split("\n") if l]
strata = os.environ["MIG_STRATA"]
olds = sorted({o for o, _ in pairs}, key=len, reverse=True)
pat_old = re.compile(r"(?<![\w.\-])(" + "|".join(re.escape(o) for o in olds) + r")(?![\w.\-])")

problems, checked = [], 0

def parts(s):
    if s.startswith("-") and "=" in s:           # --flag=/some/path
        s = s.split("=", 1)[1]
    for q in s.split(":"):                       # PATH-style lists
        if q.startswith("/"):
            yield q

def check(s, where):
    global checked
    for q in parts(s):
        if pat_old.search(q):
            problems.append("still the OLD location  %s   (in %s)" % (q, where))
        elif any(q == r or q.startswith(r + "/") for r in newroots):
            checked += 1
            if not os.path.exists(q):
                problems.append("MISSING  %s   (in %s)" % (q, where))

def walk(o, where):
    if isinstance(o, dict):
        for v in o.values():
            walk(v, where)
    elif isinstance(o, list):
        for v in o:
            walk(v, where)
    elif isinstance(o, str):
        check(o, where)

jsons = sorted(glob.glob(os.path.join(strata, "strata-*.json")))
if os.path.isfile(os.environ["MIG_SETTINGS"]):
    jsons.append(os.environ["MIG_SETTINGS"])
for j in jsons:
    try:
        walk(json.load(open(j, encoding="utf-8-sig")), os.path.basename(j))
    except Exception as e:
        problems.append("cannot read %s: %r" % (j, e))
scripts = sorted(glob.glob(os.path.join(strata, "run-*.sh")))
for s in scripts:
    text = open(s, encoding="utf-8", errors="replace").read()
    for q in re.findall(r'"([^"\n]+)"', text) + re.findall(r"^cd (\S+)", text, re.M):
        check(q, os.path.basename(s))
for m in sorted(glob.glob(os.path.join(os.path.dirname(strata), "Strata-data", "packs", "*", "manifest.json"))):
    try:
        walk(json.load(open(m, encoding="utf-8")), "packs/%s/manifest.json" % os.path.basename(os.path.dirname(m)))
    except Exception as e:
        problems.append("cannot read %s: %r" % (m, e))

print("  %d config / run-script / settings / pack file(s) read, %d path(s) under the new location verified" %
      (len(jsons) + len(scripts), checked))
if not jsons or not scripts:
    problems.append("no strata-*.json or run-*.sh found in %s (was Strata ever set up there?)" % strata)
for p in problems[:25]:
    print("  !! " + p)
sys.exit(1 if problems else 0)
PY
[ "$CHECK_RC" = 0 ] && ok "every path in the configs exists, none points at the old place" || warn "see the lines above"

# the venv: not relocatable by magic, but a text rewrite of its scripts is enough
PYV="$NEW_STRATA/.venv/bin/python"
if [ -x "$PYV" ]; then
  vp=$("$PYV" -I -c 'import sys; print(sys.prefix)' 2>&1)
  if [ "$(rp "$vp" 2>/dev/null)" = "$(rp "$NEW_STRATA/.venv")" ]; then
    ok "the venv works from its new place ($vp)"
    pv=$("$PYV" -I -m pip --version 2>&1 | head -1)
    case "$pv" in *"$NEW_STRATA/.venv"*|*"$(rp "$NEW_STRATA/.venv")"*) ok "pip: $pv";; *) warn "pip says: $pv"; CHECK_RC=1;; esac
  else
    warn "the venv reports prefix '$vp' instead of $NEW_STRATA/.venv"; CHECK_RC=1
  fi
else
  warn "no $PYV (a Strata without .venv: ./setup.sh will create it)"
fi

# other places that may still mention the old locations (report only: they are yours)
step "6. Other places that mention the old folders (for you to fix, if any)"
found=0
cands=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_aliases" "$HOME/.bash_profile" "$HOME/.zprofile"
       "$HOME/.config/fish/config.fish")
for d in "$HOME/.config/systemd/user" "$HOME/.config/autostart" /etc/systemd/system; do
  [ -d "$d" ] && while IFS= read -r f; do cands+=("$f"); done < <(find "$d" -maxdepth 1 -type f 2>/dev/null)
done
for f in "${cands[@]}"; do
  [ -r "$f" ] || continue
  for p in "${ALLOLD[@]}"; do
    hits=$(grep -nF -- "$p" "$f" 2>/dev/null | head -3)
    [ -n "$hits" ] && { found=1; warn "$f"; printf '%s\n' "$hits" | sed 's/^/        /'; }
  done
done
if crontab -l 2>/dev/null | grep -qF -e "$OLD_STRATA" -e "$OLD_DATA" -e "$OLD_HUIHUI"; then found=1; warn "your crontab mentions an old folder (crontab -e)"; fi
[ "$found" = 0 ] && ok "none found in your shell files, systemd units, autostart or crontab (a '~/Strata' typed in a terminal history is harmless)"

# ------------------------------------------------------------------------------------------ 7. retire the old folders
step "7. Wrapping up"
NOTES="$DEST/MIGRATION-NOTES.txt"
RUN_SCRIPT=$(ls "$NEW_STRATA"/run-*.sh 2>/dev/null | head -1)
RENAMED=()
SUCCESS=1; [ "$PATCH_RC" = 0 ] && [ "$CHECK_RC" = 0 ] || SUCCESS=0

if [ "$MOVE" != 1 ] && [ "$SUCCESS" = 1 ]; then
  stamp=$(date +%Y%m%d-%H%M%S)
  for i in "${!NAMES[@]}"; do
    t="${OLDS[$i]}.migrated"; [ -e "$t" ] && t="$t-$stamp"
    mv -- "${OLDS[$i]}" "$t" && RENAMED[$i]="$t" && ok "renamed ${OLDS[$i]}  ->  $t"
  done
elif [ "$MOVE" = 1 ]; then
  ok "MOVE mode: the old folders are gone, nothing to clean up. Your only backup of Strata's settings is $SETTINGS.pre-migrate.bak"
elif [ "$MOVE" != 1 ]; then
  warn "NOT renaming your old folders, because a step above reported a problem. They are untouched; the new copy is in $DEST."
fi

{
  echo "Strata migration, $(date)"
  echo "new place: $DEST"
  echo
  echo "START IT (new place):"
  [ -n "$RUN_SCRIPT" ] && echo "  $RUN_SCRIPT"
  echo "  curl -s http://127.0.0.1:11434/v1/models -H \"Authorization: Bearer \$(. ~/.strata-key; echo \$STRATA_KEY)\""
  if [ "${#RENAMED[@]}" -gt 0 ] 2>/dev/null; then
    echo
    echo "UNDO (go back to the old places; the new copy stays where it is):"
    for i in "${!RENAMED[@]}"; do echo "  mv '${RENAMED[$i]}' '${OLDS[$i]}'"; done
    [ -f "$SETTINGS.pre-migrate.bak" ] && echo "  cp -p '$SETTINGS.pre-migrate.bak' '$SETTINGS'"
    echo
    echo "ONCE YOU ARE HAPPY (frees the old disk; the Huihui folder is read-only, hence the chmod):"
    all=""; for i in "${!RENAMED[@]}"; do all+=" '${RENAMED[$i]}'"; done
    echo "  chmod -R u+w$all && rm -rf$all"
  fi
} > "$NOTES"

say
if [ "$SUCCESS" = 1 ]; then
  printf '%sDone.%s Next, in a terminal:\n' "$G" "$N"
else
  printf '%sFinished with warnings.%s Read what is marked !! above. The commands below still apply:\n' "$Y" "$N"
fi
sed 's/^/  /' "$NOTES"
rm -f "$MARK"
say
say "(the same text is saved in $NOTES)"
[ "$SUCCESS" = 1 ]
