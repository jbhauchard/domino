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

The plan: **0.** pick the disk for the big files → **1.** Strata → **2.** the microVM → **3.** plug the agent into Strata → **4.** skills & tools → **5.** Telegram.

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

We put it on port 11434 (Ollama's usual port) instead of its default 8080. So if Ollama is installed, shut it up first, or the port is taken:

🖥️ **on your PC**

```shell
sudo systemctl disable --now ollama 2>/dev/null || true
```

Strata needs a working NVIDIA driver (version 580 or newer; the one from Ubuntu's own repository is fine). Check that yours answers:

🖥️ **on your PC**

```shell
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
./setup.sh --setup --host "$STRATA_HOST" --port "$STRATA_PORT" --api-key "$STRATA_KEY" --data-dir "$LLM_DIR/Strata-data"
```

It asks which model size, how much context and if it should read pictures: Enter gives the recommended answer. Then it downloads ~70 GB into `$LLM_DIR/Strata-data` and starts. Next time, just `. ~/.llm-dir; cd "$LLM_DIR/Strata" && ./setup.sh`. If it keeps the terminal, leave it there and open another one (or use `tmux`) for the rest.

Check that it answers (it lists the model):

🖥️ **on your PC**

```shell
. ~/.strata-key
curl -s http://127.0.0.1:11434/v1/models -H "Authorization: Bearer $STRATA_KEY"
```

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

#### Find your PC's address

The VM will need your PC's address on your home network, something like `192.168.1.53` (no `/24` or anything after):

🖥️ **on your PC**

```shell
ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'
```

Write it down too. Your router may hand out another one after a reboot: give your PC a fixed address (a "DHCP reservation" in the router), or you will redo the config below.

### Another model: Huihui QFN

<details markdown="1">
<summary>Huihui QFN (abliterated) instead of the stock model</summary>

[Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF) is Qwen3.8-Flash-Next with the refusals "abliterated" (v2: the ablation was adjusted, no expert touched), quantized the way Unsloth does. It comes in the same two sizes as the "Unsloth" entry of Strata's menu, so Strata can run it, no hand-made pack needed (the `docs/ORCA.md` manual workflow is for OrcaRouter's different file). Its [model card](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF) calls the abliteration method crude, a proof of concept, and recommends research and controlled environments (license `qwen-community-1.0`). With an agent that has a shell, your VM is the only guardrail left: keep it empty.

| Size | Download | Needs | Status in Strata |
| --- | --- | --- | --- |
| `UD-IQ4_XS` | 94 GB, 3 files | 48 GB+ of RAM (from ~80 GB, all the experts stay in RAM; below, part is read from the SSD) | regular choice |
| `UD-Q4_K_XL` | 111 GB, 4 files | 48 GB+ of RAM, an NVMe SSD, an NVIDIA GPU, no images | experimental |

Start with `UD-IQ4_XS`. The files are in the repository's `unsloth-UD-IQ4_XS/` and `unsloth-UD-Q4_K_XL/` folders. This install replaces nothing: it is one more model in Strata, with its own start script. Only one runs at a time on port 11434.

**The catch:** Strata pins the SHA-256 of *Unsloth's own* files, and deletes any file with their names that doesn't match. Huihui's files have the same names and other contents, so the check must be skipped for this one install (the model card says so too, and suggests editing `setup.py`). Below is the small, reversible version: a one-line guard that only does something when you set `STRATA_SKIP_SHA256=1`, removed again right after. Strata still checks that every file is complete.

**Step 0, pre-flight** (RAM, disk, and no stock Unsloth pack in the way, it would be reused instead of rebuilt):

🖥️ **on your PC**

```shell
. ~/.llm-dir
echo "RAM, GB (48+ needed):  $(free -g | awk '/^Mem:/{print $2}')"
echo "Free disk in $LLM_DIR, GB (about 105 for IQ4_XS, 125 for Q4_K_XL):  $(df -BG --output=avail "${LLM_DIR:?do chapter 0 first}" | tail -1 | tr -dc 0-9)"
if ls "$LLM_DIR/Strata-data/packs" 2>/dev/null | grep -qi unsloth; then
  echo "STOP: a stock Unsloth pack exists. Move it away first:"
  echo "  mv $LLM_DIR/Strata-data/packs/unsloth-ud-iq4_xs $LLM_DIR/Strata-data/packs/unsloth-ud-iq4_xs.stock"
else
  echo "No stock Unsloth pack in the way: good."
fi
```

Also bring Strata up to date first (`cd "$LLM_DIR/Strata" && ./update.sh`: it pulls the newest Strata and refreshes the engine, your model files are not touched). IQ4_XS needs Strata 0.1.39 or newer.

**Step 1, download** (resumable: if it stops, run it again; it takes a while). It uses Hugging Face's `hf` tool in its own little environment:

🖥️ **on your PC**

```shell
. ~/.llm-dir
QUANT=UD-IQ4_XS      # same as above
sudo apt install -y python3-venv
python3 -m venv ~/hf-venv && ~/hf-venv/bin/pip install -q -U huggingface_hub &&
~/hf-venv/bin/hf download huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-v2-GGUF \
  --include "unsloth-$QUANT/*" --local-dir "${LLM_DIR:?do chapter 0 first}/huihui-qfn" &&
ls -l "$LLM_DIR/huihui-qfn/unsloth-$QUANT"
```

You should see 3 `.gguf` files for IQ4_XS (about 11 MB, 49.8 GB and 43.8 GB) or 4 for Q4_K_XL (11 MB, 49.9, 49.4 and 12.1 GB). If you want to be thorough, `sha256sum "$LLM_DIR"/huihui-qfn/unsloth-$QUANT/*.gguf` (a few minutes) and compare with the SHA256 Hugging Face shows on each file's page.

**Step 2, one-time guard in `setup.py`** (keeps a copy of the original; safe to paste twice):

🖥️ **on your PC**

```shell
. ~/.llm-dir
cd "${LLM_DIR:?do chapter 0 first}/Strata" && { [ -f setup.py.orig ] || cp setup.py setup.py.orig; } &&
python3 - <<'EOF'
import pathlib
p = pathlib.Path("setup.py")
t = p.read_text(encoding="utf-8")
sig = "def verify_sha256(s: Path, size: int, sha: str) -> None:\n"
guard = ('    if os.environ.get("STRATA_SKIP_SHA256") == "1":\n'
         '        return   # one-off: Huihui files are not Unsloth\'s\n')
if "STRATA_SKIP_SHA256" in t:
    print("already patched")
elif sig not in t:
    print("STOP: setup.py has changed, do not patch blindly (ask for help)")
else:
    p.write_text(t.replace(sig, sig + guard, 1), encoding="utf-8")
    print("patched")
EOF
```

**Step 3, let Strata's setup do the rest** (engine, pack, draft layer, config, start script), using your files in place, then put `setup.py` back:

🖥️ **on your PC**

```shell
. ~/.llm-dir
QUANT=UD-IQ4_XS      # same as above
. ~/.strata-key      # your STRATA_KEY
cd "${LLM_DIR:?do chapter 0 first}/Strata" &&
STRATA_SKIP_SHA256=1 ./setup.sh --setup --family unsloth --model "$QUANT" \
  --gguf-dir "$LLM_DIR/huihui-qfn/unsloth-$QUANT" --data-dir "$LLM_DIR/Strata-data" \
  --host 0.0.0.0 --port 11434 --api-key "$STRATA_KEY" --no-start
mv -f setup.py.orig setup.py && echo "setup.py restored"
```

Enter gives the recommended answers (context, images). Press Ctrl-C by mistake? Run the `mv -f` line anyway. It writes `strata-unsloth-ud-iq4_xs.json` and `run-unsloth-ud-iq4_xs.sh` next to `setup.py` (`ud-q4_k_xl` for the other size).

**Step 4, protect the files, then start it** (stop the other Strata model first). Without write access to the folder, a future Strata update that re-checks the hashes can't delete your 94 GB, it just complains:

🖥️ **on your PC**

```shell
. ~/.llm-dir
QUANT=UD-IQ4_XS      # same as above
chmod a-w "${LLM_DIR:?do chapter 0 first}/huihui-qfn/unsloth-$QUANT"
cd "$LLM_DIR/Strata" && "./run-unsloth-$(echo "$QUANT" | tr 'A-Z' 'a-z').sh"
```

The VM sees no change: same address, same key. Check with the `curl` above (the model's name is now `qwen3.8-flash-next-unsloth-ud-iq4_xs`, picoclaw doesn't care). To use the stock model again, stop this one and start another from `./setup.sh`.

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

It is a VM so you need to have your computer agree to having a VM running on it:

🖥️ **on your PC**

```shell
grep -Ec '(vmx|svm)' /proc/cpuinfo   # 0 = nope
ls /dev/kvm                          # must exist
```

<details markdown="1">
<summary>0, or no /dev/kvm, or "permission denied"?</summary>

You might have to reboot into BIOS and enable "Intel VT-x" or "AMD-V" (sometimes called "SVM Mode"). It's usually under CPU settings or Advanced. If the CPU is fine but `/dev/kvm` is missing, `sudo modprobe kvm_intel` (or `kvm_amd`). If `/dev/kvm` is there but you get "permission denied": `sudo usermod -aG kvm $USER`, then log out and back in.

</details>

Then

🖥️ **on your PC**

```shell
sudo apt install -y curl git bmake qemu-system-x86 uuid-runtime binutils libarchive-tools gdisk socat jq lsof picocom
cd ~ && git clone https://github.com/NetBSDfr/smolBSD && cd smolBSD
./smoler.sh pull clawd-amd64:latest
# or build it yourself instead of pulling, it takes a few minutes:
# ./smoler.sh build -y smolerfiles/Dockerfile.clawd
```

(The first `pull` fetches the little `oras` tool into `smolBSD/bin/` by itself.)

This part is just giving tools to the chatbot, not running the chatbot itself (Strata does that, on your GPU). It doesn't need a lot of resources (here, 2 CPU cores, 1024 MB of RAM), but it does need to be isolated from your life ! So we share one dedicated folder, and nothing else:

🖥️ **on your PC**

```shell
cd ~/smolBSD
mkdir -p share
./smoler.sh run clawd-amd64:latest -c 2 -m 1024 -w "$HOME/smolBSD/share"
```

**This terminal now IS the VM.** Open another one for anything marked "on your PC". You land in a `tmux` as user `clawd` (`Ctrl-b |` and `Ctrl-b -` to split, `Ctrl-b c` for a new window, `Ctrl-b n` to switch). `exit` in every pane shuts the VM down.

Inside the VM the shared folder is mounted at:

```
/mnt
```

The agent can read and write everything in there. A dedicated folder, never your home!

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

Strata listens on http://0.0.0.0:11434 _somewhere_ but not in the smolBSD VM. Get your PC's address from the "Find your PC's address" part above. Then, in the VM, **edit the first two lines** and paste (it keeps a dated backup of your config, and changes only these bits):

🦞 **in the VM**

```shell
PC_IP=192.168.x.x                 # EDIT: your PC's address, like 192.168.1.53
STRATA_KEY=PUT-YOUR-KEY-HERE      # EDIT: the key (cat ~/.strata-key on your PC). With Ollama: -

case "$PC_IP$STRATA_KEY" in
  *x.x*|*PUT-*) echo "STOP: edit PC_IP and STRATA_KEY first" ;;
  *)
  cd ~/.picoclaw &&
  cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
  jq --arg url "http://$PC_IP:11434/v1" --arg key "$STRATA_KEY" '
      .agents.defaults.model_name = "strata"
    | .agents.defaults.tool_feedback.enabled = true
    | .model_list = [{model_name: "strata", model: "vllm/qwen3.8-flash-next", api_base: $url, api_keys: [$key]}]
    | .tools.web.duckduckgo.enabled = true
  ' config.json > config.json.new &&
  mv config.json.new config.json &&
  chmod 600 config.json &&
  echo "OK: config.json updated"
  cd ~ ;;
esac
```

Check from the VM that Strata answers (you should see the model's name):

🦞 **in the VM** (same terminal, `PC_IP` and `STRATA_KEY` are still set)

```shell
curl -s "http://$PC_IP:11434/v1/models" -H "Authorization: Bearer $STRATA_KEY" | jq .
```

<details markdown="1">
<summary>What did that block change?</summary>

- `vllm/` = "local OpenAI-compatible server". The model's name after it is not very important, Strata answers to anything.
- `tool_feedback`: the agent tells you in the chat before each tool it uses. That's how you *see what it does* before giving it more power.
- Web search: DuckDuckGo needs no API key (no Brave key needed, unlike openclaw), but it can be **off by default**, hence the explicit `true`. Brave works too if you have a key: `.tools.web.brave = {"enabled": true, "api_key": "..."}`.
- If you gave Strata less context than picoclaw assumes (`agents.defaults.context_window`, 131072 in the example config), lower it to match, e.g. `jq '.agents.defaults.context_window = 65536' config.json > config.json.new && mv config.json.new config.json`.
- Something went wrong? `ls ~/.picoclaw/config.json.*.bak`, and `cp` the last one back over `config.json`.

</details>

Let's skip the rest for now, you can put other stuff here (Telegram, MCP, skills...), see below, but let's start small.

### Talk to it

🦞 **in the VM**

```shell
picoclaw agent                                     # chat in the terminal (type exit, or Ctrl-C, to leave)
picoclaw agent -m "what's the weather in Paris?"   # one shot
picoclaw agent --debug -m "list the files in your workspace"   # same, with the gory details
```

Or the web UI: `picoclaw-launcher -public` in the VM, then http://127.0.0.1:18800 in your PC's browser.

Heads up: picoclaw runs its tools without asking you. It's kept in its workspace (`restrict_to_workspace`) and blocks the obvious nonsense (`rm -rf`, `sudo`, `curl | sh`...), but that's a seatbelt, not a cage. The cage is the VM. Watch what it does before giving it more.

<details markdown="1">
<summary>The agent loops on "blocked by safety guard", "access denied" or "path escapes workspace"?</summary>

picoclaw's `exec` tool has several guards, each with its own message. The loop comes from a small model that doesn't know the rules and keeps retrying. With `restrict_to_workspace` on (the default), absolute paths outside the workspace are refused in **three** places, and `..` in a command is refused too. On top of that, a built-in deny list refuses some shell constructs, whatever the path:

| What the model did | What you see |
|---|---|
| ran a command that mentions `/tmp/x.json`, `/usr/...`, `/proc/...`, `/mnt/...` | `Command blocked by safety guard (path outside working dir)` |
| asked `exec` to run in another folder (`cwd` = `/`...) | `Command blocked by safety guard (access denied: path is outside the workspace)` |
| `read_file` / `list_dir` on `/`, `/mnt`, `/proc/meminfo`... | `path escapes workspace: /proc/meminfo` |
| used `../` anywhere in a command | `Command blocked by safety guard (path traversal detected)` |
| used a construct from the deny list: `$(...)`, `${...}`, backticks, piping into `sh` or `bash`, `eval`, `source x.sh`, `kill`, `chmod 755`, `chown`, `sudo`, `rm -r`, `rm -f`, `git push`, `ssh user@host`... | `Command blocked by safety guard (dangerous pattern detected)` (it never says which one) |

Small models try `/tmp`, `/proc/meminfo` (that's Linux; the VM is NetBSD), `ls /`, get refused, and retry tiny variations until the tool-call limit (50 by default). Plain commands (`date`, `cal`, `python3 -c`, `curl https://...`) are not affected. Note that the guard reads the **whole text** of a command: a script written with a shell heredoc is refused if the script mentions a path, even if the file is harmless. The agent has to create files with `write_file`. (A `missing required property "action"` warning is harmless: the model forgot `action: "run"` and retries.) Two fixes, together, and two optional ones.

**1. Let the harmless system folders through, and cap a runaway loop.** One list, `tools.allow_read_paths`, covers the first three places above. This opens `/` itself (for `list_dir /`), `/tmp`, `/usr`, `/var`, `/bin`, `/sbin`, `/lib`, `/libexec`, `/etc` and `/proc`, and stops a loop after 30 tool calls (a real task needs 10 to 20; if you see "I've reached `max_tool_iterations`", raise the number). Still refused: `/mnt` (your shared folder, see 3 below), your home folder (that's where `~/.picoclaw/config.json`, with your keys, lives) and `/home`. Despite its name, `exec` also lets commands write in the listed folders (`write_file` still can't): fine for `/tmp` in a throwaway VM. Pasting this again is harmless.

🦞 **in the VM**

```shell
cd ~/.picoclaw &&
cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
jq '.tools.allow_read_paths = ((.tools.allow_read_paths // []) + ["^/$", "^/(tmp|usr|var|bin|sbin|lib|libexec|etc|proc)(/|$)"] | unique)
    | .agents.defaults.max_tool_iterations = 30' config.json > config.json.new &&
mv config.json.new config.json &&
chmod 600 config.json &&
echo "OK" ; cd ~
```

**2. Tell the agent the house rules.** `USER.md` in the workspace is added to every prompt. This writes a few lines into it. Paste it again later and it replaces its own section, so an older version of these rules never piles up:

🦞 **in the VM**

```shell
f=~/.picoclaw/workspace/USER.md
mkdir -p ~/.picoclaw/workspace && touch "$f" &&
{ awk '/^## House rules for the shell/{skip=1; next} /^## /{skip=0} !skip' "$f"
  cat <<'EOF'

## House rules for the shell

- This machine is NetBSD, not Linux: no /proc/meminfo, free, lscpu or apt. Use uname -a, sysctl hw.model hw.ncpu hw.physmem64, vmstat, df -h, ps aux.
- Work in your workspace with relative paths, never with "..", and never pass a cwd to exec. Scratch files go in ./tmp/ (mkdir -p tmp).
- exec always needs action "run" together with the command.
- Create files with write_file, not with heredocs or echo redirections in exec.
- The shell refuses these, so do not type them: $(...), ${...}, backticks, piping into sh or bash, eval, source x.sh, kill, pkill, chmod 755 (chmod +x is fine), chown, sudo, rm -r, rm -f, git push, ssh user@host. Run commands one at a time and read their output, or use python3. To delete a file: rm file.
- If a command or tool is refused ("blocked by safety guard", "dangerous pattern", "access denied", "path escapes workspace"), do not retry it with small variations. Try one different approach at most, then stop and tell me what you wanted to do.
- For dates, holidays and calendars, use date, cal, or a short python3 -c with the standard library (datetime, calendar). If you need data from the web: curl -s URL | jq. Do not download scripts.
- After 3 failed tool calls in a row, stop and ask me.
EOF
} | cat -s > "$f.new" &&
mv "$f.new" "$f" &&
echo "OK"
```

Then restart what you were running (Ctrl-C, start `picoclaw agent` or `picoclaw gateway` again).

**3. Optional: let the agent use the shared folder `/mnt`.** Without this, it can't put a file there, which is the right default: whatever it writes in `/mnt` appears in the shared folder on your PC, and it could also read, overwrite or delete what you keep there. If you want it anyway (exports, downloads, a script you asked it to write), this adds `/mnt` for exec, `read_file`, `list_dir` **and** `write_file` / `edit_file`. It still can't read its own `~/.picoclaw` that way: to save the agent's config, use the script in the next fold, as yourself.

🦞 **in the VM**

```shell
cd ~/.picoclaw &&
cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
jq '.tools.allow_read_paths = ((.tools.allow_read_paths // []) + ["^/mnt(/|$)"] | unique)
    | .tools.allow_write_paths = ((.tools.allow_write_paths // []) + ["^/mnt(/|$)"] | unique)' config.json > config.json.new &&
mv config.json.new config.json &&
chmod 600 config.json &&
echo "OK" ; cd ~
```

**4. Optional, if the deny list keeps getting in the way: switch it off.** picoclaw has no switch for single patterns, it is all or nothing. Off, the constructs in the table work (`$(...)`, `kill`, `rm -r`...). Still on: the path guard (`restrict_to_workspace`), so the agent stays in its workspace and in the folders you opened above. In a VM that you can rebuild and restore (see the next fold), that is a fair deal. To go back, run it again with `true`.

🦞 **in the VM**

```shell
cd ~/.picoclaw &&
cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
jq '.tools.exec.enable_deny_patterns = false' config.json > config.json.new &&
mv config.json.new config.json &&
chmod 600 config.json &&
echo "OK" ; cd ~
```

**Still refusing something?** The messages don't say which command it was. Start picoclaw with `picoclaw agent --debug` (or `picoclaw gateway --debug`): the line `Tool call: exec({...})` just before each error shows the exact command. That is also the best way to watch what the agent does before you give it more. For a path, the one to add to the list in part 1 is in that line.

The honest part: this guard is a text check, not a sandbox. It doesn't understand `~/` or `cd /`, so `cat ~/.picoclaw/config.json` still works for the agent. The keys in that file (Strata, and the Telegram bot token if you did chapter 5) are the only secrets the VM holds: if you ever doubt the agent, change them. The guard stops accidents, the VM stops the rest. The blunt alternative is `jq '.agents.defaults.restrict_to_workspace = false'`: `exec` and the file tools can then roam the whole VM, `/mnt` included, and the `rm -rf` & co deny patterns stay on (part 4 turns those off).

</details>

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

Built-ins: `weather` (no API key), `summarize` (URLs and files), `github` (the `gh` CLI), `tmux`, `agent-browser` (browser automation), `hardware` (Sipeed boards, useless here), `picoclaw-agent` (it knows picoclaw's own config, ask it for help!) and `skill-creator`, a skill to make skills: *"use the skill-creator skill to make me a skill that ..."*.

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

### The built-in tools, and the leash

<details markdown="1">
<summary>Which tools exist, how to tighten each, and what I'd switch off in week one</summary>

| Tool | What it does | How to tighten it (in `config.json`) |
| --- | --- | --- |
| `exec` | runs shell commands | `tools.exec.enabled`; deny patterns are on (`enable_deny_patterns`), add yours with `custom_deny_patterns` (regexes) |
| `read_file` `write_file` `edit_file` `append_file` `list_dir` | files | `agents.defaults.restrict_to_workspace` is `true`: only `~/.picoclaw/workspace` (and what you list in `tools.allow_read_paths` / `allow_write_paths`) |
| `web_search` `web_fetch` | search the web, read a page | `tools.web.*` (each engine has `enabled`) |
| `spawn` `subagent` | the agent starts helpers | `tools.spawn.enabled`, `tools.subagent.enabled` |
| `cron` | the agent schedules jobs for itself | `tools.cron.enabled`, `tools.cron.allow_command` |
| `install_skill` `find_skills` | the agent installs skills **by itself** | `tools.install_skill.enabled` |
| MCP tools | whatever your servers expose | `tools.mcp.servers.<name>.enabled` |

Also on by default: tool output is scrubbed of anything that looks like your keys and tokens before the model sees it (`tools.filter_sensitive_data`). Full reference: [tools configuration](https://github.com/sipeed/picoclaw/blob/main/docs/reference/tools_configuration.md).

My advice for week one: you pick the skills, not the agent. Switch off its power to install some, and to schedule shell commands:

🦞 **in the VM**

```shell
cd ~/.picoclaw &&
cp config.json "config.json.$(date +%Y%m%d-%H%M%S).bak" &&
jq '.tools.install_skill.enabled = false | .tools.cron.allow_command = false' config.json > config.json.new &&
mv config.json.new config.json &&
chmod 600 config.json &&
echo "OK" ; cd ~
```

Turn them back on when you trust it more (`true`). With `tool_feedback` on, you can see every tool call in the chat before you do.

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

## When it doesn't work

<details markdown="1">
<summary>Troubleshooting table</summary>

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Strata setup: "no NVIDIA GPU found"; `nvidia-smi`: "Driver/library version mismatch" | the loaded kernel module and the NVIDIA libraries are different versions (often after an `apt upgrade`) | reboot; if it persists, the "nvidia-smi fails" fold in chapter 1 |
| `ss` shows `127.0.0.1:11434` | Strata (or Ollama) listens on localhost only | host `0.0.0.0` in `strata-<model>.json` (or the Ollama override), restart |
| In the VM, `curl` to Strata hangs or is refused | wrong `PC_IP`, Strata on `127.0.0.1`, or your PC's address changed | redo "Find your PC's address", test with `curl` on the PC using that address, fix `api_base` |
| `401` / `403` / "unauthorized" | the key in `api_keys` isn't Strata's | `cat ~/.strata-key` on the PC, redo the config block |
| Huihui: setup stops on a SHA-256 or "wrong file" | the guard of step 2 is missing, or `STRATA_SKIP_SHA256=1` wasn't set on the setup line | redo steps 2 and 3 of the Huihui part; your files are safe in `$LLM_DIR/huihui-qfn` |
| Huihui answers like the stock model | a stock Unsloth pack was reused | move `$LLM_DIR/Strata-data/packs/unsloth-ud-iq4_xs` away, run step 3 again |
| `Could not access KVM kernel module` | no virtualization | see the KVM part of chapter 2 (BIOS, `modprobe`, `kvm` group) |
| `./smoler.sh run` can't find the image | the pull didn't finish | `./smoler.sh images`; if the list is empty, `pull` again (or `build`) |
| `Could not set up host forwarding rule` | port 2289, 18789 or 18800 already used (another VM still running?) | `ss -tlnp \| grep -E '18789\|18800\|2289'` |
| Agent says it has no model / wrong model | `agents.defaults.model_name` isn't a `model_list[].model_name` | both are `strata` in the block above; `jq '.agents.defaults, .model_list' ~/.picoclaw/config.json` |
| Agent loops on "blocked by safety guard", "access denied", "path escapes workspace", "path traversal" or "dangerous pattern" | picoclaw refuses absolute paths outside the workspace (`/tmp`, `/proc`, `/mnt`...) in `exec` commands, in `exec`'s `cwd`, and in `read_file` / `list_dir`, and `../` in any command, plus a deny list of shell constructs (`$(...)`, `kill`, `rm -r`...); the model keeps retrying | the fold under "Talk to it" in chapter 3 |
| I want my agent back after a rebuild, an update or a bug | its whole state is one folder, `~/.picoclaw`, and the VM is disposable | "Save and restore the agent", right after, in chapter 3 |
| Answers, but never uses a tool | model not tool-capable (Ollama), or `exec`/`web` switched off | `picoclaw agent --debug -m "list your tools"` |
| Web search finds nothing | DuckDuckGo disabled, or the VM has no internet | `jq .tools.web ~/.picoclaw/config.json`; `curl -sI https://duckduckgo.com` |
| Telegram bot is silent | wrong token; `allow_from` isn't your numeric ID; gateway not running | `picoclaw gateway --debug`, read it |
| Telegram `409 Conflict` | two gateways poll the same bot token (e.g. an old VM) | stop one |
| Config is broken | typo in a hand edit | `jq . ~/.picoclaw/config.json` finds it; restore a `config.json.*.bak` |
| Nothing works since the PC rebooted | your router gave the PC a new address | redo "Find your PC's address" + the config block, then reserve the address in the router. Stop-gap: QEMU always shows your PC to the VM as `10.0.2.2` |

</details>

## To Be Continued

- Start the gateway on its own when the VM boots.
- Keep `~/.picoclaw` outside the VM, so a rebuild doesn't wipe it.
- Give it a local search engine (SearXNG) instead of DuckDuckGo, and a ComfyUI skill for the French girls.
- Look at what it did overnight (`~/.picoclaw/workspace`), and only then, hand it more tools.

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
- Skills: [ClawHub](https://clawhub.ai), [REA](https://github.com/morluto/rea) ([site](https://rea.tools), [npm](https://www.npmjs.com/package/rea-agents), [skills.sh](https://skills.sh/morluto/rea/reverse-engineer-anything)), [Ghidra](https://github.com/NationalSecurityAgency/ghidra/releases), [JDK](https://adoptium.net), [Node.js](https://nodejs.org/en/download)
- Telegram: [@BotFather](https://t.me/BotFather), [@userinfobot](https://t.me/userinfobot)
