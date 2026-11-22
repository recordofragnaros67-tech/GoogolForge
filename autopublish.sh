#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Auto-Publish v1.0
#   forge autopublish on      check every 30 minutes, publish only clean new work
#   forge autopublish off     stop
#   forge autopublish status  on/off + last 8 log lines
#   forge autopublish now     publish right now (still runs the quality gate)
GF="$HOME/googolforge"; LOG="$GF/autopublish.log"; JOB="$GF/autopublish.sh run"
stamp() { date "+%Y-%m-%d %H:%M"; }
case "${1:-status}" in
  on)
    command -v crond >/dev/null || pkg install -y cronie termux-services
    ( crontab -l 2>/dev/null | grep -v "autopublish.sh"; echo "*/30 * * * * bash $JOB >> $LOG 2>&1" ) | crontab -
    sv-enable crond >/dev/null 2>&1 || pgrep crond >/dev/null || crond
    gh auth status >/dev/null 2>&1 || echo "Heads up: run  gh auth login  once, or nothing can publish."
    echo "Auto-publish ON: every 30 minutes, only when your code changed and passes checks."
    echo "Keep Termux running in the background (Settings > Apps > Termux > Battery > Unrestricted)." ;;
  off)
    crontab -l 2>/dev/null | grep -v "autopublish.sh" | crontab -
    echo "Auto-publish OFF." ;;
  status)
    crontab -l 2>/dev/null | grep -q "autopublish.sh" && echo "Auto-publish: ON" || echo "Auto-publish: OFF"
    [ -f "$LOG" ] && tail -n 8 "$LOG" || echo "No runs yet." ;;
  run|now)
    mkdir "$GF/.publock" 2>/dev/null || { echo "$(stamp) skipped: a publish is already running"; exit 0; }
    trap 'rmdir "$GF/.publock" 2>/dev/null' EXIT
    cd "$GF" || exit 1
    if ! gh auth status >/dev/null 2>&1; then echo "$(stamp) skipped: not signed in (run gh auth login)"; exit 0; fi
    HASH=$( { cat forge.py; ls workspace/*.py >/dev/null 2>&1 && cat workspace/*.py; } 2>/dev/null | sha256sum | cut -c1-16)
    if [ "$1" = "run" ] && [ "$HASH" = "$(cat .last_publish 2>/dev/null)" ]; then echo "$(stamp) no changes"; exit 0; fi
    # Quality gate: every file must compile; files with built-in tests must pass them
    BAD=""
    for f in workspace/*.py; do
      [ -e "$f" ] || continue
      python -B -m py_compile "$f" 2>/dev/null || { BAD="$BAD $(basename "$f")"; continue; }
      if grep -q "ALL TESTS PASSED" "$f"; then
        timeout 30 python -B "$f" </dev/null 2>/dev/null | grep -q "ALL TESTS PASSED" || BAD="$BAD $(basename "$f")"
      fi
    done
    if [ -n "$BAD" ]; then echo "$(stamp) held back: fix these first ->$BAD  (try: forge debug FILE)"; exit 0; fi
    termux-wake-lock 2>/dev/null || true
    if GF_AUTO=1 bash "$GF/publish.sh" > "$GF/.publish_out" 2>&1; then
      echo "$HASH" > .last_publish
      echo "$(stamp) published: $(grep -o 'https://[^ ]*github.io[^ ]*' .publish_out | head -1)"
    else
      echo "$(stamp) publish failed: $(tail -n 2 .publish_out | tr '\n' ' ')"
    fi
    rm -f .publish_out
    termux-wake-unlock 2>/dev/null || true ;;
  *) sed -n '2,6p' "$0" ;;
esac
