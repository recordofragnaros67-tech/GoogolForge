#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Genius Run v3.6: copy and paste the whole block into Termux.
# It updates GoogolForge, checks RAM, picks the strongest model your phone can hold,
# runs the sealed Hard exam, shows wrong answers, and saves a report.
set -u
T="${TMPDIR:-$HOME}"; LOG="$HOME/googolforge/genius_run_$(date +%Y%m%d_%H%M).txt"
say(){ printf '\n\033[1;33m== %s ==\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
bad(){ printf '\033[1;31m[!!]\033[0m %s\n' "$*"; }

say "1/7 Tools"
for p in curl git python ollama; do
  command -v "$p" >/dev/null 2>&1 && ok "$p found" || { bad "$p missing, installing"; pkg install -y "$p" >/dev/null 2>&1 && ok "$p installed" || bad "could not install $p"; }
done

say "2/7 Update GoogolForge (free, from GitHub)"
curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/install.sh -o "$T/gf_install.sh" \
  && bash "$T/gf_install.sh" >"$T/gf_install.log" 2>&1 && ok "GoogolForge updated" || { bad "update failed, see $T/gf_install.log"; }
hash -r
command -v forge >/dev/null || export PATH="$PREFIX/bin:$HOME/googolforge:$PATH"
command -v forge >/dev/null && ok "forge ready" || { bad "forge not found. Run: exec bash, then paste this again."; return 1 2>/dev/null || exit 1; }

say "3/7 Start the local AI engine"
if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null; then
  nohup ollama serve >"$T/ollama.log" 2>&1 &
  for i in $(seq 1 30); do curl -s http://127.0.0.1:11434/api/tags >/dev/null && break; sleep 1; done
fi
curl -s http://127.0.0.1:11434/api/tags >/dev/null && ok "Ollama running" || { bad "Ollama did not start, see $T/ollama.log"; exit 1; }

say "4/7 Pick the strongest brain your RAM allows"
FREE_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
echo "RAM: ${FREE_MB} MB free of ${TOTAL_MB} MB"
FAST="qwen2.5-coder:1.5b"
if [ "$FREE_MB" -ge 5500 ]; then STRONG="qwen2.5-coder:7b"
elif [ "$FREE_MB" -ge 2600 ]; then STRONG="qwen2.5-coder:3b"
else STRONG="qwen2.5-coder:1.5b"; bad "Low RAM. Close other apps for a stronger brain."; fi
[ "${GF_STRONG:-}" ] && STRONG="$GF_STRONG"
ok "fast=$FAST  strong=$STRONG"
for m in "$FAST" "$STRONG"; do
  ollama list 2>/dev/null | grep -q "^${m}" && ok "$m present" || { echo "Downloading $m (one time, needs Wi-Fi)..."; ollama pull "$m" && ok "$m downloaded" || bad "pull $m failed"; }
done

say "5/7 Keep the phone awake"
command -v termux-wake-lock >/dev/null && termux-wake-lock && ok "wake lock on" || echo "(optional) install Termux:API for wake lock"

say "6/7 Sealed Hard exam, Genius mode (takes 10-40 min)"
START=$(date +%s)
forge bench "$FAST" --genius --hard --strong="$STRONG" 2>&1 | tee "$LOG"
END=$(date +%s)
SCORE=$(grep -o 'SCORE [0-9]*/100' "$LOG" | tail -1)

say "7/7 What it got wrong"
forge bench losses 2>&1 | tee -a "$LOG"
command -v termux-wake-unlock >/dev/null && termux-wake-unlock

say "RESULT"
echo "Device : $(getprop ro.product.model 2>/dev/null || echo unknown)"
echo "Models : $FAST + $STRONG"
echo "Result : ${SCORE:-no score line found}"
echo "Time   : $((END-START))s"
echo "Report : $LOG"
command -v termux-notification >/dev/null && termux-notification -t "GoogolForge" -c "Genius Hard: ${SCORE:-done}" >/dev/null 2>&1
echo "Paste the RESULT block back to Hark."
