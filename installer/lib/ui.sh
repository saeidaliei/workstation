#!/usr/bin/env bash

command -v gum >/dev/null 2>&1 && HAVE_GUM=1 || HAVE_GUM=0

ui_init() {
  clear 2>/dev/null || true
  cat <<'BANNER'

   ██╗██████╗       ██████╗ ███╗   ███╗ █████╗ ██████╗  ██████╗██╗  ██╗██╗   ██╗
   ██║╚════██╗     ██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██╔════╝██║  ██║╚██╗ ██╔╝
   ██║ █████╔╝     ██║   ██║██╔████╔██║███████║██████╔╝██║     ███████║ ╚████╔╝ 
   ██║██╔═══╝      ██║   ██║██║╚██╔╝██║██╔══██║██╔══██╗██║     ██╔══██║  ╚██╔╝  
   ██║███████╗     ╚██████╔╝██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╗██║  ██║   ██║   
   ╚═╝╚══════╝      ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   

   An elegant Arch + i3 installer for fresh VMs and desktops
BANNER
  printf '\n'
}

pause(){ read -rp "Press Enter to continue..." _ || true; }

ask_text() {
  local prompt=$1 default=$2 var=$3 value
  if ((HAVE_GUM)); then
    value=$(gum input --prompt "$prompt " --value "$default")
  else
    read -rp "$prompt [$default]: " value
    value=${value:-$default}
  fi
  printf -v "$var" '%s' "$value"
}

ask_password() {
  local prompt=$1 var=$2 value confirm
  while true; do
    read -rsp "$prompt: " value; echo
    read -rsp "Repeat: " confirm; echo
    [[ -n "$value" && "$value" == "$confirm" ]] && break
    echo "Passwords do not match or are empty. Try again."
  done
  printf -v "$var" '%s' "$value"
}

choose() {
  local prompt=$1 var=$2; shift 2
  local opts=("$@") choice i=1
  if ((HAVE_GUM)); then
    choice=$(printf '%s\n' "${opts[@]}" | gum choose --header "$prompt")
  else
    echo
    echo "$prompt"
    for o in "${opts[@]}"; do printf '  %d) %s\n' "$i" "$o"; ((i++)); done
    while true; do
      read -rp 'Select: ' n
      [[ "$n" =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#opts[@]} ]] && { choice=${opts[$((n-1))]}; break; }
      echo 'Invalid selection.'
    done
  fi
  printf -v "$var" '%s' "$choice"
}

confirm() {
  local prompt=$1
  if ((HAVE_GUM)); then gum confirm "$prompt"; else read -rp "$prompt [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; fi
}

spinner(){ "$@"; }

progress() {
  local pct=$1 msg=$2 width=38 filled
  filled=$((width*pct/100))
  local bar
  printf -v bar '%*s' "$filled" ''
  bar=${bar// /#}
  local rest=$((width-filled)); printf -v rest '%*s' "$rest" ''; rest=${rest// /-}
  printf '\r[%s%s] %3d%% %s' "$bar" "$rest" "$pct" "$msg"
  if ((pct >= 100)); then printf '\n'; fi
}
