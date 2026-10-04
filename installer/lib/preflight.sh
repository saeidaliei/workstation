#!/usr/bin/env bash

preflight() {
  info 'Running preflight checks...'
  [[ $EUID -eq 0 ]] || { error 'Run from the Arch ISO as root.'; return 1; }
  [[ $(uname -m) == x86_64 ]] || { error 'This installer currently supports x86_64 only.'; return 1; }
  command -v pacman >/dev/null || { error 'pacman is missing. This does not look like an Arch ISO.'; return 1; }
  command -v lsblk >/dev/null || { error 'lsblk is missing.'; return 1; }
  command -v sfdisk >/dev/null || { error 'sfdisk is missing.'; return 1; }
  if command -v cryptsetup >/dev/null 2>&1; then HAVE_CRYPTSETUP=1; else HAVE_CRYPTSETUP=0; fi
  for required in lsblk sfdisk sgdisk wipefs partprobe mkfs.fat mkfs.ext4 mount umount arch-chroot pacstrap genfstab; do
    command -v "$required" >/dev/null 2>&1 || { error "Required command missing: $required"; return 1; }
  done
  command -v reflector >/dev/null 2>&1 && HAVE_REFLECTOR=1 || HAVE_REFLECTOR=0
  command -v gum >/dev/null || HAVE_GUM=0

  if [[ ! -d /sys/firmware/efi/efivars ]]; then
    error 'UEFI was not detected. Enable EFI in VirtualBox. BIOS installs are intentionally disabled for reliability.'
    return 1
  fi

  local mem_mb
  mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  (( mem_mb >= 1024 )) || warn "Only ${mem_mb} MiB RAM detected; 2 GiB+ is recommended."

  if ! ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
    error 'No working network connection. Connect Ethernet/Wi-Fi in the ISO and rerun.'
    return 1
  fi

  info 'Preflight passed.'
}

maybe_install_gum() {
  command -v gum >/dev/null && return 0
  if confirm 'Install gum temporarily for the nicer installer UI?'; then
    if retry 2 pacman -Sy --needed --noconfirm gum; then
      HAVE_GUM=1
      info 'gum installed for this live session.'
    else
      warn 'Could not install gum; continuing with plain terminal UI.'
    fi
  fi
}
