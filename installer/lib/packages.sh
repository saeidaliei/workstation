#!/usr/bin/env bash

setup_mirrors() {
  info 'Selecting fast HTTPS mirrors...'
  if ! command -v reflector >/dev/null 2>&1; then
    retry 2 pacman -S --needed --noconfirm reflector >>"$LOG_FILE" 2>&1 || true
  fi
  if command -v reflector >/dev/null 2>&1; then
    local country_arg=()
    case "$MIRROR_COUNTRY" in
      auto) ;;
      *) country_arg=(--country "$MIRROR_COUNTRY") ;;
    esac
    if retry 2 reflector --protocol https --latest 15 --sort rate "${country_arg[@]}" --save /etc/pacman.d/mirrorlist; then
      info 'Mirrorlist updated.'
      return 0
    fi
  fi
  warn 'Reflector failed or is unavailable; using the ISO mirrorlist.'
}

install_base() {
  local packages=(
    base base-devel linux linux-firmware
    networkmanager sudo git curl wget openssh
    nano less man-db man-pages texinfo
    xorg-server xorg-xinit xorg-xrandr xorg-xsetroot
    i3-wm i3status i3lock dmenu rofi
    alacritty picom dunst feh
    lightdm lightdm-gtk-greeter
    pipewire pipewire-pulse wireplumber pavucontrol
    network-manager-applet
    noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
    papirus-icon-theme lxappearance
    firefox
  )
  [[ "$INSTALL_FIREFOX" == true ]] || packages=(${packages[@]//firefox/})
  if [[ "$INSTALL_VIRTUALBOX" == true ]]; then packages+=(virtualbox-guest-utils); fi
  if [[ "$ENCRYPTION" == luks2 ]]; then packages+=(cryptsetup); fi
  if grep -q GenuineIntel /proc/cpuinfo; then packages+=(intel-ucode); elif grep -q AuthenticAMD /proc/cpuinfo; then packages+=(amd-ucode); fi

  info "Installing ${#packages[@]} packages..."
  retry 3 pacstrap -K /mnt "${packages[@]}"
  genfstab -U /mnt > /mnt/etc/fstab
}
