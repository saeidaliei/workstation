#!/usr/bin/env bash

disk_inventory() {
  echo
  printf '%-16s %-8s %-10s %-28s %s\n' DEVICE SIZE TYPE MODEL FLAGS
  while read -r name size type rm ro; do
    [[ $type == disk ]] || continue
    [[ $rm == 1 ]] && continue
    local model
    model=$(lsblk -dn -o MODEL "/dev/$name" | sed 's/[[:space:]]\+/ /g')
    printf '%-16s %-8s %-10s %-28s %s\n' "/dev/$name" "$size" "$type" "${model:0:28}" "$( ((ro)) && echo READ-ONLY || echo ready)"
  done < <(lsblk -dn -o NAME,SIZE,TYPE,RM,RO)
  echo
}

detect_installable_disks() {
  mapfile -t INSTALLABLE_DISKS < <(lsblk -dn -o NAME,TYPE,RM,RO | awk '$2=="disk" && $3==0 && $4==0 {print "/dev/"$1}')
  ((${#INSTALLABLE_DISKS[@]})) || { error 'No writable non-removable disks found.'; return 1; }
}

select_disk() {
  disk_inventory
  detect_installable_disks
  local opts=() d size model
  for d in "${INSTALLABLE_DISKS[@]}"; do
    size=$(lsblk -dn -o SIZE "$d")
    model=$(lsblk -dn -o MODEL "$d" | sed 's/[[:space:]]\+/ /g')
    opts+=("$d — $size — ${model:-Virtual disk}")
  done
  local chosen idx=0
  choose 'Select the disk to completely erase' chosen "${opts[@]}"
  echo
  echo 'Selected disk details:'
  for i in "${!opts[@]}"; do [[ "${opts[$i]}" == "$chosen" ]] && idx=$i; done
  DISK=${INSTALLABLE_DISKS[$idx]}
  echo
  lsblk -o NAME,SIZE,FSTYPE,FSVER,TYPE,MOUNTPOINTS,MODEL "$DISK" 2>/dev/null || true
}

part_path() {
  local n=$1
  if [[ $DISK == *nvme* || $DISK == *mmcblk* ]]; then echo "${DISK}p${n}"; else echo "${DISK}${n}"; fi
}

prepare_disk() {
  info "Preparing $DISK"
  swapoff -a 2>/dev/null || true
  umount -R /mnt 2>/dev/null || true
  if ! wipefs -af "$DISK" >>"$LOG_FILE" 2>&1; then
    error "Unable to wipe signatures from $DISK"; return 1
  fi
  sgdisk --zap-all "$DISK" >>"$LOG_FILE" 2>&1
  sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "$DISK" >>"$LOG_FILE" 2>&1
  sgdisk -n 2:0:0 -t 2:8300 -c 2:ROOT "$DISK" >>"$LOG_FILE" 2>&1
  partprobe "$DISK" || true
  sleep 2
  EFI=$(part_path 1); ROOT_RAW=$(part_path 2)
  ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_RAW")
  printf 'EFI=%q\nROOT_RAW=%q\nROOT_PARTUUID=%q\n' "$EFI" "$ROOT_RAW" "$ROOT_PARTUUID" >> "$STATE_DIR/disk.env"

  mkfs.fat -F32 "$EFI" >>"$LOG_FILE" 2>&1

  if [[ "$ENCRYPTION" == luks2 ]]; then
    command -v cryptsetup >/dev/null || { error 'cryptsetup unavailable.'; return 1; }
    info 'Creating LUKS2 container on root partition.'
    printf '%s' "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 "$ROOT_RAW" -q - >>"$LOG_FILE" 2>&1
    printf '%s' "$LUKS_PASSWORD" | cryptsetup open "$ROOT_RAW" cryptroot --key-file - >>"$LOG_FILE" 2>&1
    ROOT=/dev/mapper/cryptroot
  else
    ROOT="$ROOT_RAW"
  fi

  mkfs.ext4 -F "$ROOT" >>"$LOG_FILE" 2>&1
  mount "$ROOT" /mnt
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
}

restore_disk_environment() {
  if [[ -f "$STATE_DIR/disk.env" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_DIR/disk.env"
  else
    EFI=$(part_path 1)
    ROOT_RAW=$(part_path 2)
    ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_RAW")
  fi

  if [[ "$ENCRYPTION" == luks2 ]]; then
    if [[ ! -e /dev/mapper/cryptroot ]]; then
      ask_password 'LUKS passphrase' LUKS_PASSWORD
      printf '%s' "$LUKS_PASSWORD" | cryptsetup open "$ROOT_RAW" cryptroot --key-file - >>"$LOG_FILE" 2>&1
    fi
    ROOT=/dev/mapper/cryptroot
  else
    ROOT="$ROOT_RAW"
  fi

  findmnt -rn /mnt >/dev/null 2>&1 || mount "$ROOT" /mnt
  if ! findmnt -rn /mnt/boot >/dev/null 2>&1; then
    mkdir -p /mnt/boot
    mount "$EFI" /mnt/boot
  fi
}
