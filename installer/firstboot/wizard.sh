#!/usr/bin/env bash
set -euo pipefail

HOME_DIR=${HOME:-/root}
CFG="$HOME_DIR/.config/i3/config"
MARKER="$HOME_DIR/.config/i3-omarchy-firstboot-done"
mkdir -p "$HOME_DIR/.config/i3"

clear
cat <<'BANNER'
╭──────────────────────────────────────────────────────────────╮
│                  Welcome to i3-Omarchy                      │
│                                                              │
│  A calm, keyboard-first Arch desktop.                       │
╰──────────────────────────────────────────────────────────────╯
BANNER

echo
printf 'Super+Enter = terminal    Super+D = apps    Super+1..5 = workspaces\n'
printf 'Super+Shift+Q = close     Super+F = fullscreen\n\n'

PS3='Choose an accent: '
select accent in 'Ice Blue' 'Sage' 'Warm Amber' 'Monochrome'; do
  case $REPLY in 1) fg='#8ab4f8'; break;; 2) fg='#8fbc8f'; break;; 3) fg='#d7ba7d'; break;; 4) fg='#c9d1d9'; break;; *) echo 'Pick 1-4.';; esac
done

read -rp 'Enable transparency? [Y/n]: ' transparency
if [[ ! "$transparency" =~ ^[Nn]$ ]]; then
  sed -i "s/^opacity = .*/opacity = 0.94;/" "$HOME_DIR/.config/picom/picom.conf" || true
else
  sed -i 's/^opacity = .*/opacity = 1.0;/' "$HOME_DIR/.config/picom/picom.conf" || true
fi

sed -i "s/^  focused_workspace .*/  focused_workspace $fg $fg #0d1117/" "$CFG"

touch "$MARKER"
clear
printf '\nSetup complete. Restart i3 with Super+Shift+R if you changed the appearance.\n\n'
read -rp 'Press Enter to close... ' _ || true
