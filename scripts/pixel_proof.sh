#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Pixel Proof Run v3.8 - copy and paste the whole block into Termux.
# Goal: the first REAL scores measured on your phone, labeled "Pixel 8", for the Page and for the
# AI Builder Nights demo (Dec 15). Nothing here is tuned on the holdout; it is the honest check.
#
#   bash pixel_proof.sh          core plan  (about 20-60 min): selftest + 4 quick exams + holdout
#   bash pixel_proof.sh full     core + Genius Hard + full HumanEval+ 40 (can take 2-4 hours)
#   bash pixel_proof.sh demo     a 3-minute live demo for a show-and-tell (1 quick exam)
#
# Safe: free and open source, no accounts, no payments. Writes only under ~/googolforge.
set -u
PLAN="${1:-core}"
T="${TMPDIR:-$HOME}"
OUT="$HOME/googolforge/pixel_runs"; mkdir -p "$OUT"
STAMP=$(date +%Y%m%d_%H%M)
LOG="$OUT/pixel_proof_${STAMP}.txt"
JSON="$OUT/pixel_proof_${STAMP}.json"
say(){ printf '\n\033[1;33m== %s ==\033[0m\n' "$*" | tee -a "$LOG"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*" | tee -a "$LOG"; }
bad(){ printf '\033[1;31m[!!]\033[0m %s\n' "$*" | tee -a "$LOG"; }
: > "$LOG"
case "$PLAN" in core|full|demo) ;; *) bad "Unknown plan '$PLAN'. Use: core | full | demo"; exit 1;; esac

# ---------------------------------------------------------------- 1. tools
say "1/8 Tools"
command -v pkg >/dev/null || { bad "This script is for Termux on Android."; exit 1; }
for p in curl git python ollama; do
  if command -v "$p" >/dev/null 2>&1; then ok "$p found"
  else bad "$p missing, installing"; pkg install -y "$p" >>"$LOG" 2>&1 && ok "$p installed" || { bad "could not install $p"; exit 1; }
  fi
done

# ---------------------------------------------------------------- 2. update
say "2/8 Update GoogolForge to the latest (v3.8+)"
if curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/install.sh -o "$T/gf_install.sh" \
   && bash -n "$T/gf_install.sh" && bash "$T/gf_install.sh" </dev/null >"$T/gf_install.log" 2>&1; then
  ok "GoogolForge updated"
else
  bad "update failed (see $T/gf_install.log); continuing with the installed copy"
fi
hash -r
command -v forge >/dev/null || export PATH="$PREFIX/bin:$HOME/googolforge:$PATH"
command -v forge >/dev/null && ok "forge ready" || { bad "forge not found. Run: exec bash   then paste this again."; exit 1; }

# ---------------------------------------------------------------- 3. engine
say "3/8 Start the local AI engine"
if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null; then
  nohup ollama serve >"$T/ollama.log" 2>&1 &
  for i in $(seq 1 40); do curl -s http://127.0.0.1:11434/api/tags >/dev/null && break; sleep 1; done
fi
curl -s http://127.0.0.1:11434/api/tags >/dev/null && ok "Ollama $(ollama -v 2>/dev/null | grep -o '[0-9.]*' | head -1) running" \
  || { bad "Ollama did not start, see $T/ollama.log"; exit 1; }

# ---------------------------------------------------------------- 4. models
say "4/8 Pick models your RAM can hold"
FREE_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
echo "RAM: ${FREE_MB} MB free of ${TOTAL_MB} MB" | tee -a "$LOG"
FAST="qwen2.5-coder:1.5b"
if   [ "$FREE_MB" -ge 5500 ]; then STRONG="qwen2.5-coder:7b"
elif [ "$FREE_MB" -ge 2600 ]; then STRONG="qwen2.5-coder:3b"
else STRONG="qwen2.5-coder:1.5b"; bad "Low RAM: close other apps for a stronger model"; fi
[ -n "${GF_STRONG:-}" ] && STRONG="$GF_STRONG"
for m in "$FAST" "$STRONG" "llama3.2:1b"; do
  if ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$m"; then ok "$m present"
  else echo "Downloading $m (one time, use Wi-Fi)..." | tee -a "$LOG"; ollama pull "$m" >>"$LOG" 2>&1 && ok "$m downloaded" || bad "pull $m failed"; fi
done
ok "fast=$FAST  strong=$STRONG"
PAIR="1.5B+$(echo "$STRONG" | sed 's/.*://; s/b$/B/')"

# ---------------------------------------------------------------- 5. stay awake
say "5/8 Keep the phone awake"
if command -v termux-wake-lock >/dev/null; then termux-wake-lock && ok "wake lock on"
else echo "Tip: keep the screen on, or install Termux:API from F-Droid for a wake lock." | tee -a "$LOG"; fi
echo "Tip: Settings > Apps > Termux > Battery > Unrestricted stops Android from killing long runs." | tee -a "$LOG"

# ---------------------------------------------------------------- 6. selftest
say "6/8 Selftest (all modules)"
if forge test 2>&1 | tee -a "$LOG" | grep -qiE "fail|error"; then bad "a selftest failed (details above)"; SELF="fail"
else ok "selftests passed"; SELF="pass"; fi

# ---------------------------------------------------------------- 7. exams
say "7/8 Exams (sealed judge: the AI never sees the hidden tests)"
ROWS=""
exam(){ # exam "Label" args...
  local label="$1"; shift
  local f="$T/gf_exam_$$.txt" s e score solved secs
  echo; echo ">>> $label   (forge bench $*)" | tee -a "$LOG"
  s=$(date +%s)
  forge bench "$@" 2>&1 | tee "$f" | tee -a "$LOG"
  e=$(date +%s)
  score=$(grep -o 'SCORE [0-9]*/100' "$f" | tail -1 | grep -o '[0-9]*/100')
  solved=$(grep -o 'Solved [0-9]*/[0-9]*' "$f" | tail -1 | cut -d' ' -f2)
  secs=$((e - s))
  [ -z "$score" ] && { bad "$label: no score line (crash or too little RAM?)"; score="none"; solved="-"; }
  ROWS="$ROWS$(printf '%-34s %-8s %-7s %6ss' "$label" "$score" "$solved" "$secs")\n"
  printf '{"label":"%s","args":"%s","score":"%s","solved":"%s","seconds":%s},' "$label" "$*" "$score" "$solved" "$secs" >> "$JSON.tmp"
  rm -f "$f"
}
: > "$JSON.tmp"
START=$(date +%s)
case "$PLAN" in
  demo)
    echo "Live demo: a small local AI writes code on this phone, and a sealed judge grades it." | tee -a "$LOG"
    exam "Arena quick, plain (demo)"          "$FAST" --quick ;;
  core|full)
    exam "Arena quick, plain"                 "$FAST" --quick
    exam "HumanEval+ quick 8, plain"          "$FAST" --heplus --quick
    exam "MBPP+ quick 8, plain"               "$FAST" --mbppplus --quick
    exam "Holdout 6, plain (never tuned)"     "$FAST" --holdout
    if [ "$PLAN" = full ]; then
      exam "Genius Hard 6, $PAIR"     "$FAST" --genius --hard --strong="$STRONG"
      exam "HumanEval+ 40, plain"             "$FAST" --heplus
      exam "Holdout 6, Genius $PAIR"  "$FAST" --genius --holdout --strong="$STRONG"
    fi ;;
esac
END=$(date +%s)
command -v termux-wake-unlock >/dev/null && termux-wake-unlock

# ---------------------------------------------------------------- 8. report
say "8/8 RESULT (Pixel 8, on-device)"
DEV="$(getprop ro.product.manufacturer 2>/dev/null) $(getprop ro.product.model 2>/dev/null)"
{
  echo "Machine  : ${DEV:-unknown} (on-device, Termux, Ollama)"
  echo "Android  : $(getprop ro.build.version.release 2>/dev/null)   RAM free at start: ${FREE_MB}/${TOTAL_MB} MB"
  echo "Models   : fast=$FAST strong=$STRONG judge=llama3.2:1b"
  echo "Plan     : $PLAN   Selftest: $SELF   Total time: $((END - START))s"
  echo
  printf '%-34s %-8s %-7s %7s\n' "Exam" "Score" "Solved" "Time"
  printf "$ROWS"
} | tee -a "$LOG"
printf '{"machine":"%s","plan":"%s","selftest":"%s","fast":"%s","strong":"%s","free_mb":%s,"date":"%s","exams":[%s]}\n' \
  "${DEV:-unknown} (on-device)" "$PLAN" "$SELF" "$FAST" "$STRONG" "$FREE_MB" "$(date -Iminutes)" \
  "$(sed 's/,$//' "$JSON.tmp")" > "$JSON"; rm -f "$JSON.tmp"
echo
echo "Saved: $LOG"
echo "Saved: $JSON"
command -v termux-notification >/dev/null && termux-notification -t "GoogolForge" -c "Pixel proof run done ($PLAN)" >/dev/null 2>&1
echo "Paste the RESULT block back to Hark; it goes on the Page labeled Pixel 8."
