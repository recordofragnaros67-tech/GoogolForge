#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge one-line installer for Termux:
#   curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/install.sh | bash
set -e
URL="https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/googolforge_setup.sh"
DEST="${TMPDIR:-$HOME}/googolforge_setup.sh"
command -v curl >/dev/null || pkg install -y curl
echo "Downloading GoogolForge setup..."
curl -fsSL "$URL" -o "$DEST"
bash -n "$DEST" || { echo "Download looks broken, try again on Wi-Fi"; exit 1; }
bash "$DEST" </dev/tty
echo
echo "=================================================="
echo "  IMPORTANT: reload your shortcuts before using forge:"
echo "      exec bash"
echo "  (or open a new Termux session)"
echo "=================================================="
