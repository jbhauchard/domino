# A fully local agent, how to

Strata runs the LLM on your PC. picoclaw (the "claw" agent) runs inside a smolBSD microVM and talks to Strata.
Everything on a gaming machine.

```
                                   your Ubuntu PC
 Inference Server                                       smolBSD microVM (smolClaw)
┌────────────────────────────────────┐         ┌───────────────────────────────────┐
│ Strata  0.0.0.0:11434/v1  ◄────────┼─────────┼─ picoclaw (the agent)             │
│ (Qwen3.8-Flash-Next on your GPU)   │         │   tools: shell, files, web search │
└────────────────────────────────────┘         └───────────────────────────────────┘
```

The plan: **0.** pick the disk for the big files → **1.** Strata → **2.** the microVM → **3.** plug the agent into Strata → **4.** skills, tools & a browser → **5.** Telegram → **6.** daily life (one command starts everything).

Every block says where it runs: **🖥️ on your PC** (the Ubuntu one) or **🦞 in the VM** (the prompt looks like `[~]@😈+🦞>`). Blocks are meant to be pasted whole. Where you must change something, the line says `EDIT`, and the block refuses to run until you did. Sections folded under a ▶ are optional, or for when something breaks.

## Why ? how ?

<details markdown="1">
<summary>Why not.</summary>

- You need an inference server that hosts LLMs, either locally or on someone's computer. llama.cpp or [Strata](https://github.com/Niko1221/Strata) are great for this. You need at least some GPU to infer at decent speed.

- Which LLM ? It depends. [llmfit](https://github.com/AlexsJones/llmfit) is a cool tool to help you decide if your GPU was worth the money.

- Where to get these models (the weights making a model interesting) ? Mostly from [ollama.com](https://ollama.com/search) or [huggingface.co](https://huggingface.co). Strata only runs the Qwen3.8-Flash-Next architecture; its installer offers several sizes of it. Other GGUFs of that same model, like [Huihui QFN](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF/tree/main), need a little help (see the Huihui part of the Strata chapter below). Other models, like [Huihui 27B](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF), need Ollama or llama.cpp.

- What to do with that? Have an agent that thinks like an AI, and uses tools to do real stuff with your real SSH key and your real money, wait what?

- Seriously, that's clawd/moltbot/openclaw/picoclaw/zeroclaw/nullclaw's job, it plugs a stochastic parrot into command-line tools (some are made by hackers to steal your credentials). You will let it search the internet, and it should be seen as a personal assistant.

- You can run it in a microVM: that's much better isolation than Docker, and it can boot faster than you blink.

- [smolBSD](https://github.com/NetBSDfr/smolBSD) is a great tool that fully boots a UNIX VM in about 10 ms. Its "smolClaw" flavor runs [picoclaw](https://github.com/sipeed/picoclaw) in a VM that can't see your files, unless you share them. It can still reach the internet and your local network, so don't give it secrets and it won't steal your stuff.

- nvtop monitors your new electric space heater's efficiency; llm-visuals is even fancier.

</details>

<details markdown="1">
<summary>Lexicon</summary>

In this context, we call:

- __Model__: a bunch of matrices (a big pile of numbers, 125 billion *parameters* for QwenFlashNext, chewing on (very) high-dimension vectors: thousands of dimensions each, 3D is for ants) turning text into a guess at the next word, again and again. The parameters for a non-deterministic text completion system.
- __Inference server__: software that loads the model's weights to turn them into a chatty API, one piece of the puzzle.
- __Claw\<thing>__ (here "__picoclaw__"): transforms the LLM into an agent. It sends your request to the model, runs the tools the model asks for, and feeds the results back. So if you ask it to draw you like one of its French girls, it actually knows the ComfyUI API exists.
- __SmolClaw__: a small, empty playground where the Claw\<thing> can play safely without destroying your life. From iMil's famous smolBSD.
- __Tools__: what the Claw\<thing> can do, e.g. "search DuckDuckGo", "run a shell command", "generate an image" or "build a .docx document". Some want to steal your stuff, be careful.
- __Skills__: mostly text that goes into the context (so keep it short) to explain precisely how to do certain things or how to call tools.
- __MCP__ (Model Context Protocol): a standard plug for tools. A little program (local, or a website) announces "here are my tools", and the agent can call them. Skills are the manual, MCP servers are the hands.
- __Gateway__: the part of picoclaw that connects chat apps (Telegram & co) to the agent, so you can talk to it from your phone.
- __Abliterated__: a model edited so that it (mostly) stops refusing things. Fun for fiction, less fun with a shell.
- __Maki__: a Coding agent. Like a Claw\<thing>, but you give it a local directory containing your code rather than the whole internet, and it makes more code. LLM-powered, with skills, tools and a permission system; smolBSD has a recipe for it too (`smolerfiles/SMOLerfile.maki`).
- __RAG__: unrelated here. Another database full of vectors, so you can store important "knowledge" and avoid having to put everything in your prompt or fetch it from the internet every time.

</details>

### "Nice to have" tools

<details markdown="1">
<summary>llmfit</summary>

Install [llmfit](https://github.com/AlexsJones/llmfit) (NOT by `curl | sh` !, pick one of the other methods in its README) and decide what fits on your hardware.

</details>

<details markdown="1">
<summary>nvtop</summary>

Monitor your GPU activity ([nvtop](https://github.com/Syllo/nvtop)):

```shell
sudo snap install nvtop
```

</details>

<details markdown="1">
<summary>llm-visuals</summary>

A nice display, in Rust ([llm-visuals](https://github.com/DingoOz/llm-visuals), you need [rustup](https://rustup.rs) first):

```shell
# Install with:
rustup update
git clone https://github.com/DingoOz/llm-visuals
cd llm-visuals
cargo install --path .
# Run:
llm-visuals
```

</details>

---

## 0. Where do the big files go?

The models weigh 100 GB and more, and from a hard disk they take minutes longer to load. See which of your disks is the fast one (`NVMe`) and how much room it has:

🖥️ **on your PC**

```shell
df -h --output=source,avail,target -x tmpfs -x devtmpfs -x squashfs -x efivarfs -x overlay | tail -n +2 | while read -r src avail tgt; do
  case "$tgt" in /boot*|/snap*|/run*) continue;; esac
  d=$(lsblk -srno NAME,TYPE "$src" 2>/dev/null | awk '$2=="disk"{print $1; exit}')
  case "$d" in
    "")    k="?" ;;
    nvme*) k="NVMe (fast)" ;;
    *)     if [ "$(cat "/sys/block/$d/queue/rotational" 2>/dev/null)" = 1 ]; then k="hard disk (slow)"; else k="SSD"; fi ;;
  esac
  printf '%-10s %7s free  %-17s %s\n' "${d:-?}" "$avail" "$k" "$tgt"
done
```

It prints something like this (here `/` is the NVMe and `/home` an old hard disk):

```
nvme0n1       612G free  NVMe (fast)       /
sda           1.2T free  hard disk (slow)  /home
```

Pick a folder on the fast one: about 80 GB for the stock model, about 105 GB more for Huihui. Mine is `/AI/LLM`. This creates it and remembers it in `~/.llm-dir`, which the next blocks read:

🖥️ **on your PC**

```shell
LLM_DIR=/AI/LLM      # EDIT: a folder on your fast disk (only one disk? $HOME/LLM is fine)
if mkdir -p "$LLM_DIR" 2>/dev/null && [ -w "$LLM_DIR" ]; then
  LLM_DIR=$(readlink -f "$LLM_DIR") && printf 'LLM_DIR=%q\n' "$LLM_DIR" > ~/.llm-dir
  echo "OK: the big files go to $LLM_DIR ($(df -h --output=avail "$LLM_DIR" | tail -1 | tr -d ' ') free)."
else
  echo "Can't write to $LLM_DIR. Once, as root:  sudo mkdir -p $LLM_DIR && sudo chown $USER: $LLM_DIR   then paste this block again."
fi
```

<details markdown="1">
<summary>Already installed in your home folder? Move it</summary>

Stop Strata, then run [migrate-llm.sh](migrate-llm.sh) (it sits next to this document). It copies `~/Strata`, `~/Strata-data` and `~/huihui-qfn` to the new place, rewrites the absolute paths Strata keeps in its configs, checks the result, and only renames (never deletes) your old folders to `*.migrated`. Short on disk space? Put `MOVE=1` in front: it moves instead of copying.

🖥️ **on your PC**

```shell
cd ~ && . ~/.llm-dir && bash migrate-llm.sh "$LLM_DIR"
```

</details>

---

## 1. Install an Inference server

Install Strata (or ollama or _liteLLM_ or _vLLM_, if you know what you're doing...)

### Strata (preferable)

[Strata](https://github.com/Niko1221/Strata) wants a GPU with 12 GB of VRAM or more, 32 GB+ of RAM, and about 80 GB of free disk. It speaks the OpenAI API (`/v1`) and Anthropic's (`/v1/messages`).

We put it on port 11434 (Ollama's usual port) instead of its default 8080, so Ollama, if you have it, must not run. Strata also needs a working NVIDIA driver (version 580 or newer; the one from Ubuntu's own repository is fine). This frees the port and checks that your driver answers:

🖥️ **on your PC**

```shell
sudo systemctl disable --now ollama 2>/dev/null || true   # frees port 11434 (does nothing if you never had Ollama)
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
```

You want a line with your card, its memory and the driver version, something like `NVIDIA GeForce RTX 3090, 24576 MiB, 580.95.05`. An error instead (`Driver/library version mismatch`, `command not found`, `couldn't communicate with the NVIDIA driver`)? Open the fold below, fix it, then come back.

<details markdown="1">
<summary>nvidia-smi fails ("Driver/library version mismatch"), or Strata stops on "no NVIDIA GPU found"</summary>

The NVIDIA driver has two halves: a kernel module (loaded at boot) and the user-space libraries. This error means the two are not the same version. It usually happens after an `apt upgrade` replaced the libraries while the old module was still loaded, or when a driver downloaded from nvidia.com (the `.run` file) got mixed with Ubuntu's packages.

**1. Reboot.** This fixes it most of the time:

🖥️ **on your PC**

```shell
sudo reboot
```

Then run the `nvidia-smi` check above again.

**2. Still broken? See what is installed and what is loaded:**

🖥️ **on your PC**

```shell
echo "== kernel module loaded now:";           head -1 /proc/driver/nvidia/version 2>/dev/null || echo "   none"
echo "== kernel module installed on disk:";     modinfo -F version nvidia 2>/dev/null || echo "   none"
echo "== NVIDIA packages:";                     dpkg -l 2>/dev/null | awk '/^ii +(nvidia-driver|nvidia-dkms|nvidia-kernel|libnvidia-compute|linux-modules-nvidia)/{print "  ", $2, $3}'
echo "== Ubuntu recommends:";                   nvidia-detector 2>/dev/null || echo "   (sudo apt install ubuntu-drivers-common)"
echo "== Secure Boot:";                         mokutil --sb-state 2>/dev/null || echo "   (mokutil not installed)"
```

The module loaded and the packages must show the same version number. "none loaded" while a module exists on disk means the kernel refused it at boot, very often because of Secure Boot.

**3. Reinstall one clean driver from Ubuntu's repository** (your screen may fall back to a basic resolution until the reboot, that's normal):

🖥️ **on your PC**

```shell
if command -v nvidia-uninstall >/dev/null; then sudo nvidia-uninstall; fi   # only exists if you used NVIDIA's .run installer
sudo apt update
sudo apt purge -y '^nvidia-.*' '^libnvidia-.*' '^linux-modules-nvidia-.*'
sudo apt autoremove -y
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers install   # installs the one `nvidia-detector` recommends
sudo reboot
```

If Secure Boot is on, apt may ask for a one-time password. Remember it: at the next boot a blue screen ("MOK management") appears, choose "Enroll MOK", "Continue", "Yes", and type that password. Without it the kernel refuses the module and `nvidia-smi` stays broken.

When `nvidia-smi` prints your card, paste the install block below. It picks up where it stopped: it reuses your key and the Strata folder, and Strata skips what is already done.

</details>

Copy/Paste/run to install Strata and configure it:

🖥️ **on your PC**

```shell
. ~/.llm-dir          # chapter 0: where the big files go
STRATA_HOST=0.0.0.0   # reachable from the VM and your other devices (127.0.0.1 would NOT work for the VM)
STRATA_PORT=11434
# We use a key, optional but recommended as Strata will be quite open otherwise. Pasting this block again reuses the same one.
[ -s ~/.strata-key ] && . ~/.strata-key
[ -n "$STRATA_KEY" ] || STRATA_KEY=$(openssl rand -hex 24)
printf 'STRATA_KEY=%s\n' "$STRATA_KEY" > ~/.strata-key && chmod 600 ~/.strata-key
printf 'Write that down !\nSTRATA_KEY=%s\n(also saved in ~/.strata-key)\n' "$STRATA_KEY"

cd "${LLM_DIR:?do chapter 0 first}" && { [ -d Strata ] || git clone https://github.com/Niko1221/Strata; } && cd Strata &&
./setup.sh --setup --host "$STRATA_HOST" --port "$STRATA_PORT" --api-key "$STRATA_KEY" --data-dir "$LLM_DIR/Strata-data" --no-browser
```

It asks which model size, how much context and if it should read pictures: Enter gives the recommended answer. Then it downloads ~70 GB into `$LLM_DIR/Strata-data` and starts (`--no-browser`: it won't open its own chat page every time). It keeps the terminal: leave it there and open another one for the rest. Next time you don't need to remember anything: chapter 6 starts it for you (by hand it is `. ~/.llm-dir; cd "$LLM_DIR/Strata" && ./setup.sh`).

<details markdown="1">
<summary>It stops on "error: calling a __device__ function ... __half_as_ushort" (the engine does not compile)</summary>

On Ubuntu, Strata compiles its engine itself, with the CUDA 12.0 that comes from apt (its log says `build tools present (CUDA 12.0)`). Since Strata 0.1.45 (October 2026) one debug print in `src/qwen35/q36_engine.cu` calls a CUDA function that this old toolkit only accepts on the GPU side, so the compile stops with:

```
src/qwen35/q36_engine.cu(1659): error: calling a __device__ function("__half_as_ushort(    ::__half)") from a __host__ function("verify_q8") is not allowed
```

This is a bug in Strata (newer CUDA toolkits accept the line), not something you did. What you see depends on the moment: on a **fresh install** the setup stops (`Setup stopped`). On an **update** (`./update.sh`, or a `./setup.sh` after a `git pull`) Strata says `could not compile the updated engine: starting the installed one`: nothing is lost and the old engine keeps working, but each start tries the compile again, for a few minutes, and fails again.

The fix is one line, in that debug print only (the model and its answers are not touched). Paste this; pasting it twice is harmless, and it says so when there is nothing left to fix:

🖥️ **on your PC**

```shell
. ~/.llm-dir
F="${LLM_DIR:?do chapter 0 first}/Strata/src/qwen35/q36_engine.cu"
if grep -q '__half_as_ushort(__float2half(t\[0\]))' "$F"; then
  sed -i 's/(unsigned) __half_as_ushort(__float2half(t\[0\]))/(unsigned) ((__half_raw) __float2half(t[0])).x/' "$F" &&
  echo "FIXED. Fresh install: paste the install block above again (it resumes). Existing install: cd \"\$LLM_DIR/Strata\" && ./update.sh"
else
  echo "Nothing to fix: that line is not in your Strata (fixed upstream?). If the error is the same, report it at https://github.com/Niko1221/Strata/issues"
fi
```

The compile then takes a few minutes. Later, as soon as Strata changes that same file (it does so often, and a fix for this bug would too), `./update.sh` stops with "Your local changes ... would be overwritten" and updates nothing. Give the file back first, then update:

🖥️ **on your PC**

```shell
. ~/.llm-dir; cd "$LLM_DIR/Strata" && git checkout -- src/qwen35/q36_engine.cu && ./update.sh
```

If the same error comes back, Strata has not fixed it yet: paste the fix block again.

</details>

#### Check that it answers

In another terminal on your PC. This asks Strata for its model, and prints the two lines the VM will need in chapter 3 (your PC's address on your home network, and the key). Keep that output at hand:

🖥️ **on your PC**

```shell
. ~/.strata-key
PC_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
echo "== Strata's model (an id below means it works):"
curl -s --max-time 10 http://127.0.0.1:11434/v1/models -H "Authorization: Bearer $STRATA_KEY" | grep -o '"id": *"[^"]*"' || echo "   no answer yet: still loading? see the fold below"
echo
echo "== For chapter 3, the first two lines of the VM block:"
echo "PC_IP=${PC_IP:-NO-NETWORK}"
echo "STRATA_KEY=$STRATA_KEY"
```

Your router may hand out another address to your PC after a reboot: give it a fixed one (a "DHCP reservation" in the router), or redo this block and the config of chapter 3 when it changes.

<details markdown="1">
<summary>Already have Strata? Or no answer? Listening checks and the firewall</summary>

If you already have Strata installed, edit `strata-<model>.json` in the Strata folder and set (then restart):

```json
"port": 11434,
"host": "0.0.0.0",
"api_key": "<your key>",
```

Who is it listening to?

🖥️ **on your PC**

```shell
ss -tlnp | grep 11434
```

BAD (only your PC can talk to it, the VM can't):

```
LISTEN 0      4096             127.0.0.1:11434      0.0.0.0:*
```

GOOD:

```
LISTEN 0      4096               0.0.0.0:11434      0.0.0.0:*
```

From your other devices it's `http://<your-pc-ip>:11434/v1` with the key. If ufw is on, open it to your LAN only (adjust the range). The VM itself doesn't need this rule, its traffic comes from your PC:

🖥️ **on your PC**

```shell
sudo ufw allow from 192.168.0.0/16 to any port 11434 proto tcp
```

Note: same port as Ollama, but not the same language. Strata speaks OpenAI's API (`/v1/...`), not Ollama's (`/api/chat`, `/api/tags`). In your apps, pick "OpenAI-compatible", not "Ollama".

</details>

### Another model: Huihui QFN

<details markdown="1">
<summary>Huihui QFN (abliterated) instead of the stock model</summary>

[Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF) is Qwen3.8-Flash-Next with the refusals "abliterated" (v2: the ablation was adjusted, no expert touched), quantized the way Unsloth does. It comes in the same two sizes as the "Unsloth" entry of Strata's menu, so Strata can run it, no hand-made pack needed (the `docs/ORCA.md` manual workflow is for OrcaRouter's different file). Its [model card](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF) calls the abliteration method crude, a proof of concept, and recommends research and controlled environments (license `qwen-community-1.0`). With an agent that has a shell, your VM is the only guardrail left: keep it empty.

| Size | Download | Needs | Status in Strata |
| --- | --- | --- | --- |
| `UD-IQ4_XS` | 94 GB, 3 files | 48 GB+ of RAM (from ~80 GB, all the experts stay in RAM; below, part is read from the SSD) | regular choice |
| `UD-Q4_K_XL` | 111 GB, 4 files | 48 GB+ of RAM, an NVMe SSD, an NVIDIA GPU, no images | experimental |

Start with `UD-IQ4_XS`. The files are in the repository's `unsloth-UD-IQ4_XS/` and `unsloth-UD-Q4_K_XL/` folders. This install replaces nothing: it is one more model in Strata, with its own start script. Only one runs at a time on port 11434.

**The catch:** Strata pins the SHA-256 of *Unsloth's own* files, and stops on any file with their names that doesn't match (older versions deleted it). Huihui's files have the same names and other contents, so the check must be skipped for this one install (the model card says so too, and suggests editing `setup.py`). Below is the small, reversible version: a one-line guard that only does something when you set `HUIHUI_SKIP_SHA256=1`, removed again right after. Strata still checks that every file is complete.

**Step 1, check and download** in one block (RAM, disk, no stock Unsloth pack in the way, then the download). The download is resumable: if it stops, paste the block again; it takes a while. It uses Hugging Face's `hf` tool in its own little environment:

🖥️ **on your PC**

```shell
. ~/.llm-dir
QUANT=UD-IQ4_XS      # EDIT only for the bigger one: UD-Q4_K_XL (see the table above)
L="${LLM_DIR:?do chapter 0 first}"
P="$L/Strata-data/packs/unsloth-$(echo "$QUANT" | tr 'A-Z' 'a-z')"
echo "RAM, GB (48+ needed):  $(free -g | awk '/^Mem:/{print $2}')"
echo "Free disk in $L, GB (about 105 for IQ4_XS, 125 for Q4_K_XL):  $(df -BG --output=avail "$L" | tail -1 | tr -dc 0-9)"
if [ -d "$P" ]; then
  echo "STOP: Strata already has a pack $P"
  echo "If it is the stock Unsloth one, it would be reused instead of Huihui's: move it away, then paste this block again:"
  echo "  mv $P $P.stock"
  echo "If it is from an earlier Huihui install, you can go straight to step 2."
else
  sudo apt install -y python3-venv &&
  python3 -m venv ~/hf-venv && ~/hf-venv/bin/pip install -q -U huggingface_hub &&
  ~/hf-venv/bin/hf download huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF \
    --include "unsloth-$QUANT/*" --local-dir "$L/huihui-qfn" &&
  ls -l "$L/huihui-qfn/unsloth-$QUANT"
fi
```

(IQ4_XS needs Strata 0.1.39 or newer, which any Strata installed with this guide is: there is no need to update it for this.) You should see 3 `.gguf` files for IQ4_XS (about 11 MB, 49.8 GB and 43.8 GB) or 4 for Q4_K_XL (11 MB, 49.9, 49.4 and 12.1 GB). If you want to be thorough, `sha256sum "$LLM_DIR"/huihui-qfn/unsloth-$QUANT/*.gguf` (a few minutes) and compare with the SHA256 Hugging Face shows on each file's page.

**Step 2, install and start** in one block: it adds the one-time guard to `setup.py`, lets Strata's setup do the rest using your files in place (engine, pack, draft layer, config, start script), puts `setup.py` back, protects the files, and starts the model. Stop the other Strata model first (only one runs on port 11434). Enter gives the recommended answers (context, images):

🖥️ **on your PC**

```shell
. ~/.llm-dir
. ~/.strata-key      # your STRATA_KEY
QUANT=UD-IQ4_XS      # same as in step 1
L="${LLM_DIR:?do chapter 0 first}"
cd "$L/Strata" &&
python3 - <<'EOF' &&
import pathlib, re, shutil, sys
p, o = pathlib.Path("setup.py"), pathlib.Path("setup.py.orig")
t = p.read_text(encoding="utf-8")
guard = ('    if os.environ.get("HUIHUI_SKIP_SHA256") == "1":\n'
         '        return   # one-off: Huihui files are not Unsloth\'s\n')
if "HUIHUI_SKIP_SHA256" in t:
    if o.exists():
        print("setup.py already patched (an earlier run was interrupted): going on")
        sys.exit(0)
    print("STOP: setup.py is patched but setup.py.orig is gone: run  git checkout setup.py  here, then paste again")
    sys.exit(1)
m = re.search(r"^def verify_sha256\(.*\) -> None:\n", t, re.M)
if m is None:
    print("STOP: setup.py has changed, do not patch blindly (ask for help)")
    sys.exit(1)
shutil.copy2(p, o)
p.write_text(t[:m.end()] + guard + t[m.end():], encoding="utf-8")
print("setup.py patched (the original is kept as setup.py.orig)")
EOF
( trap 'mv -f setup.py.orig setup.py && echo "setup.py restored"' EXIT
  HUIHUI_SKIP_SHA256=1 ./setup.sh --setup --family unsloth --model "$QUANT" \
    --gguf-dir "$L/huihui-qfn/unsloth-$QUANT" --data-dir "$L/Strata-data" \
    --host 0.0.0.0 --port 11434 --api-key "$STRATA_KEY" --no-browser --no-start ) &&
chmod a-w "$L/huihui-qfn/unsloth-$QUANT" &&
cp "strata-unsloth-$(echo "$QUANT" | tr 'A-Z' 'a-z').json" "$L/huihui-qfn/strata-$QUANT.json.keep" &&
"./run-unsloth-$(echo "$QUANT" | tr 'A-Z' 'a-z').sh"
```

Press Ctrl-C by mistake during the install? The `trap` puts `setup.py` back anyway. The setup writes `strata-unsloth-ud-iq4_xs.json` and `run-unsloth-ud-iq4_xs.sh` next to `setup.py` (`ud-q4_k_xl` for the other size). The `chmod a-w` is for your 94 GB: without write access to that folder, a future Strata update that re-checks the hashes can't delete them, it just complains. The last `cp` keeps a copy of the config in `huihui-qfn/` (see just below why).

**Careful, this model has the stock model's name.** Strata names it `unsloth-ud-iq4_xs`, like its own "Unsloth" choice, so a plain `./setup.sh --setup` where you pick "Unsloth" **overwrites this config with the stock files** (the weights stay untouched). To change Huihui's settings or redo its diagnostics, paste step 2 again instead: it is that same setup, aimed at your files. Overwritten anyway? The copy that step 2 made (`huihui-qfn/strata-UD-IQ4_XS.json.keep`) is the config as it was: copy it over `Strata/strata-unsloth-ud-iq4_xs.json` (for the other size, `UD-Q4_K_XL` and `ud-q4_k_xl`).

The VM sees no change: same address, same key. Check with the "Check that it answers" block above (the model's name is now `qwen3.8-flash-next-unsloth-ud-iq4_xs`, picoclaw doesn't care). With two models installed, `./setup.sh` asks which one to start: to go back to the stock model, stop this one and pick the other.

**Already overwritten?** (the run script now starts the stock files, and you have no copy of the config.) Two ways back, both safe to paste twice. The first is step 2 again, as said: it writes a new config from your Huihui files. The second only points the existing config back at them and keeps everything else that Strata just wrote into it (the context, the settings found by its diagnostics): it looks for the model files named in the config's `args`, swaps each one for the same-named file in your Huihui folder, and saves the old config as `.bak` first:

🖥️ **on your PC**

```shell
. ~/.llm-dir
QUANT=UD-IQ4_XS      # same as in step 1
python3 - "${LLM_DIR:?do chapter 0 first}" "$QUANT" <<'EOF'
import json, os, pathlib, shutil, sys
L, quant = pathlib.Path(sys.argv[1]), sys.argv[2]
cfg_path = L / "Strata" / f"strata-unsloth-{quant.lower()}.json"
mine = L / "huihui-qfn" / f"unsloth-{quant}"
if not cfg_path.is_file() or not mine.is_dir():
    sys.exit(f"STOP: need {cfg_path} and the folder {mine}")
cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
args, changed = cfg["args"], 0
for i, a in enumerate(args):
    if isinstance(a, str) and a.endswith(".gguf") and pathlib.Path(a).parent != mine:
        new = mine / pathlib.Path(a).name
        if not new.is_file():
            sys.exit(f"STOP: {new} does not exist (is the download complete? step 1)")
        print(f"{args[i - 1]}:\n   was {a}\n   now {new}")
        args[i], changed = str(new), changed + 1
if not changed:
    sys.exit("Nothing to change: the config already points at the Huihui files.")
shutil.copy2(cfg_path, str(cfg_path) + ".bak")
tmp = pathlib.Path(str(cfg_path) + ".tmp")
tmp.write_text(json.dumps(cfg, indent=1), encoding="utf-8")
os.replace(tmp, cfg_path)
print(f"Done: {changed} path(s) changed, the old config is {cfg_path}.bak. Start it with ./run-unsloth-{quant.lower()}.sh")
EOF
```

If the stock setup also downloaded the regular Unsloth files (94 GB), the `was` lines above show their folder, and `du -sh` on it tells. Once the Huihui model runs, you can delete the `*-of-0000?.gguf` shards there to get the space back, but keep the `mmproj` file if the config's `vision` part names it: that is the image encoder.

To remove it:

🖥️ **on your PC**

```shell
. ~/.llm-dir && L="${LLM_DIR:?do chapter 0 first}" &&
{ chmod -R u+w "$L/huihui-qfn" || true; } &&
rm -rf "$L/huihui-qfn" "$L"/Strata-data/packs/unsloth-ud-* &&
rm -f "$L"/Strata/strata-unsloth-ud-* "$L"/Strata/run-unsloth-ud-*
```

Prefer not to touch `setup.py` at all? Strata documents a by-hand route for this file format in its [UNSLOTH_Q4.md](https://github.com/Niko1221/Strata/blob/main/docs/UNSLOTH_Q4.md) (pack with `tools/iq_pack.py --compat-bf16`, then a hand-written config). Longer, but nothing to restore.

</details>

### (Old) Ollama, not needed if you're running Strata

<details markdown="1">
<summary>Procedure to configure Ollama instead</summary>

Heads up: Ollama has no API key. On 0.0.0.0, anyone on your network can use it. Install it from [ollama.com/download/linux](https://ollama.com/download/linux) first (it creates the `ollama` systemd service). The script below is the "update by hand" version, check its paths against that page if you change anything.

🖥️ **on your PC**

```shell
sudo apt install -y zstd curl
# This creates a script (install/update + restart)
cat <<'EOF' >launch_ollama.sh
#!/bin/sh
set -e
sudo systemctl stop ollama
sudo rm -rf /usr/local/lib/ollama
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst | zstd -d - | \
    sudo tar xvf - -C /usr/local
# no "export OLLAMA_HOST" here: systemd ignores your shell's variables, see the override below
sudo systemctl start ollama
sudo systemctl status ollama
EOF

# this makes the script executable
chmod +x launch_ollama.sh
```

(`<<'EOF'` with quotes matters: without them the shell eats the `\` at the end of the `curl` line.)

#### Edit the service's conf so it's 0.0.0.0 every time `ollama` starts:

Edit the systemd service override (better than editing `/etc/systemd/system/ollama.service`, which updates overwrite):
`sudo systemctl edit ollama`

Add:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"

# rest is optional, it comes from Yorzian
# OLLAMA_ORIGINS=* lets any web page you visit call your Ollama, only if you need it
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_CONTEXT_LENGTH=16384"
Environment="OLLAMA_NEW_ENGINE=1"
```

then

```shell
sudo systemctl daemon-reload
```

#### Run the ollama

(serves ollama on ~~localhost~~ 0.0.0.0:11434 thanks to the override)

```shell
./launch_ollama.sh
```

#### Pull the model you see fit

Go to [ollama.com/search](https://ollama.com/search) and copy the name of the model you want, then either pull it, or run it (it will pull it if not already here)

Note that you need a "tool-able" model, which means it'll "know" to use some key words that trigger the tool calling provided by _claw\<thing>_

```shell
ollama pull gpt-oss:20b
# or
ollama run seamon67/GPT-OSS-Heretic:120b
# or
ollama pull qwen3.5:4b-q4_K_M

# to list the models you have:
ollama list

# check config
ollama serve --help
# for example      OLLAMA_HOST                IP Address for the ollama server (default 127.0.0.1:11434)
```

#### Check that ollama is properly listening

```shell
ss -tlnp | grep 11434
```

BAD:

```
LISTEN 0      4096             127.0.0.1:11434      0.0.0.0:*
```

HOW TO FIX: the override above wasn't applied. `sudo systemctl edit ollama` again, then

```shell
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

(maybe even `sudo ufw allow from 192.168.0.0/16 to any port 11434 proto tcp`)

GOOD:

```
LISTEN 0      4096                     *:11434            *:*
```

THEN RUN IT
Example:

```shell
ollama pull qwen3.5:4b-q4_K_M
# then, in another shell
ollama ps
```

```
NAME                 ID              SIZE      PROCESSOR    CONTEXT    UNTIL
qwen3.5:4b-q4_K_M    2a654d98e6fb    6.5 GB    100% GPU     16384      4 minutes from now
```

With Ollama, in the rest of this doc: the key can be any non-empty string like `-`, and the model line of the picoclaw config becomes `"model": "ollama/qwen3.5:4b-q4_K_M"`.

</details>

---

## 2. Install smolCLAW

Follow that nice tutorial from [smolBSD](https://github.com/NetBSDfr/smolBSD/tree/main/service/clawd) (or just this).

The VM is just giving tools to the chatbot, not running the chatbot itself (Strata does that, on your GPU). It doesn't need a lot of resources (here, 2 CPU cores, 1024 MB of RAM), but it does need to be isolated from your life ! So we share one dedicated folder, `~/smolBSD/share`, and nothing else.

It is a VM, so your computer must agree to run one (KVM). This one block checks that first (if it stops there, the first fold below explains the fix), then installs the tools, fetches the VM image and boots it. The first time it takes a few minutes (the `pull` also fetches the little `oras` tool into `smolBSD/bin/` by itself):

🖥️ **on your PC**

```shell
if [ ! -w /dev/kvm ]; then
  echo "STOP: no usable /dev/kvm (virtualization is off, or it isn't yours to use): see the first fold below, then paste this block again"
else
  sudo apt install -y curl git bmake qemu-system-x86 uuid-runtime binutils libarchive-tools gdisk socat jq lsof picocom tmux &&
  cd ~ && { [ -d smolBSD ] || git clone https://github.com/NetBSDfr/smolBSD; } && cd smolBSD &&
  mkdir -p share &&
  ./smoler.sh pull clawd-amd64:latest &&
  ./smoler.sh run clawd-amd64:latest -c 2 -m 1024 -w "$HOME/smolBSD/share"
fi
```

(Rather build the image yourself than pull it? Replace the `pull` line with `./smoler.sh build -y smolerfiles/Dockerfile.clawd`, a few minutes.)

**This terminal now IS the VM.** Open another one for anything marked "on your PC". You land in a `tmux` as user `clawd`. `exit` in every pane shuts the VM down. Next time, you don't paste this block again: chapter 6 starts everything with one command. These are the only tmux keys you really need (press `Ctrl-b`, let go, then the key):

| Keys | What it does |
| --- | --- |
| `Ctrl-b c` | new window (a second terminal in the VM, e.g. for `picoclaw gateway`) |
| `Ctrl-b n` / `Ctrl-b p` | next / previous window (`Ctrl-b 0` ... `9`: window number N) |
| `Ctrl-b w` | a list of the windows to pick from |
| `Ctrl-b \|` and `Ctrl-b -` | split the window side by side / top and bottom (in this VM only: tmux's own keys are `%` and `"`) |
| `Ctrl-b` + an arrow | go to the pane on that side |
| `Ctrl-b z` | zoom the pane to the whole window, again to go back |
| `Ctrl-b [` | scroll back: arrows or PageUp, `q` to leave. The mouse wheel usually does not scroll tmux's history. |
| `Ctrl-b d` | detach: leave and let everything keep running (`tmux attach` brings you back). On your PC only: in the VM, just leave the window open |
| `Ctrl-b ,` | rename the window |
| `Ctrl-b x` | close the pane (asks `y`) |

On your PC, the same table works for the `agent` session of chapter 6, with `Ctrl-a` instead of `Ctrl-b` (so the two never fight when one tmux runs inside the other). Outside tmux: `tmux ls` lists the sessions, `tmux attach -t agent` goes back to one.

Inside the VM the shared folder is mounted at:

```
/mnt
```

The agent can read and write everything in there. A dedicated folder, never your home!

<details markdown="1">
<summary>STOP on the KVM check? No /dev/kvm, or "permission denied"?</summary>

Check what your PC says: `grep -Ec '(vmx|svm)' /proc/cpuinfo` (0 = the CPU feature is off or missing) and `ls -l /dev/kvm`. You might have to reboot into BIOS and enable "Intel VT-x" or "AMD-V" (sometimes called "SVM Mode"). It's usually under CPU settings or Advanced. If the CPU is fine but `/dev/kvm` is missing, `sudo modprobe kvm_intel` (or `kvm_amd`). If `/dev/kvm` is there but you get "permission denied": `sudo usermod -aG kvm $USER`, then log out and back in.

</details>

<details markdown="1">
<summary>Example of iMil's conf: ports and SSH (handy, optional)</summary>

The ports are already forwarded, they're in `etc/clawd.conf` (it comes with smolBSD, don't overwrite it):

| Your PC | VM | What |
| --- | --- | --- |
| 2289 | 22 | SSH: `ssh -p 2289 clawd@localhost` |
| 18800 | 18800 | picoclaw's web UI |
| 18789 | 18789 | picoclaw's gateway (only if you move it there, see the gateway part) |

QEMU opens them on all your PC's interfaces, so your LAN can knock too. Firewall them if you don't want that.

SSH is worth it: pasting big blocks in SSH is much more reliable than in the VM's console. For SSH, put your **public** key in `share/` before building:

🖥️ **on your PC** (`ls ~/.ssh/*.pub` to see what you have, `ssh-keygen -t ed25519` if nothing)

```shell
cd ~/smolBSD
cp ~/.ssh/id_ed25519.pub share/ssh.pub   # or id_rsa.pub
./smoler.sh build -y smolerfiles/Dockerfile.clawd
./smoler.sh run clawd-amd64:latest -c 2 -m 1024 -w "$HOME/smolBSD/share"
```

(or, in the running VM: `mkdir -p ~/.ssh && cat >~/.ssh/authorized_keys`, paste your public key, Ctrl-D, `chmod 600 ~/.ssh/authorized_keys`. Gone at the next rebuild.)

</details>

<details markdown="1">
<summary>What's in the VM, and which picoclaw is it?</summary>

bash (not brew, brew doesn't do NetBSD), git, curl, python + pip + uv, vim, jq, ripgrep, fd, w3m and gh. The package manager is `pkgin`: to add something for good, add it to the `RUN pkgin ... in` line of `smolerfiles/Dockerfile.clawd` and rebuild. A rebuild wipes the VM, so save `~/.picoclaw` first if you care about it: chapter 3 has a one-paste script for that ("Save and restore the agent"), or just `cp -a ~/.picoclaw /mnt/picoclaw-backup`.

picoclaw itself is a NetBSD build from [afjcjsbx's releases](https://github.com/afjcjsbx/picoclaw/releases) of [sipeed/picoclaw](https://github.com/sipeed/picoclaw), and the VM updates it at every boot (`picoclaw-install`). So the version moves; check yours with `picoclaw version`.

</details>

## 3. Begin onboarding

(aka giving your home's keys to your new -potentially stupid or nefarious- pet)

### Once the microVM has started

```
➡️  setup picoclaw: picoclaw onboard
➡️  start picoclaw gateway: picoclaw gateway
➡️  or: picoclaw-launcher -public for a web GUI at http://127.0.0.1:18800
[~]@😈+🦞>
```

Run:

🦞 **in the VM**

```shell
picoclaw onboard
```

It writes a default config in `~/.picoclaw/config.json` and a workspace in `~/.picoclaw/workspace` (with the built-in skills). If it asks questions, take the defaults, we edit the config right after: you tell picoclaw about Strata there.

Strata listens on http://0.0.0.0:11434 _somewhere_ but not in the smolBSD VM. In the VM, **edit the first three lines** and paste. The first two are the lines the "Check that it answers" block of chapter 1 printed for you. This one block sets up everything the agent needs to start: the model, web search, a leash (see the fold below), and a few house rules for the small model. It keeps a dated backup of your config, changes only these bits, can be pasted again any time, and ends by asking Strata for its model from inside the VM, which proves the whole path works:

🦞 **in the VM**

```shell
PC_IP=192.168.x.x                 # EDIT: your PC's address, like 192.168.1.53 (printed by chapter 1)
STRATA_KEY=PUT-YOUR-KEY-HERE      # EDIT: Strata's key (printed there too). With Ollama: -
MODE=open                         # EDIT or keep: "open" = picoclaw's safety guards off, the VM is the cage (advised); "strict" = its defaults

case "$MODE" in
  open)   guard=false; iter=40 ;;
  strict) guard=true;  iter=50 ;;
  *)      guard= ;;
esac
RULES='## House rules for the shell

- This machine is NetBSD, not Linux: no /proc/meminfo, free, lscpu or apt. Use uname -a, sysctl hw.model hw.ncpu hw.physmem64, vmstat, df -h, ps aux.
- You are not root: su and sudo do not work, and pkgin needs root. If you need a system package, tell me.
- exec always needs action "run" together with the command.
- If a command or tool fails twice the same way, do not try a third variation: stop and tell me what you wanted to do. After 3 failed tool calls in a row, stop and ask me.'

if case "$PC_IP$STRATA_KEY" in *x.x*|*PUT-*) true ;; *) false ;; esac; then
  echo "STOP: edit PC_IP and STRATA_KEY first"
elif [ -z "$guard" ]; then
  echo "STOP: MODE must be open or strict"
else
  cd ~/.picoclaw &&
  cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
  jq --arg url "http://$PC_IP:11434/v1" --arg key "$STRATA_KEY" --argjson g "$guard" --argjson n "$iter" '
      .agents.defaults.model_name = "strata"
    | .agents.defaults.tool_feedback.enabled = true
    | .agents.defaults.restrict_to_workspace = $g
    | .tools.exec.enable_deny_patterns = $g
    | .agents.defaults.max_tool_iterations = $n
    | .model_list = [{model_name: "strata", model: "vllm/qwen3.8-flash-next", api_base: $url, api_keys: [$key]}]
    | .tools.web.duckduckgo.enabled = true
    | .tools.install_skill.enabled = false
    | .tools.cron.allow_command = false
  ' config.json > config.json.new &&
  mv config.json.new config.json &&
  chmod 600 config.json &&
  f=workspace/USER.md &&
  mkdir -p workspace && touch "$f" &&
  { awk '/^## House rules for the shell/{skip=1; next} /^## /{skip=0} !skip' "$f"
    printf '\n%s\n' "$RULES"; } | cat -s > "$f.new" &&
  mv "$f.new" "$f" &&
  echo "OK: agent configured (MODE=$MODE), house rules written"
  cd ~
  ids=$(curl -s --max-time 10 "http://$PC_IP:11434/v1/models" -H "Authorization: Bearer $STRATA_KEY" | jq -r '.data[].id' 2>/dev/null)
  if [ -n "$ids" ]; then echo "Strata answers from the VM: $ids"
  else echo "NO ANSWER from Strata at $PC_IP:11434: wrong address or key? Strata not started? see the troubleshooting table at the end"; fi
fi
```

<details markdown="1">
<summary>What did that block change? (and why are the safety guards off?)</summary>

- `vllm/` = "local OpenAI-compatible server". The model's name after it is not very important, Strata answers to anything.
- `tool_feedback`: the agent tells you in the chat before each tool it uses. That's how you *see what it does* before giving it more power.
- Web search: DuckDuckGo needs no API key (no Brave key needed, unlike openclaw), but it can be **off by default**, hence the explicit `true`. Brave works too if you have a key: `.tools.web.brave = {"enabled": true, "api_key": "..."}`.
- The leash for week one: you pick the skills, not the agent, so `install_skill` (it installing skills by itself) and `cron.allow_command` (it scheduling shell commands for itself) are off. Chapter 4 says how to turn them back on when you trust it more.
- **The safety guards (`MODE`).** picoclaw puts two guards on its shell and file tools: one keeps them inside the workspace (no `/tmp`, `/proc` or `/mnt`, no `..`, no other `cwd`), the other refuses a list of shell constructs (`$(...)`, `${...}`, backticks, `kill`, `rm -r`, `chmod 755`...) and only says "dangerous pattern detected". A small model can't see these rules, so it retries variations until it runs out of tool calls, and even a simple task (a holiday date, a system check, "test your skills") fails with "blocked by safety guard", "access denied" or "path escapes workspace". They are a text check, not a sandbox (they don't understand `~/` or `cd /`), so they never were the cage: **the VM is the cage**. So `open` switches them off and raises the cap to 40 tool calls per request (a real task needs 10 to 25). It means the agent can read and write anywhere in the VM, `/mnt` (your shared folder) and its own `~/.picoclaw/config.json` (your keys) included, and run any command a normal user can. It is still not root. So keep in the shared folder only what the VM may see, and take a save before big experiments (the "Save and restore" fold, after "Talk to it"). Want picoclaw's own guards back? Paste the block again with `MODE=strict`.
- The house rules go into `USER.md` in the workspace, which is added to every prompt: the model otherwise guesses it is on Linux, as root. Pasting the block again replaces that section, it never piles up.
- If you gave Strata less context than picoclaw assumes (`agents.defaults.context_window`, 131072 in the example config), lower it to match, e.g. `jq '.agents.defaults.context_window = 65536' config.json > config.json.new && mv config.json.new config.json`.
- Something went wrong? `ls ~/.picoclaw/config.json.*.bak`, and `cp` the last one back over `config.json`.

</details>

Let's skip the rest for now, you can put other stuff here (Telegram, MCP, skills, a browser...), see below, but let's start small.

### Talk to it

🦞 **in the VM**

```shell
picoclaw agent                                     # chat in the terminal (type exit, or Ctrl-C, to leave)
picoclaw agent -m "what's the weather in Paris?"   # one shot
picoclaw agent --debug -m "list the files in your workspace"   # same, with the gory details
```

Or the web UI: `picoclaw-launcher -public` in the VM, then http://127.0.0.1:18800 in your PC's browser.

Heads up: picoclaw runs its tools without asking you, and with `MODE=open` nothing but the VM stands in its way. The cage is the VM. Watch what it does before giving it more: `picoclaw agent --debug` (or `picoclaw gateway --debug`) prints every command it runs on the `Tool call: exec({...})` lines. A `missing required property "action"` warning is harmless: the model forgot `action: "run"` and retries.

<details markdown="1">
<summary>Save and restore the agent (so a bug or an update costs ten seconds)</summary>

Everything that makes your agent *yours* (its config and keys, its memory, its skills, `USER.md`) lives in one folder, `~/.picoclaw`. The VM itself is disposable: a rebuild wipes it. This script, which **you** run in the VM (not the agent), packs that folder into the shared folder and puts it back, so that "kill the VM and start over" becomes: rebuild, restore, done. Saves land in `picoclaw-saves/` in the shared folder, so they are on your PC too.

🦞 **in the VM**: create the script once (it goes in `/mnt`, so it survives rebuilds)

```shell
cat > /mnt/picoclaw-keep.sh <<'EOF'
#!/bin/sh
# picoclaw-keep.sh: save and restore the agent (config, memory, skills) in the shared folder.
#   sh /mnt/picoclaw-keep.sh save [name]      save ~/.picoclaw (name defaults to the date and time)
#   sh /mnt/picoclaw-keep.sh list             list the saves, newest first
#   sh /mnt/picoclaw-keep.sh restore [name]   put a save back (newest if no name)
# Run it as yourself in the VM, with picoclaw stopped (Ctrl-C) before a restore.
# The saves contain your keys (config.json): keep the shared folder private.

SRC="${PICOCLAW_DIR:-$HOME/.picoclaw}"
DEST="${KEEP_DIR:-/mnt/picoclaw-saves}"

die() { echo "ERROR: $*" >&2; exit 1; }

latest() { ls -t "$DEST"/*.tgz 2>/dev/null | head -1; }

case "$1" in
  save)
    [ -d "$SRC" ] || die "$SRC not found (did you run picoclaw onboard?)"
    name="${2:-$(date +%Y%m%d-%H%M%S)}"
    case "$name" in */*) die "no slash in the name" ;; esac
    mkdir -p "$DEST" || die "cannot create $DEST (is the shared folder mounted on /mnt?)"
    out="$DEST/$name.tgz"
    [ -e "$out" ] && die "$out already exists, pick another name"
    tar -C "$(dirname "$SRC")" -czf "$out" "$(basename "$SRC")" || die "tar failed"
    chmod 600 "$out" 2>/dev/null
    echo "saved: $out ($(du -h "$out" | cut -f1))"
    ;;
  list)
    ls -t "$DEST"/*.tgz 2>/dev/null || echo "no saves in $DEST"
    ;;
  restore)
    if [ -n "$2" ]; then f="$DEST/$2.tgz"; else f="$(latest)"; fi
    [ -n "$f" ] && [ -f "$f" ] || die "no such save (try: sh $0 list)"
    tar -tzf "$f" >/dev/null 2>&1 || die "$f is not a valid archive"
    for p in picoclaw picoclaw-launcher; do
      pgrep -x "$p" >/dev/null 2>&1 && die "$p is running: stop it (Ctrl-C) and restore again"
    done
    old=""
    if [ -d "$SRC" ]; then
      old="$SRC.before-restore-$(date +%Y%m%d-%H%M%S)"
      [ -e "$old" ] && old="$old-$$"
      mv "$SRC" "$old" || die "cannot move $SRC away"
      echo "your current $SRC was kept as $old"
    fi
    tar -C "$(dirname "$SRC")" -xzf "$f" || die "tar failed${old:+, your previous folder is $old}"
    chmod 600 "$SRC/config.json" 2>/dev/null
    echo "restored: $f"
    echo "now start picoclaw again"
    ;;
  *)
    echo "usage: sh $0 save [name] | list | restore [name]" >&2
    exit 1
    ;;
esac
EOF
echo "OK: now use  sh /mnt/picoclaw-keep.sh save"
```

(If `/mnt` answers "Permission denied", put the same text in a file named `picoclaw-keep.sh` in the `share/` folder on your PC instead.) Then, whenever you want:

🦞 **in the VM**

```shell
sh /mnt/picoclaw-keep.sh save                  # before an update or an experiment
sh /mnt/picoclaw-keep.sh save before-telegram  # or with a name of your own
sh /mnt/picoclaw-keep.sh list                  # what do I have ?
sh /mnt/picoclaw-keep.sh restore               # put the newest one back (stop picoclaw first)
sh /mnt/picoclaw-keep.sh restore before-telegram
```

A restore keeps what it replaces: your current folder is moved aside to `~/.picoclaw.before-restore-<date>` first. After a rebuild: boot the new VM, `sh /mnt/picoclaw-keep.sh restore`, start picoclaw. What isn't saved: packages you added with `pkgin` (they go in the `Dockerfile.clawd` line instead, see chapter 2), and files you left outside `~/.picoclaw`.

</details>

---

## 4. Skills & tools

A **tool** is something the agent can *do* (run a command, read a file, search the web). A **skill** is a short *manual* that tells it how and when to use tools well. Tools can also come from **MCP servers**.

### How a skill works

A skill is a folder with a `SKILL.md` and, if needed, helpers next to it:

```
my-skill/
├── SKILL.md        required: a name, a description, then the instructions
├── scripts/        code the agent can run
├── references/     long docs, read only when needed
├── assets/         templates, files to copy
```

Only the **name and description** of each skill are put in the prompt. When your request matches a description, the model reads the whole `SKILL.md` (with its file tools) and follows it. That's why descriptions should say *when* to use the skill, and why a big skill costs context only when it is used.

picoclaw looks in `~/.picoclaw/workspace/skills/` (yours), then `~/.picoclaw/skills/`, then its built-ins. Manage them with:

🦞 **in the VM**

```shell
picoclaw skills list                        # what the agent knows now
picoclaw skills show weather                # read one
picoclaw skills search "web scraping"       # search ClawHub (https://clawhub.ai)
picoclaw skills list-builtin                # the ones that come with picoclaw
picoclaw skills install-builtin             # (re)install them in your workspace

# These need a real name in place of the CAPITALS, so they are commented out:
# picoclaw skills install --registry clawhub SLUG        # install one found with "search"
# picoclaw skills install OWNER/REPO/PATH/TO/SKILL       # or straight from GitHub (the REA example is below)
# picoclaw skills remove SKILL_NAME
```

Built-ins: `weather` (no API key), `summarize` (URLs and files), `github` (the `gh` CLI), `tmux`, `agent-browser` (browser automation: it needs a program that doesn't exist for NetBSD, see "A browser for the agent" below), `hardware` (Sipeed boards, useless here), `picoclaw-agent` (it knows picoclaw's own config, ask it for help!) and `skill-creator`, a skill to make skills: *"use the skill-creator skill to make me a skill that ..."*.

### Make your own, in 30 seconds

A tiny skill with a script, to see the mechanics:

🦞 **in the VM**

```shell
d=~/.picoclaw/workspace/skills/vm-health
mkdir -p "$d/scripts"

cat > "$d/SKILL.md" <<'EOF'
---
name: vm-health
description: Report how the smolClaw VM is doing (OS, uptime, disk space). Use when the user asks about the health, load, uptime or free disk of the VM.
---

# vm-health

Run the script that sits next to this file, from this folder, and report the result in three lines at most:

    sh scripts/health.sh

Only report. Do not try to fix or clean anything.
EOF

cat > "$d/scripts/health.sh" <<'EOF'
#!/bin/sh
uname -a
uptime
df -h
EOF

picoclaw skills list
picoclaw agent -m "how is the VM doing?"
```

You should see it read `vm-health/SKILL.md`, then run the script. If it doesn't, your description is too vague, or your model too small: that's most of the art.

Tips: short and imperative beats long and clever (a local model has less room than a cloud one), one job per skill, put the fragile steps in `scripts/` and the long reading in `references/`.

### A real one: Reverse Engineer Anything (REA)

[REA](https://github.com/morluto/rea) ([rea.tools](https://rea.tools)) is the recent famous one: it teaches an agent to reverse engineer shipped software (native binaries, Electron/JavaScript apps, firmware, packages...), explain features, and compare versions. It's a good example because it has **both halves**:

| Half | What it is | Where it lives |
| --- | --- | --- |
| The skill | `SKILL.md` (~22 KB of method) + a `references/` folder: *when and how* to investigate | [`.agents/skills/reverse-engineer-anything`](https://github.com/morluto/rea/tree/main/.agents/skills/reverse-engineer-anything) |
| The tools | an MCP server, the npm package [`rea-agents`](https://www.npmjs.com/package/rea-agents), run with `npx -y rea-agents@<version> mcp` | needs Node.js |

Skill without tools is a manual with no hands; tools without skill are hands with no brain. Even REA's own `SKILL.md` says that installing the skill does not register the MCP server.

**Be careful before you install anything like this, it is text that tells your agent what to run:**

- Read the `SKILL.md` first: [on GitHub](https://github.com/morluto/rea/blob/main/.agents/skills/reverse-engineer-anything/SKILL.md).
- Use the official sources only: [github.com/morluto/rea](https://github.com/morluto/rea), [rea.tools](https://rea.tools), [npm `rea-agents`](https://www.npmjs.com/package/rea-agents), [skills.sh](https://skills.sh/morluto/rea/reverse-engineer-anything). REA's own README warns that similarly named repos exist and are not official.
- It analyzes *untrusted* files, and strings inside a binary can talk to your model. Another reason for the VM, with a dedicated `/mnt` for the samples. Read REA's `DISCLAIMER.md` for what you're allowed to analyze.

**Step 1, the skill** (this works in the VM):

🦞 **in the VM**

```shell
picoclaw skills install morluto/rea/.agents/skills/reverse-engineer-anything
picoclaw skills list
ls ~/.picoclaw/workspace/skills/reverse-engineer-anything/references | head
```

It downloads `SKILL.md` and the `references/`, `scripts/`, `assets/`... subfolders from GitHub. Check the `references/` folder is there; without it you only got the front page of the manual.

Now your agent knows when to reach for it. Ask for something it can't do yet, and watch it explain what is missing: *"Use the reverse-engineer-anything skill. How would you find out what the app in /mnt/samples does?"*. It costs about 6k tokens of context when used, so be sure Strata's context is big enough.

<details markdown="1">
<summary>"Rate limit" while installing a skill from GitHub?</summary>

GitHub's anonymous API quota is used up: wait an hour, or give picoclaw a token with *no permissions* in `tools.skills.registries.github.auth_token` (not one of your real ones).

</details>

**Step 2, the tools (MCP).** In short: `picoclaw mcp add --deferred rea -- npx -y rea-agents@6.5.0 mcp`. But **this half won't run in smolClaw as is**: REA needs Node.js 22.19+ and Linux, macOS or Windows, and NetBSD isn't on its list. So in the VM, step 1 teaches you the mechanics. To really use REA, run it on your Ubuntu PC (appendix A at the end sets up Ghidra for it). The details:

<details markdown="1">
<summary>Adding an MCP server, REA's caveats, and an MCP that does work in the VM</summary>

This is how any MCP server is added; REA's version-pinned launch line is from its [installation docs](https://github.com/morluto/rea/blob/main/docs/installation.md). In the VM, `add` and `list` work, `test` will fail until there is a Node.js to run it:

🦞 **in the VM**

```shell
picoclaw mcp add --deferred rea -- npx -y rea-agents@6.5.0 mcp
picoclaw mcp list --status
picoclaw mcp test rea
```

- `--deferred` matters: REA exposes a huge catalog of tools, and putting all of them in the prompt would eat your context. Deferred tools stay hidden until the agent *searches* for them. Use it for any big MCP server.
- Pin the version (`6.5.0` was the latest when this was written, check with `npm view rea-agents version`). An MCP server is code that runs with the agent's powers; `@latest` means "whatever shows up tomorrow".
- `picoclaw mcp add` just writes `tools.mcp.servers` in `config.json`; picoclaw starts the server itself when needed. `picoclaw mcp remove rea` undoes it.

The caveat, in full: REA needs Node.js 22.19+ (or 24.11+) and runs on macOS, Windows (partly) and Linux distributions with apt, dnf or pacman (its docs mention a procps-compatible `ps` on Linux). NetBSD isn't on that list. Native binaries also need Hopper, Ghidra or IDA; JavaScript/Electron apps need nothing more than Node. The image has no Node; `pkgin search nodejs` may offer one, but then you're on your own. So today:

- In the VM, you can install the skill and watch the agent read a big manual.
- To really use REA, run it where it's supported: on your Ubuntu PC with a coding agent REA knows (its `npx rea-agents@latest setup` handles Claude Code, Codex, Cursor...). picoclaw isn't on its list. Appendix A shows how, with Ghidra.
- The same recipe works for lighter servers. One that needs no Node and no local install is a *remote* one, for example `picoclaw mcp add context7 --transport http https://mcp.context7.com/mcp` (library documentation lookup; it may ask for a key, and your queries go to that service). Details: picoclaw's [MCP CLI doc](https://github.com/sipeed/picoclaw/blob/main/docs/reference/mcp-cli.md).

Whatever is installed, `/list skills`, `/list mcp` and `/show mcp <server>` (in Telegram, below) tell you what the agent can use.

</details>

### A browser for the agent

`web_fetch` reads a plain page. A page built with JavaScript, a button to click, a form or a screenshot need a real browser. There is none in the VM and none can be installed there, so the browser runs on your PC and the agent drives it over the network.

<details markdown="1">
<summary>Give the agent a real browser (Chrome on your PC, driven from the VM)</summary>

**Why on the PC.** The built-in `agent-browser` skill needs two programs and neither exists for NetBSD: its own command (no NetBSD build; compiling it needs a Rust toolchain of 1.7 GB, on a root disk of 3.9 GB) and Chrome (`pkgin` has it, with about 110 dependencies and 125 MB, but installing needs root, which you don't have). The kernel has no Linux emulation either, so the Linux builds are out. So: Chrome on your Ubuntu PC, driven by [Playwright MCP](https://github.com/microsoft/playwright-mcp) (Microsoft's MCP server for browsers), and the VM only speaks HTTP to it. QEMU shows your PC to the VM as `10.0.2.2`, which is why the server can listen on `127.0.0.1` only: nothing on your network can reach it.

**Step 1, on your PC, once:** Node.js 18+, Google Chrome (skipped if you have it; it is Google's official `.deb`, which also adds Google's apt repository), and a small start script. Pasting it again is harmless:

🖥️ **on your PC**

```shell
node_ok() { node -e 'process.exit(+process.versions.node.split(".")[0] >= 18 ? 0 : 1)' 2>/dev/null; }
node_ok || sudo apt install -y nodejs npm
command -v google-chrome >/dev/null || {
  curl -fL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
  sudo apt install -y /tmp/chrome.deb; rm -f /tmp/chrome.deb; }

cat > ~/browser-mcp.sh <<'EOF'
#!/bin/sh
# browser-mcp.sh: a headless Chrome that the agent in the VM can drive (Playwright MCP).
# It listens on this PC only (127.0.0.1:8931); the VM reaches it as 10.0.2.2:8931. Ctrl-C stops it.
# Its files (screenshots, page snapshots) go to shots/ in the shared folder, which is /mnt/shots in the VM.
SHARE="${SHARE:-$HOME/smolBSD/share}"
mkdir -p "$SHARE/shots" && cd "$SHARE" || exit 1
exec npx -y @playwright/mcp@0.0.83 \
  --browser chrome --headless --isolated \
  --host 127.0.0.1 --port 8931 --allowed-hosts 10.0.2.2:8931 \
  --image-responses omit --output-dir shots
EOF

if node_ok && command -v google-chrome >/dev/null; then
  echo "OK: Node $(node --version), $(google-chrome --version). Next: sh ~/browser-mcp.sh"
else
  echo "STOP: Node.js 18+ and Google Chrome are both needed (see above; Node: https://nodejs.org)"
fi
```

**Step 2, on your PC:** start it, and leave that terminal open (chapter 6 starts it for you from then on). The first start downloads Playwright MCP, then it says `Listening on ...:8931`:

🖥️ **on your PC**

```shell
sh ~/browser-mcp.sh
```

**Step 3, in the VM, once:** plug it in, give the agent a short manual for it, and remove the `agent-browser` skill, which would only send it chasing a program that isn't there. The server is registered `--no-deferred`: its 25 tools are always in the prompt (about 5k tokens), so the small model can't forget they exist.

🦞 **in the VM**

```shell
picoclaw mcp add -f --no-deferred --transport http browser http://10.0.2.2:8931/mcp
picoclaw skills remove agent-browser 2>/dev/null

d=~/.picoclaw/workspace/skills/browser
mkdir -p "$d" && cat > "$d/SKILL.md" <<'EOF'
---
name: browser
description: Use a real web browser: open a page, read it, click, fill a form, take a screenshot. Use it when web_fetch is not enough (page built with JavaScript, a button to click, a form, a screenshot). This is NOT the agent-browser command, which does not exist on this machine.
---

# browser

A real Chrome runs on the user's PC. You drive it with the browser_* tools (browser_navigate, browser_snapshot, browser_click, browser_type, browser_fill_form, browser_take_screenshot, browser_tabs...).

1. browser_navigate with the URL.
2. browser_snapshot: the page as text, with a ref like e12 for each link, button and field. Read it, do not guess refs.
3. browser_click or browser_type: give the ref from the LAST snapshot (like e12) as the target. Snapshot again after each action: the refs change.
4. Answer from the snapshot text. If the user asks for a picture, use browser_take_screenshot. You cannot see it: the file is in /mnt/shots, tell the user its name.

Rules:
- For a plain page of text, web_fetch is cheaper. Use the browser only when it is not enough.
- Never log in, never type a password, a key or personal data, never buy or submit anything without asking the user first.
- Stay on the sites the user asked about. Never open addresses of the local network (localhost, 127.0.0.1, 10.x.x.x, 192.168.x.x).
- If something fails twice, stop and tell the user what you wanted to do.
EOF

picoclaw mcp test browser
picoclaw skills list
```

`mcp test` should list the browser tools (`browser_navigate`, `browser_snapshot`...). Then try it, and look in `~/smolBSD/share/shots` on your PC afterwards:

🦞 **in the VM**

```shell
picoclaw agent -m "Use the browser skill: open https://example.com, tell me the title of the page, then take a screenshot."
```

**What to know before you let it loose:**

- The browser is **headless** (no window) and **isolated**: a throwaway profile, no cookies, no logins, forgotten when it closes. Don't log in to anything in it.
- It has **no password**. Whatever reaches port 8931 of your PC can drive the browser: the VM (that is the point), but also any program on your PC. It only answers to the name `10.0.2.2:8931`, so a web page you visit can't talk to it.
- The browser lives on **your PC's network**: it can open your router's admin page or `http://127.0.0.1:11434` (Strata), which the VM itself could not. The skill tells the agent not to; that is a request, not a wall.
- Opening `file://` is blocked, and file uploads can only read the shared folder (that is where the script starts it from).
- The model never gets the pictures (`--image-responses omit`), only the file name; it works from the text snapshot of the page. Snapshots and console logs pile up in `shots/` too: empty it now and then.
- After an hour idle the browser closes itself; the next call opens it again.

**What did not work, so you don't redo it:** the `agent-browser` command built in the VM (the disk fills up before the build ends); the Linux builds of it (no `compat_linux` in the VM's kernel); Chrome from `pkgin` (needs root). The other route, `agent-browser` on the PC driven from the VM by SSH, or Chrome's debugging port (9222) through an SSH tunnel, does work, but it hands the VM a shell on your PC, which is exactly what the VM is there to avoid, and that debugging port has no password either. If you still go that way, use a dedicated user on the PC and a restricted key (`restrict` in its `authorized_keys`), never your own account.

</details>

### The built-in tools, and the leash

<details markdown="1">
<summary>Which tools exist, and how to tighten (or loosen) each</summary>

| Tool | What it does | How to tighten it (in `config.json`) |
| --- | --- | --- |
| `exec` | runs shell commands | `tools.exec.enabled`; deny patterns are on by default (`enable_deny_patterns`; the "open" setting in chapter 3 turns them off), add yours with `custom_deny_patterns` (regexes) |
| `read_file` `write_file` `edit_file` `append_file` `list_dir` | files | `agents.defaults.restrict_to_workspace` is `true` by default: only `~/.picoclaw/workspace` (and what you list in `tools.allow_read_paths` / `allow_write_paths`); the "open" setting in chapter 3 turns it off |
| `web_search` `web_fetch` | search the web, read a page | `tools.web.*` (each engine has `enabled`) |
| `spawn` `subagent` | the agent starts helpers | `tools.spawn.enabled`, `tools.subagent.enabled` |
| `cron` | the agent schedules jobs for itself | `tools.cron.enabled`, `tools.cron.allow_command` |
| `install_skill` `find_skills` | the agent installs skills **by itself** | `tools.install_skill.enabled` |
| MCP tools | whatever your servers expose | `tools.mcp.servers.<name>.enabled` |

Also on by default: tool output is scrubbed of anything that looks like your keys and tokens before the model sees it (`tools.filter_sensitive_data`). Full reference: [tools configuration](https://github.com/sipeed/picoclaw/blob/main/docs/reference/tools_configuration.md).

Chapter 3's block already followed my advice for week one: you pick the skills, not the agent, so `install_skill` and `cron.allow_command` are off. Turn them back on when you trust it more (pasting the chapter 3 block again turns them off again):

🦞 **in the VM**

```shell
cd ~/.picoclaw &&
cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
jq '.tools.install_skill.enabled = true | .tools.cron.allow_command = true' config.json > config.json.new &&
mv config.json.new config.json &&
chmod 600 config.json &&
echo "OK" ; cd ~
```

With `tool_feedback` on, you can see every tool call in the chat before you do.

</details>

---

## 5. The gateway (Telegram & co)

The gateway is picoclaw's door to chat apps. For Telegram it needs **no open port**: the VM calls Telegram (long polling), not the other way round. So nothing to forward or firewall, only an internet-connected VM.

### Make a bot

1. In Telegram, talk to [@BotFather](https://t.me/BotFather): `/newbot`, a name, a username ending in `bot`. It gives you a **token** like `123456789:ABCdef...`. That token is the bot's password.
2. Talk to [@userinfobot](https://t.me/userinfobot): it answers with your **numeric user ID** (like `123456789`).

### Tell picoclaw

`allow_from` is the list of Telegram users the bot obeys. **ALWAYS set it to your own user ID.** Left empty, anybody who finds your bot can drive your pet (and its shell). Edit the first two lines, paste:

🦞 **in the VM**

```shell
TG_TOKEN="PUT-BOT-TOKEN-HERE"        # EDIT: from @BotFather
TG_USER="PUT-YOUR-NUMERIC-ID-HERE"   # EDIT: from @userinfobot

case "$TG_TOKEN$TG_USER" in
  *PUT-*) echo "STOP: edit TG_TOKEN and TG_USER first" ;;
  *)
    cd ~/.picoclaw &&
    cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
    jq --arg tok "$TG_TOKEN" --arg uid "$TG_USER" '
      .channel_list.telegram = ((.channel_list.telegram // {})
        | .enabled = true
        | .type = "telegram"
        | .allow_from = [$uid]
        | if has("settings") then .settings.token = $tok else .token = $tok end)
    ' config.json > config.json.new &&
    mv config.json.new config.json &&
    chmod 600 config.json &&
    echo "OK: telegram enabled for user $TG_USER"
    cd ~ ;;
esac
```

(The token ends up in the shell history and in `config.json`, readable by the agent's own shell. Fine for a throwaway bot: if it leaks, `/revoke` it with BotFather. picoclaw can also read secrets from `~/.picoclaw/.security.yml`, see its [security configuration](https://github.com/sipeed/picoclaw/blob/main/docs/security/security_configuration.md).)

### Start it

In a second tmux window of the VM (`Ctrl-b c`; `Ctrl-b n` goes back and forth):

🦞 **in the VM**

```shell
picoclaw gateway --debug
```

(drop `--debug` once it works). Now message your bot: `/start`, then "what's the weather in Paris?". With `tool_feedback` on you'll see the tools it runs in the chat. Closing the window or stopping the VM stops the bot.

In the chat, besides normal talk:

- `/list skills`: what it knows
- `/list mcp` and `/show mcp <server>`: its MCP servers and their tools
- `/use <skill> <message>`: force a skill for one message, e.g. `/use weather Paris tomorrow?`
- `/use <skill>`, then your next message: same, in two steps. `/use clear` forgets it.

<details markdown="1">
<summary>The gateway's own port, and other chat apps</summary>

You may remember `nothing works, YEAH!`: `ss -tlnp | grep -E '18789|18800|2289'` on your PC says QEMU is listening, but that proves nothing, QEMU holds those ports as long as the VM runs, whatever happens inside.

The real reason: the gateway's own HTTP port defaults to `localhost:18790`. Only reachable from inside the VM, and 18790 isn't even forwarded. Telegram doesn't care. You only need to change it if you want to reach the gateway from your PC (health checks, or chat apps that use webhooks):

🦞 **in the VM**

```shell
cd ~/.picoclaw &&
jq '.gateway.host = "0.0.0.0" | .gateway.port = 18789' config.json > config.json.new &&
mv config.json.new config.json &&
chmod 600 config.json ; cd ~
```

then restart `picoclaw gateway`. 18789 is forwarded to your PC by the VM's conf, on all interfaces: firewall it if your LAN isn't friendly.

Other chat apps (Discord, Slack, Matrix...) are configured the same way, in `channel_list`: see picoclaw's [chat apps guide](https://github.com/sipeed/picoclaw/blob/main/docs/guides/chat-apps.md) and the [Telegram doc](https://github.com/sipeed/picoclaw/blob/main/docs/channels/telegram/README.md).

</details>

---

## 6. Daily life

Everything is installed. A normal day is: one command to start, talk to it, look at what it did, stop. Chapters 1 to 5 were the install; you will not paste those again.

### Start everything with one command

Three things must run on your PC: Strata (the brain), the browser server if you did the browser part of chapter 4, and the VM (the hands). This script starts the ones that are not running yet, each in its own window of a `tmux` session called `agent`, and drops you in the VM's window. Create it once:

🖥️ **on your PC**

```shell
cat > ~/agent-up.sh <<'EOF'
#!/bin/sh
# agent-up.sh: bring the whole local agent up with one command, in a tmux session called "agent".
#   sh ~/agent-up.sh          start what is not running yet, then go to the VM's window
#   sh ~/agent-up.sh stop     stop Strata and the browser (the VM: type exit in each of its panes)
# Windows: pc (a free shell), strata (the brain), vm (the agent), browser (if set up). Ctrl-a w lists them.
# This tmux answers to Ctrl-a, so it never fights with the VM's own tmux (Ctrl-b).

S=agent
SHARE="${SHARE:-$HOME/smolBSD/share}"
[ -r ~/.llm-dir ] && . ~/.llm-dir
[ -f "${LLM_DIR:-/nonexistent}/Strata/setup.sh" ] || { echo "ERROR: Strata not found (chapters 0 and 1 first)"; exit 1; }
[ -f ~/smolBSD/smoler.sh ] || { echo "ERROR: ~/smolBSD not found (chapter 2 first)"; exit 1; }
command -v tmux >/dev/null || { echo "ERROR: sudo apt install tmux"; exit 1; }

if [ "$1" = stop ]; then
  tmux kill-window -t "$S:strata" 2>/dev/null
  tmux kill-window -t "$S:browser" 2>/dev/null
  echo "Strata and the browser are stopped. The VM: go to its window (Ctrl-a w) and type exit in each pane."
  exit 0
fi

running() { ss -tln 2>/dev/null | grep -q ":$1 "; }                       # is something listening on this port?
there() { tmux list-windows -t "$S" -F '#W' 2>/dev/null | grep -qx "$1"; }   # is there a window with this name?

start() {   # start NAME PORT COMMAND
  if running "$2" || there "$1"; then echo "$1: already running"; return; fi
  tmux new-window -d -t "$S:" -n "$1" "$3; echo; echo '--- $1 has stopped. Enter closes this window ---'; read x"
  echo "$1: started"
}

tmux has-session -t "$S" 2>/dev/null || {
  tmux new-session -d -s "$S" -n pc
  tmux set-option -t "$S" prefix C-a
  tmux bind-key C-a send-prefix
}
start strata 11434 "cd '$LLM_DIR/Strata' && ./setup.sh --no-browser"
start vm 2289 "cd '$HOME/smolBSD' && ./smoler.sh run clawd-amd64:latest -c 2 -m 1024 -w '$SHARE'"
if [ -f ~/browser-mcp.sh ]; then start browser 8931 "sh '$HOME/browser-mcp.sh'"; fi

tmux select-window -t "$S:vm" 2>/dev/null
if [ -n "$TMUX" ]; then tmux switch-client -t "$S"; else exec tmux attach -t "$S"; fi
EOF
sh ~/agent-up.sh
```

From now on it is only `sh ~/agent-up.sh`. Strata needs a minute or two to load the model; its window (`Ctrl-a w` lists the windows) says when it is ready. Two Strata models installed (chapter 1, Huihui)? That window asks which one to start. Inside the VM, type `picoclaw agent` (or `picoclaw gateway` in a second VM window for Telegram), and the keys are the ones of the tmux table in chapter 2, with `Ctrl-a` for the PC and `Ctrl-b` for the VM. `Ctrl-a d` leaves and lets everything run; `tmux attach -t agent` comes back.

### What you do with it

| I want to... | Do |
| --- | --- |
| ask one thing | `picoclaw agent -m "..."` |
| have a conversation | `picoclaw agent` (`exit` leaves) |
| talk to it from my phone | `picoclaw gateway` in a second VM window, then Telegram (chapter 5) |
| see what it does | `picoclaw agent --debug`; or just read the tool calls `tool_feedback` prints in the chat |
| stop it in the middle of a task | `/stop` in the chat, or Ctrl-C |
| start over (it drifts, it loops, the context is full) | `/clear` in the chat; `/context` shows how full it is |
| ask a side question without disturbing the task | `/btw <question>` |
| give it a file, or get one back | the shared folder: `~/smolBSD/share` on your PC is `/mnt` in the VM |
| see what it did while I was away | `ls -lt /mnt ~/.picoclaw/workspace` in the VM, and `~/smolBSD/share/shots` for the browser |
| try something risky | `sh /mnt/picoclaw-keep.sh save` first (chapter 3); `restore` undoes it |
| give it a new skill | chapter 4: read the `SKILL.md` first, install it yourself |

A few habits that keep it safe: put in the shared folder only what the VM may see; read what a skill says before you install it; if you doubt the agent, change the two secrets it can reach, the Strata key and the Telegram bot token. A model that is stuck is nearly always a model that was asked for too much at once: split the task.

### When you are done, and when things change

When you game or render, free the GPU: `sh ~/agent-up.sh stop` (Strata and the browser stop; in the VM window, `exit` in each pane shuts the VM down cleanly). Next morning, `sh ~/agent-up.sh` again.

Now and then: Strata needs no update to keep working, so update it only when you want something new in it: `. ~/.llm-dir; cd "$LLM_DIR/Strata" && ./update.sh`, then restart it. That update compiles the engine again (a few minutes). If it ends with `could not compile the updated engine`, nothing is lost, the old engine still runs, but each start retries the compile: the fold after the install block in chapter 1 has the fix. picoclaw updates itself every time the VM boots; for smolBSD, `cd ~/smolBSD && git pull`, and remember that a rebuilt or freshly pulled VM image is a new, empty VM: `save` before, `restore` after. Your router gave your PC another address? Chapter 1's check block prints it, and chapter 3's block takes it.

---

## When it doesn't work

<details markdown="1">
<summary>Troubleshooting table</summary>

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Strata setup: "no NVIDIA GPU found"; `nvidia-smi`: "Driver/library version mismatch" | the loaded kernel module and the NVIDIA libraries are different versions (often after an `apt upgrade`) | reboot; if it persists, the "nvidia-smi fails" fold in chapter 1 |
| `ss` shows `127.0.0.1:11434` | Strata (or Ollama) listens on localhost only | host `0.0.0.0` in `strata-<model>.json` (or the Ollama override), restart |
| In the VM, `curl` to Strata hangs or is refused | wrong `PC_IP`, Strata on `127.0.0.1`, or your PC's address changed | redo the "Check that it answers" block of chapter 1 (it prints the address), test with `curl` on the PC using that address, redo the config block of chapter 3 |
| `401` / `403` / "unauthorized" | the key in `api_keys` isn't Strata's | `cat ~/.strata-key` on the PC, redo the config block |
| `./setup.sh` or `./update.sh` stops on `calling a __device__ function ... __half_as_ushort`, or says `could not compile the updated engine` | Strata 0.1.45 and newer, compiled with Ubuntu's CUDA 12.0: one debug line that this toolkit refuses | the fold right after the install block in chapter 1 (a one-line fix) |
| Huihui: setup stops on a SHA-256 or "wrong file" | the guard in `setup.py` is missing, or `HUIHUI_SKIP_SHA256=1` wasn't set on the setup line | paste step 2 of the Huihui part again; your files are safe in `$LLM_DIR/huihui-qfn` |
| Huihui: after a `./setup.sh --setup` where you picked "Unsloth", the model is the stock one (the config names files in `Strata-data/models/`) | the Huihui model has the stock model's name, so that setup overwrote its config | "Already overwritten?" in the Huihui part (step 2 again, or the script that points the config back); your Huihui files are untouched |
| Huihui answers like the stock model | a stock Unsloth pack was reused | move `$LLM_DIR/Strata-data/packs/unsloth-ud-iq4_xs` away (`mv` it to `...iq4_xs.stock`), paste step 2 again |
| "STOP: no usable /dev/kvm", or `Could not access KVM kernel module` | no virtualization, or no permission | the KVM fold in chapter 2 (BIOS, `modprobe`, `kvm` group) |
| `./smoler.sh run` can't find the image | the pull didn't finish | `./smoler.sh images`; if the list is empty, `pull` again (or `build`) |
| `Could not set up host forwarding rule` | port 2289, 18789 or 18800 already used (another VM still running?) | `ss -tlnp \| grep -E '18789\|18800\|2289'` |
| Agent says it has no model / wrong model | `agents.defaults.model_name` isn't a `model_list[].model_name` | both are `strata` in the block above; `jq '.agents.defaults, .model_list' ~/.picoclaw/config.json` |
| Agent keeps getting "blocked by safety guard", "access denied", "path escapes workspace" or "dangerous pattern" and loops | picoclaw's workspace guard and shell deny list refuse what a small model tries (`/tmp`, `/proc`, `$(...)`, `kill`...); it retries until the call cap | paste the chapter 3 config block again with `MODE=open` (guards off, the VM is the cage); the fold after it says why |
| I want my agent back after a rebuild, an update or a bug | its whole state is one folder, `~/.picoclaw`, and the VM is disposable | "Save and restore the agent", right after, in chapter 3 |
| Answers, but never uses a tool | model not tool-capable (Ollama), or `exec`/`web` switched off | `picoclaw agent --debug -m "list your tools"` |
| Web search finds nothing | DuckDuckGo disabled, or the VM has no internet | `jq .tools.web ~/.picoclaw/config.json`; `curl -sI https://duckduckgo.com` |
| `picoclaw mcp test browser` fails, or the agent says it can't browse | the browser server isn't running on the PC, or the VM can't reach it | on the PC: `sh ~/browser-mcp.sh` must be running, and `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: 10.0.2.2:8931' http://127.0.0.1:8931/mcp` must print `400` (that is the server answering); then in the VM `picoclaw mcp list --status` |
| The browser server starts, but every call fails with an error saying that "chrome" is not found or not installed | Google Chrome isn't installed (or isn't at `/opt/google/chrome`) | step 1 of the browser fold in chapter 4, then `google-chrome --version` |
| The agent tries `agent-browser` and fails | the built-in skill is still there, or the `browser` skill is missing | `picoclaw skills list`, then step 3 of the browser fold |
| Telegram bot is silent | wrong token; `allow_from` isn't your numeric ID; gateway not running | `picoclaw gateway --debug`, read it |
| Telegram `409 Conflict` | two gateways poll the same bot token (e.g. an old VM) | stop one |
| Config is broken | typo in a hand edit | `jq . ~/.picoclaw/config.json` finds it; restore a `config.json.*.bak` |
| Nothing works since the PC rebooted | your router gave the PC a new address | redo the "Check that it answers" block of chapter 1 and the config block of chapter 3, then reserve the address in the router. Stop-gap: QEMU always shows your PC to the VM as `10.0.2.2` |

</details>

## To Be Continued

- Start the gateway on its own when the VM boots.
- Keep `~/.picoclaw` outside the VM, so a rebuild doesn't wipe it (for now, the save script does it by hand).
- Start `agent-up.sh` by itself when you log in to your PC.
- Give it a local search engine (SearXNG) instead of DuckDuckGo, and a ComfyUI skill for the French girls.
- Look at what it did overnight (`~/.picoclaw/workspace`, `shots/`), and only then, hand it more tools.

---

## Appendix A: Ghidra, so REA can decompile native programs

<details markdown="1">
<summary>Set up Ghidra on your Ubuntu PC for REA (not in the VM)</summary>

REA's JavaScript/Electron analysis needs nothing but Node. For **native** programs (ELF, PE, Mach-O, firmware...) it drives a decompiler engine: Hopper or IDA (commercial) or [Ghidra](https://github.com/NationalSecurityAgency/ghidra) (free, open source, from the NSA, and the one REA documents best). REA never installs Ghidra, Java or Node for you: it connects to what you installed. This all happens **on your Ubuntu PC**: Ghidra ships its native decompiler for Linux, macOS and Windows only, so it doesn't belong in the smolClaw VM.

What REA accepts (its [installation docs](https://github.com/morluto/rea/blob/main/docs/installation.md#ghidra)): Ghidra **12.1.x** (tested with 12.1.4), a **full JDK 21 or newer** (with `javac`), Node.js 22.19+, and a procps `ps` (standard on Ubuntu).

**1. Java** (the JDK, not just the runtime):

🖥️ **on your PC**

```shell
sudo apt install -y openjdk-21-jdk unzip procps
java -version && javac -version
```

Both must answer with 21 or newer. If apt has no `openjdk-21-jdk` on your Ubuntu, take a JDK 21 from [adoptium.net](https://adoptium.net).

**2. Node.js 22.19 or newer:**

🖥️ **on your PC**

```shell
node --version
```

Lower, or not found? Ubuntu's apt Node is usually too old. Download the Linux tarball of a current LTS from [nodejs.org/en/download](https://nodejs.org/en/download), unpack it in `~/tools` and put its `bin` folder first in your `PATH` (no `curl | sh`).

**3. Ghidra.** Download the **PUBLIC** zip of release 12.1.4 from the [releases page](https://github.com/NationalSecurityAgency/ghidra/releases) (it is named like `ghidra_12.1.4_PUBLIC_<date>.zip`), into `~/Downloads`. Compare its SHA-256 with the one in the release notes, then unpack it:

🖥️ **on your PC**

```shell
mkdir -p ~/tools
sha256sum ~/Downloads/ghidra_12.1.4_PUBLIC_*.zip
unzip -q ~/Downloads/ghidra_12.1.4_PUBLIC_*.zip -d ~/tools
ls ~/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless
```

Nothing to build or install: Ghidra runs from this folder. REA only uses the headless mode (`analyzeHeadless`); the Ghidra window isn't needed.

**4. Tell REA where things are.** Two environment variables; this appends them to your `~/.bashrc` (a second paste only repeats the lines, harmlessly):

🖥️ **on your PC**

```shell
cat >> ~/.bashrc <<'EOF'

# REA: where Ghidra and its JDK are
export GHIDRA_INSTALL_DIR="$HOME/tools/ghidra_12.1.4_PUBLIC"
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
EOF
. ~/.bashrc
echo "$GHIDRA_INSTALL_DIR"; echo "$JAVA_HOME"
```

Both lines must print a real folder (`.../ghidra_12.1.4_PUBLIC` and something like `/usr/lib/jvm/java-21-openjdk-amd64`).

**5. Ask REA if it's happy.** `doctor` only reads, it changes nothing:

🖥️ **on your PC**

```shell
npx -y rea-agents@6.5.0 doctor --provider ghidra --json
echo "exit status: $?"
```

Exit status 0 means Ghidra is accepted. Otherwise the JSON says which check failed (JDK too old, no `javac`, missing decompiler for your CPU...) and how to fix it.

**6. Try it on something harmless.** `/usr/bin/true` is a tiny stripped program that is on every Ubuntu. The first Ghidra query imports and analyses the file, which takes a few minutes the first time:

🖥️ **on your PC**

```shell
npx -y rea-agents@6.5.0 analyze /usr/bin/true --provider ghidra --json | head -c 2000; echo
```

If you see JSON with functions and segments, it works. For big programs, give it more time and memory (the defaults are 330 s and 2 GB):

```shell
export REA_GHIDRA_STARTUP_TIMEOUT_MS=900000   # 15 minutes
export GHIDRA_HEADLESS_MAXMEM=4G
```

**7. Give it to an agent.** REA's own installer registers it with the coding agents it knows. It shows exactly what it will change, makes backups, and does nothing until you approve (Ctrl-C cancels, nothing changes):

🖥️ **on your PC**

```shell
npx -y rea-agents@6.5.0 setup
```

It records the Ghidra and JDK settings it detects in the agent's registration, which matters for an agent started from a menu or icon rather than a terminal: it doesn't see the variables of step 4. picoclaw isn't on its list. If you run picoclaw directly on a Linux machine (not in smolClaw), add REA by hand and pass the variables along:

```shell
picoclaw mcp add --deferred \
  --env GHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR" --env JAVA_HOME="$JAVA_HOME" \
  rea -- npx -y rea-agents@6.5.0 mcp
```

**Mind the difference.** Ghidra analyses a program, it doesn't run it. But REA has other tools that do run things (runtime observation, Frida instrumentation): for those, and for anything you don't trust, use a disposable machine or VM. To remove Ghidra: `rm -rf ~/tools/ghidra_12.1.4_PUBLIC` and delete the two lines from `~/.bashrc`.

</details>

---

## Links

- Inference: [Strata](https://github.com/Niko1221/Strata) ([models](https://github.com/Niko1221/Strata/blob/main/docs/MODELS.md), [Unsloth by hand](https://github.com/Niko1221/Strata/blob/main/docs/UNSLOTH_Q4.md)), [Huihui QFN](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF), [Ollama](https://ollama.com), [llmfit](https://github.com/AlexsJones/llmfit)
- The VM: [smolBSD](https://github.com/NetBSDfr/smolBSD), its [smolClaw page](https://github.com/NetBSDfr/smolBSD/tree/main/service/clawd) and [local-model notes](https://github.com/NetBSDfr/smolBSD/blob/main/service/clawd/LOCAL.md)
- The agent: [sipeed/picoclaw](https://github.com/sipeed/picoclaw), [NetBSD builds](https://github.com/afjcjsbx/picoclaw/releases); docs: [Telegram](https://github.com/sipeed/picoclaw/blob/main/docs/channels/telegram/README.md), [MCP CLI](https://github.com/sipeed/picoclaw/blob/main/docs/reference/mcp-cli.md), [tools](https://github.com/sipeed/picoclaw/blob/main/docs/reference/tools_configuration.md), [debugging / tool feedback](https://github.com/sipeed/picoclaw/blob/main/docs/operations/debug.md), [security configuration](https://github.com/sipeed/picoclaw/blob/main/docs/security/security_configuration.md)
- A browser: [Playwright MCP](https://github.com/microsoft/playwright-mcp), [Google Chrome](https://www.google.com/chrome/)
- Skills: [ClawHub](https://clawhub.ai), [REA](https://github.com/morluto/rea) ([site](https://rea.tools), [npm](https://www.npmjs.com/package/rea-agents), [skills.sh](https://skills.sh/morluto/rea/reverse-engineer-anything)), [Ghidra](https://github.com/NationalSecurityAgency/ghidra/releases), [JDK](https://adoptium.net), [Node.js](https://nodejs.org/en/download)
- Telegram: [@BotFather](https://t.me/BotFather), [@userinfobot](https://t.me/userinfobot)
