#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Autopilot v3.10: runs the whole routine in order, resumes where it stopped,
# and suggests the next move from this phone's own scores. Nothing is published automatically.
# Usage: bash autopilot.sh            run the sequence (skips steps already done today)
#        bash autopilot.sh --fresh    start the sequence over
#        bash autopilot.sh --suggest  only print suggestions from your scores
#        bash autopilot.sh --schedule run it every night at 3:00 (needs cronie)
#        bash autopilot.sh --unschedule
GF="$HOME/googolforge"; RAW="https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main"
STATE="$GF/autopilot_state"; LOG="$GF/autopilot_$(date +%Y%m%d).log"; TODAY=$(date +%Y-%m-%d)
mkdir -p "$GF"
ok(){ printf '\033[32m[OK]\033[0m %s\n' "$1" | tee -a "$LOG"; }
bad(){ printf '\033[31m[!!]\033[0m %s\n' "$1" | tee -a "$LOG"; }
step(){ printf '\n\033[33m== %s ==\033[0m\n' "$1" | tee -a "$LOG"; }
done_today(){ grep -qx "$TODAY $1" "$STATE" 2>/dev/null; }
mark(){ echo "$TODAY $1" >> "$STATE"; }
command -v forge >/dev/null || export PATH="$PREFIX/bin:$GF:$PATH"

suggest(){
  step "Suggestions from your scores"
  python3 - "$GF/bench_history.json" <<'PY'
import json, sys
try:
    h = json.load(open(sys.argv[1]))
except Exception:
    print("No exams on this phone yet. Next: run the sequence (it starts with a quick exam)."); sys.exit()
last = {}
for r in h:
    key = r.get("suite", "arena") + ("-hard" if r.get("hard") else "") + "/" + r.get("style", "plain")
    last[key] = r
tips = []
for k, r in sorted(last.items(), key=lambda kv: kv[1].get("score", 0)):
    s, n = r.get("score", 0), f"{r.get('solved', 0)}/{r.get('tasks', 0)}"
    print(f"  {k:<22} score {s:>3}  solved {n:<6} {r.get('seconds', 0)//60} min  ({str(r.get('date', ''))[:16]})")
    if s < 50:
        tips.append(f"{k}: below 50. Run 'forge bench losses' right after the next {k.split('/')[0]} exam to see the wrong answers.")
    elif s < 80 and r.get("style") == "plain":
        tips.append(f"{k}: try Genius mode on this set ('forge bench --genius ...'); it is slower but solved 1-2 more on GitHub tests.")
if not any(k.startswith("holdout") for k in last):
    tips.append("No holdout score yet: it is the honest test. Run 'forge bench --holdout' once; never tune on it.")
if not any(r.get("style") == "genius" for r in last.values()):
    tips.append("No Genius run on this phone yet. Plug in the charger and run the Genius exam from the dashboard.")
print("\nNext moves:")
for t in tips[:3] or ["Scores are steady. Build something: forge team \"<idea>\", then show it at Builder Nights."]:
    print("  - " + t)
PY
}

case "$1" in
  --suggest) suggest; exit 0 ;;
  --fresh) rm -f "$STATE"; ok "sequence reset" ;;
  --schedule)
    pkg install -y cronie termux-services >/dev/null 2>&1 || { bad "could not install cronie"; exit 1; }
    curl -fsSL "$RAW/scripts/autopilot.sh" -o "$GF/autopilot.sh" || { bad "download failed"; exit 1; }
    ( crontab -l 2>/dev/null | grep -v googolforge/autopilot.sh; echo "0 3 * * * bash $GF/autopilot.sh >/dev/null 2>&1" ) | crontab -
    sv-enable crond 2>/dev/null || crond
    ok "Autopilot runs every night at 3:00. Keep the phone charging. Undo: bash autopilot.sh --unschedule"
    exit 0 ;;
  --unschedule) crontab -l 2>/dev/null | grep -v googolforge/autopilot.sh | crontab -; ok "nightly autopilot removed"; exit 0 ;;
esac

termux-wake-lock 2>/dev/null
trap 'termux-wake-unlock 2>/dev/null' EXIT

step "1/6 Update"
if done_today update; then ok "already updated today"
elif curl -fsSL "$RAW/install.sh" -o "$GF/.install.sh" && bash "$GF/.install.sh" >>"$LOG" 2>&1; then ok "updated"; mark update
else bad "update failed (Wi-Fi?) - continuing with the installed version"; fi

step "2/6 Local AI"
pgrep -x ollama >/dev/null || { nohup ollama serve >"$GF/ollama.log" 2>&1 & sleep 6; }
if pgrep -x ollama >/dev/null; then ok "AI running"; else bad "AI did not start. Run forge-start, then this again."; exit 1; fi

step "3/6 Self-test"
if done_today selftest; then ok "already passed today"
elif forge test >>"$LOG" 2>&1; then ok "all systems pass"; mark selftest
else bad "self-test reported a problem (see $LOG). Stopping so nothing runs broken."; exit 1; fi

step "4/6 Quick exam"
if done_today quick; then ok "already done today"
elif forge bench --quick 2>&1 | tee -a "$LOG" | grep -E "SCORE|Solved"; then mark quick; ok "quick exam saved"
else bad "quick exam failed"; fi

step "5/6 Genius exam (only when charging)"
CHG=$(termux-battery-status 2>/dev/null | grep -o '"plugged": *"[A-Z_]*"' | grep -v UNPLUGGED)
if done_today genius; then ok "already done today"
elif [ -n "$CHG" ] || [ "$GF_FORCE_GENIUS" = 1 ]; then
  forge bench --genius --hard 2>&1 | tee -a "$LOG" | grep -E "SCORE|Solved" && mark genius && ok "Genius exam saved"
  forge bench losses >>"$LOG" 2>&1
else ok "skipped: plug in the charger (or set GF_FORCE_GENIUS=1) for the long Genius exam"; fi

step "6/6 Report"
suggest | tee -a "$LOG"
echo
ok "Done. Full log: $LOG"
echo "Paste the Next moves section to Hark for a plan. Open the dashboard with: forge web"
