#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Grandmaster v3.12: the whole routine on autopilot, with a local AI Coach.
#
#   Prepare -> Update -> Start AI -> Pick models by RAM -> Self-test -> Baseline exam
#   -> AI Coach loop (the local model picks the next move from a safe menu, it runs, scores are
#      re-read, repeat) -> Report with next moves -> phone notification.
#
# Every score is a real sealed-judge result. Nothing is inflated, nothing is published, and the
# Coach can only choose moves from the menu below (no free-form commands).
#
# Usage: bash grandmaster.sh                 plan, then run (each move auto-confirms after 15s)
#        bash grandmaster.sh --yes           fully automatic, no questions
#        bash grandmaster.sh --dry           show the Coach's plan only, run no exams
#        bash grandmaster.sh --minutes 90    time budget for the Coach loop (default 60)
#        bash grandmaster.sh --rounds 4      most Coach moves (default 3)
#        bash grandmaster.sh --schedule      every night at 3:30, fully automatic (needs cronie)
#        bash grandmaster.sh --unschedule
#        bash grandmaster.sh --report        show the last report
# Env: GF_STRONG=qwen2.5-coder:7b  force the strong model   GF_FORCE_GENIUS=1  run long exams unplugged
#      GF_SKIP_UPDATE=1  skip the update                     GF_OLLAMA=http://127.0.0.1:11434

VER="3.12"
GF="$HOME/googolforge"; RAW="https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main"
API="${GF_OLLAMA:-http://127.0.0.1:11434}"; TMP="${TMPDIR:-$HOME}"
STAMP=$(date +%Y%m%d_%H%M); LOG="$GF/grandmaster_$STAMP.log"; REPORT="$GF/grandmaster_$STAMP.md"
SESSION="$GF/.gm_session_$STAMP.tsv"
YES=0; DRY=0; MINUTES=60; ROUNDS=3
mkdir -p "$GF"
command -v forge >/dev/null 2>&1 || export PATH="${PREFIX:-/usr}/bin:$GF:$PATH"

c(){ printf '\033[%sm%s\033[0m' "$1" "$2"; }
ok(){ echo "$(c 32 '[OK]') $1"; echo "[OK] $1" >>"$LOG"; }
bad(){ echo "$(c 31 '[!!]') $1"; echo "[!!] $1" >>"$LOG"; }
info(){ echo "$(c 36 '[..]') $1"; echo "[..] $1" >>"$LOG"; }
step(){ printf '\n%s\n' "$(c 33 "== $1 ==")"; echo "== $1 ==" >>"$LOG"; }
notify(){ command -v termux-notification >/dev/null 2>&1 && termux-notification --title "GoogolForge Grandmaster" --content "$1" >/dev/null 2>&1; true; }
elapsed_min(){ echo $(( ( $(date +%s) - T0 ) / 60 )); }

# ---------- flags ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --dry) DRY=1 ;;
    --minutes) shift; MINUTES="${1:-60}" ;;
    --rounds) shift; ROUNDS="${1:-3}" ;;
    --report)
      R=$(ls -t "$GF"/grandmaster_*.md 2>/dev/null | head -1)
      [ -n "$R" ] && cat "$R" || echo "No report yet. Run: bash grandmaster.sh"; exit 0 ;;
    --schedule)
      pkg install -y cronie termux-services >/dev/null 2>&1 || { bad "could not install cronie"; exit 1; }
      curl -fsSL "$RAW/scripts/grandmaster.sh" -o "$GF/grandmaster.sh" || { bad "download failed"; exit 1; }
      ( crontab -l 2>/dev/null | grep -v googolforge/grandmaster.sh
        echo "30 3 * * * bash $GF/grandmaster.sh --yes --minutes 90 >/dev/null 2>&1" ) | crontab -
      sv-enable crond 2>/dev/null || crond
      ok "Grandmaster runs every night at 3:30, fully automatic. Keep the phone charging."
      ok "Read the result in the morning with: bash ~/googolforge/grandmaster.sh --report"
      exit 0 ;;
    --unschedule) crontab -l 2>/dev/null | grep -v googolforge/grandmaster.sh | crontab -; ok "nightly Grandmaster removed"; exit 0 ;;
    -h|--help) sed -n 2,22p "$0"; exit 0 ;;
    *) bad "unknown option $1 (try --help)"; exit 1 ;;
  esac
  shift
done
case "$MINUTES$ROUNDS" in *[!0-9]*) bad "--minutes and --rounds need whole numbers"; exit 1 ;; esac

T0=$(date +%s)
DEVICE=$(getprop ro.product.model 2>/dev/null); DEVICE=${DEVICE:-this device}
: >"$SESSION"
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
cleanup(){ command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock; rm -f "$SESSION"; }
trap cleanup EXIT
echo "$(c 35 "GoogolForge Grandmaster v$VER")  $(date '+%Y-%m-%d %H:%M')  budget ${MINUTES} min, up to ${ROUNDS} Coach moves"
[ "$DRY" = 1 ] && info "Dry run: the Coach plans, no exams run."

# ---------- 1. prepare ----------
step "1/7 Prepare"
for p in curl python3 git; do
  command -v "$p" >/dev/null 2>&1 || { info "installing $p"; pkg install -y "${p/python3/python}" >>"$LOG" 2>&1; }
done
command -v python3 >/dev/null 2>&1 || { bad "python3 is missing. Run: pkg install python"; exit 1; }
FREE_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null); FREE_MB=${FREE_MB:-0}
DISK_MB=$(df -m "$HOME" 2>/dev/null | awk 'NR==2{print $4}'); DISK_MB=${DISK_MB:-0}
BATT=$(termux-battery-status 2>/dev/null | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(str(d.get("percentage","?"))+" "+d.get("plugged","?"))
except Exception:
    print("? UNKNOWN")' 2>/dev/null)
PCT=${BATT%% *}; PLUG=${BATT#* }
CHARGING=0; case "$PLUG" in UNPLUGGED|UNKNOWN|"") ;; *) CHARGING=1 ;; esac
[ "${GF_FORCE_GENIUS:-0}" = 1 ] && CHARGING=1
ok "free RAM ${FREE_MB} MB, free storage ${DISK_MB} MB, battery ${PCT}% (${PLUG})"
[ "$DISK_MB" -gt 0 ] && [ "$DISK_MB" -lt 1500 ] && bad "less than 1.5 GB free storage: model downloads may fail"
[ "$CHARGING" = 0 ] && info "Not charging: long Genius exams are skipped. Plug in, or set GF_FORCE_GENIUS=1."

# ---------- 2. update ----------
step "2/7 Update"
if [ "${GF_SKIP_UPDATE:-0}" = 1 ]; then ok "skipped (GF_SKIP_UPDATE=1)"
elif curl -fsSL "$RAW/install.sh" -o "$TMP/.gf_install.sh" && bash "$TMP/.gf_install.sh" >>"$LOG" 2>&1; then
  ok "GoogolForge updated"; hash -r
else bad "update failed (Wi-Fi?) - continuing with the installed version"; fi
rm -f "$TMP/.gf_install.sh"
command -v forge >/dev/null 2>&1 || { bad "forge not found. Run the installer, then: exec bash"; exit 1; }

# ---------- 3. local AI ----------
step "3/7 Local AI"
api_up(){ curl -fs -m 3 "$API/api/tags" >/dev/null 2>&1; }
if ! api_up; then
  command -v ollama >/dev/null 2>&1 || { info "installing ollama"; pkg install -y ollama >>"$LOG" 2>&1; }
  nohup ollama serve >"$GF/ollama.log" 2>&1 &
  for _ in $(seq 1 20); do api_up && break; sleep 1; done
fi
api_up && ok "AI server answering at $API" || { bad "AI server did not start (see $GF/ollama.log)"; exit 1; }

# ---------- 4. models ----------
step "4/7 Models"
FAST="qwen2.5-coder:1.5b"
if [ -n "$GF_STRONG" ]; then STRONG="$GF_STRONG"
elif [ "$FREE_MB" -ge 5500 ]; then STRONG="qwen2.5-coder:7b"
elif [ "$FREE_MB" -ge 2600 ]; then STRONG="qwen2.5-coder:3b"
else STRONG="$FAST"; bad "low free RAM: close other apps for a stronger model"; fi
have(){ curl -fs -m 5 "$API/api/tags" | grep -q "\"$1\""; }
for m in "$FAST" "$STRONG"; do
  if have "$m"; then ok "$m ready"
  elif [ "$DRY" = 1 ]; then info "$m would be downloaded"
  else info "downloading $m (one time)"; ollama pull "$m" >>"$LOG" 2>&1 && ok "$m downloaded" || bad "could not download $m"; fi
done
have "$STRONG" || { [ "$DRY" = 1 ] || { STRONG="$FAST"; info "using $FAST as the strong model"; }; }
ok "fast $FAST, strong $STRONG"

# ---------- 5. self-test ----------
step "5/7 Self-test"
if [ "$DRY" = 1 ]; then info "skipped in dry run"
elif forge test >>"$LOG" 2>&1; then ok "all systems pass"
else bad "self-test reported a problem (see $LOG). Stopping so nothing runs broken."; notify "Self-test failed. See $LOG"; exit 1; fi

# ---------- the move menu (the only things the Coach may run) ----------
# id|label|minutes|needs charging|command
MENU="1|Quick exam (10 tasks, plain)|3|0|forge bench --quick
2|HumanEval+ quick, Genius (8 public tasks)|15|1|forge bench --heplus --quick --genius --strong=$STRONG
3|Genius Hard exam (6 tasks)|30|1|forge bench --genius --hard --strong=$STRONG
4|MBPP+ quick, Genius (8 public tasks)|15|1|forge bench --mbppplus --quick --genius --strong=$STRONG
5|Holdout check, Genius (6 never-tuned tasks)|40|1|forge bench --holdout --genius --strong=$STRONG
6|Model Shootout (picks the best model and prompt style)|20|1|forge shootout --apply
7|Stop here|0|0|true"
field(){ echo "$MENU" | awk -F'|' -v id="$1" -v f="$2" '$1==id{print $f}'; }

run_move(){  # $1 = move id; records score in the session table
  local id="$1" label cmd out score
  label=$(field "$id" 2); cmd=$(field "$id" 5)
  [ "$id" = 7 ] && return 0
  info "running: $label"
  echo "\$ $cmd" >>"$LOG"
  out=$($cmd 2>&1 | tee -a "$LOG" | tee /dev/stderr | grep -E "SCORE|Solved" | tail -2)
  score=$(echo "$out" | grep -o 'SCORE [0-9]*' | tail -1 | grep -o '[0-9]*')
  printf '%s\t%s\t%s\t%s\n' "$id" "$label" "${score:--}" "$(elapsed_min)" >>"$SESSION"
  [ -n "$score" ] && ok "$label: $score/100 (sealed judge)" || ok "$label: done"
}

# ---------- 6. baseline ----------
step "6/7 Baseline"
if [ "$DRY" = 1 ]; then info "dry run: baseline skipped"; else run_move 1; fi

# ---------- 7. AI Coach loop ----------
coach(){  # prints "id|reason"; the local model chooses, rules check it, rules decide if it fails
  python3 - "$API" "$FAST" "$GF/bench_history.json" "$SESSION" "$CHARGING" "$(( MINUTES - $(elapsed_min) ))" "$MENU" <<'PY'
import json, sys, urllib.request
api, model, hist, sess, charging, left, menu = sys.argv[1:8]
charging, left = charging == "1", int(left)
moves = {}
for line in menu.splitlines():
    i, label, mins, chg, _ = line.split("|", 4)
    moves[int(i)] = (label, int(mins), chg == "1")
done = [int(l.split("\t")[0]) for l in open(sess) if l.strip()] if sess else []
try:
    h = json.load(open(hist))
except Exception:
    h = []
last = {}
for r in h:
    k = r.get("suite", "arena") + ("-hard" if r.get("hard") else "") + "/" + r.get("style", "plain")
    last[k] = r
scores = "; ".join(f"{k} {r.get('score')}/100 ({r.get('solved')}/{r.get('tasks')})" for k, r in last.items()) or "none yet"

def allowed(i):
    lab, mins, chg = moves[i]
    return i == 7 or (i not in done and mins <= left and (charging or not chg) and not (i == 5 and 5 in done))

ok = [i for i in moves if allowed(i)]
# Rule order when the AI's answer is unusable: public sets first, holdout last, then stop.
rule = next((i for i in (2, 3, 4, 6, 5, 7) if i in ok), 7)
menu_txt = "\n".join(f"{i}. {moves[i][0]} (~{moves[i][1]} min)" for i in ok)
prompt = ("You are the coach for a coding-AI benchmark on a phone. Pick the ONE next move that teaches us the most "
          "about real quality. Prefer public sets before the holdout, and do not repeat a move.\n"
          f"Scores so far on this phone: {scores}\nMoves already done this session: {done or 'none'}\n"
          f"Minutes left: {left}\nAllowed moves:\n{menu_txt}\n"
          'Reply with JSON only: {"move": <number>, "why": "<one short sentence>"}')
pick, why = rule, "rule order (public sets first, holdout last)"
try:
    body = json.dumps({"model": model, "prompt": prompt, "stream": False, "format": "json",
                       "options": {"temperature": 0, "num_predict": 80}}).encode()
    req = urllib.request.Request(api + "/api/generate", body, {"Content-Type": "application/json"})
    local = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # talk to the phone's own AI directly
    ans = json.loads(json.loads(local.open(req, timeout=120).read())["response"])
    m = int(ans.get("move"))
    if m in ok:
        pick, why = m, ("AI Coach: " + str(ans.get("why", "")).strip().replace("|", "/"))[:160]
    else:
        why = f"AI Coach picked {m}, not allowed now; using rule order"
except Exception as e:
    why = f"AI Coach unavailable ({type(e).__name__}); using rule order"
print(f"{pick}|{why}")
PY
}

step "7/7 AI Coach"
PLAN=""
for r in $(seq 1 "$ROUNDS"); do
  CH=$(coach); ID=${CH%%|*}; WHY=${CH#*|}
  case "$ID" in [1-7]) ;; *) ID=7; WHY="Coach gave no answer" ;; esac
  LABEL=$(field "$ID" 2)
  echo "Round $r: $(c 35 "$LABEL")  -  $WHY"
  PLAN="$PLAN
| $r | $LABEL | $WHY |"
  [ "$ID" = 7 ] && break
  if [ "$DRY" = 1 ]; then
    printf '%s\t%s\t%s\t%s\n' "$ID" "$LABEL" "planned" "0" >>"$SESSION"; continue
  fi
  if [ "$YES" = 0 ]; then
    printf 'Run it? [Y/n] (auto-yes in 15s) '
    read -r -t 15 A </dev/tty 2>/dev/null; echo
    case "$A" in n|N|no|NO) info "skipped by you"; printf '%s\t%s\t%s\t%s\n' "$ID" "$LABEL" "skipped" "$(elapsed_min)" >>"$SESSION"; continue ;; esac
  fi
  run_move "$ID"
  [ "$(elapsed_min)" -ge "$MINUTES" ] && { info "time budget used"; break; }
done

# ---------- report ----------
SUG=""
if [ -f "$GF/autopilot.sh" ] || curl -fsSL "$RAW/scripts/autopilot.sh" -o "$GF/autopilot.sh" 2>/dev/null; then
  SUG=$(bash "$GF/autopilot.sh" --suggest 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -n '/Next moves/,$p' | tail -n +2)
fi
{
  echo "# GoogolForge Grandmaster report"
  echo
  echo "Version $VER, $(date '+%Y-%m-%d %H:%M'), $DEVICE (Termux), fast $FAST, strong $STRONG, $(elapsed_min) min."
  echo "Free RAM ${FREE_MB} MB, battery ${PCT}% (${PLUG}). Scores are sealed-judge results; nothing is inflated."
  echo
  echo "## Exams this session"
  echo
  echo "| Move | Score | At minute |"
  echo "|---|---|---|"
  awk -F'\t' '{print "| "$2" | "$3" | "$4" |"}' "$SESSION"
  echo
  echo "## Coach decisions"
  echo
  echo "| Round | Move | Why |"
  echo "|---|---|---|$PLAN"
  echo
  echo "## Next moves"
  echo
  echo "${SUG:-  - Run the Grandmaster again tomorrow and compare.}"
} >"$REPORT"
echo; cat "$REPORT"
BEST=$(awk -F'\t' '$3 ~ /^[0-9]+$/ {print $2": "$3"/100"}' "$SESSION" | tr '\n' ';' | sed 's/;$//; s/;/; /g')
notify "${BEST:-Plan ready}. Report: $REPORT"
echo
echo "$(c 32 '===== RESULT (send this to Hark) =====')"
echo "Grandmaster v$VER | fast $FAST | strong $STRONG | ${FREE_MB} MB free | $(elapsed_min) min"
echo "${BEST:-no exams run}"
echo "Report: $REPORT"
