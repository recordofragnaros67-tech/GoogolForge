#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Voice v1.0: speak a command, the Assistant runs it, the phone answers out loud.
# Needs the Termux:API app (F-Droid) + pkg install termux-api, and the mic permission.
GF="$HOME/googolforge"
say() { echo "$1"; command -v termux-tts-speak >/dev/null && termux-tts-speak "$1" 2>/dev/null; }
if ! command -v termux-speech-to-text >/dev/null; then
  echo "Voice needs Termux:API."
  echo "1) Install the Termux:API app from F-Droid (same source as Termux)"
  echo "2) Run: pkg install -y termux-api"
  echo "3) Run forge voice again and allow the microphone"
  exit 1
fi
LOOP=0; [ "$1" = "--loop" ] && LOOP=1
while true; do
  say "Listening."
  TEXT="$(termux-speech-to-text 2>/dev/null | tr -d '\r' | tail -n 1)"
  if [ -z "$TEXT" ]; then
    say "I didn't catch that."
  else
    echo "you said> $TEXT"
    case "$(echo "$TEXT" | tr 'A-Z' 'a-z')" in
      stop|exit|quit|goodbye|"stop listening") say "Goodbye."; exit 0;;
    esac
    python "$GF/assistant.py" "$TEXT"
    say "Done."
  fi
  [ "$LOOP" = 1 ] || break
done
