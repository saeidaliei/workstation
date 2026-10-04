#!/usr/bin/env bash
set -euo pipefail
MARKER="$HOME/.config/i3-omarchy-firstboot-done"
[[ -e "$MARKER" ]] && exit 0
sleep 2
if command -v alacritty >/dev/null 2>&1; then
  alacritty --title 'Welcome to i3-Omarchy' -e /opt/i3-omarchy-installer/firstboot/wizard.sh
else
  /opt/i3-omarchy-installer/firstboot/wizard.sh
fi
