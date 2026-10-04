#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# One-shot Arch Linux + i3 installer for a fresh VirtualBox VM
# ============================================================

USERNAME="arch"
HOSTNAME="archvm"
TIMEZONE="Europe/Tallinn"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# Find the first non-removable disk.
DISK="$(lsblk -dpno NAME,TYPE,RM | awk '$2=="disk" && $3==0 {print $1; exit}')"

if [[ -z "${DISK}" ]]; then
    echo "ERROR: Could not find a suitable disk."
    exit 1
fi

# Convert /dev/sda -> /dev/sda1
# and /dev/nvme0n1 -> /dev/nvme0n1p1
part() {
    if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
        echo "${DISK}p$1"
    else
        echo "${DISK}$1"
    fi
}

if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

echo
echo "=============================================="
echo "         ARCH LINUX ONE-SHOT INSTALL"
echo "=============================================="
echo
echo "Disk:      $DISK"
echo "Boot mode: $BOOT_MODE"
echo "Hostname:  $HOSTNAME"
echo "Username:  $USERNAME"
echo
echo "WARNING: EVERYTHING ON $DISK WILL BE ERASED."
echo

read -rp 'Type WIPE to continue: ' CONFIRM
[[ "$CONFIRM" == "WIPE" ]] || {
    echo "Installation cancelled."
    exit 1
}

# Ask for user password.
while true; do
    read -rsp "Password for user '$USERNAME': " USER_PASSWORD
    echo
    read -rsp "Repeat password: " USER_PASSWORD2
    echo

    if [[ "$USER_PASSWORD" == "$USER_PASSWORD2" && -n "$USER_PASSWORD" ]]; then
        break
    fi

    echo "Passwords do not match or are empty. Try again."
done

echo
echo "==> Testing internet connection..."
ping -c 1 -W 3 archlinux.org >/dev/null

echo "==> Setting NTP..."
timedatectl set-ntp true

echo "==> Wiping disk..."
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
wipefs -af "$DISK"
sgdisk --zap-all "$DISK" 2>/dev/null || true

# ------------------------------------------------------------
# Partition disk
# ------------------------------------------------------------

echo "==> Partitioning..."

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    # 1 GiB EFI partition + rest as root
    sfdisk "$DISK" <<PARTITIONS
label: gpt
,1G,U
,,L
PARTITIONS

    EFI="$(part 1)"
    ROOT="$(part 2)"

    partprobe "$DISK"
    sleep 2

    echo "==> Formatting EFI partition..."
    mkfs.fat -F32 "$EFI"

else
    # Legacy BIOS: one bootable root partition
    sfdisk "$DISK" <<PARTITIONS
label: dos
,,L,*
PARTITIONS

    ROOT="$(part 1)"

    partprobe "$DISK"
    sleep 2
fi

echo "==> Formatting root..."
mkfs.ext4 -F "$ROOT"

# ------------------------------------------------------------
# Mount
# ------------------------------------------------------------

echo "==> Mounting filesystem..."
mount "$ROOT" /mnt

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    mkdir -p /mnt/boot
    mount "$EFI" /mnt/boot
fi

# ------------------------------------------------------------
# Determine CPU microcode
# ------------------------------------------------------------

MICROCODE=""

if grep -q "GenuineIntel" /proc/cpuinfo; then
    MICROCODE="intel-ucode"
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    MICROCODE="amd-ucode"
fi

# ------------------------------------------------------------
# Install base system
# ------------------------------------------------------------

echo "==> Installing Arch Linux..."

PACKAGES=(
    base
    base-devel
    linux
    linux-firmware
    sudo
    networkmanager
    grub
    nano
    git
    curl
    wget
)

[[ -n "$MICROCODE" ]] && PACKAGES+=("$MICROCODE")

# i3 desktop
PACKAGES+=(
    xorg-server
    xorg-xinit
    i3-wm
    i3status
    dmenu
    alacritty
    lightdm
    lightdm-gtk-greeter
    mesa
    firefox
)

# VirtualBox guest support
PACKAGES+=(
    virtualbox-guest-utils
)

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    PACKAGES+=(efibootmgr)
fi

pacstrap -K /mnt "${PACKAGES[@]}"

# ------------------------------------------------------------
# fstab
# ------------------------------------------------------------

echo "==> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ------------------------------------------------------------
# Configure installed system
# ------------------------------------------------------------

echo "==> Configuring system..."

cat > /mnt/root/configure.sh <<CONFIG
#!/usr/bin/env bash
set -euo pipefail

USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
BOOT_MODE="$BOOT_MODE"
USER_PASSWORD='$USER_PASSWORD'

# Timezone
ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
hwclock --systohc

# Locale
sed -i "s/^#\${LOCALE} UTF-8/\${LOCALE} UTF-8/" /etc/locale.gen
locale-gen

echo "LANG=\$LOCALE" > /etc/locale.conf
echo "KEYMAP=\$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "\$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
HOSTS

# Root password
echo "root:\$USER_PASSWORD" | chpasswd

# Create normal user
useradd -m -G wheel -s /bin/bash "\$USERNAME"
echo "\$USERNAME:\$USER_PASSWORD" | chpasswd

# Enable sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Network
systemctl enable NetworkManager

# VirtualBox guest services
systemctl enable vboxservice

# ------------------------------------------------------------
# Basic i3 configuration
# ------------------------------------------------------------

mkdir -p "/home/\$USERNAME/.config/i3"

cat > "/home/\$USERNAME/.config/i3/config" <<'I3CONFIG'
# Minimal i3 configuration

set \$mod Mod4

font pango:JetBrains Mono 10

# Terminal
bindsym \$mod+Return exec alacritty

# Application launcher
bindsym \$mod+d exec dmenu_run

# Close focused window
bindsym \$mod+Shift+q kill

# Reload i3
bindsym \$mod+Shift+r reload

# Restart i3 in place
bindsym \$mod+Shift+c restart

# Focus
bindsym \$mod+h focus left
bindsym \$mod+j focus down
bindsym \$mod+k focus up
bindsym \$mod+l focus right

# Move
bindsym \$mod+Shift+h move left
bindsym \$mod+Shift+j move down
bindsym \$mod+Shift+k move up
bindsym \$mod+Shift+l move right

# Workspaces
set \$ws1 "1"
set \$ws2 "2"
set \$ws3 "3"
set \$ws4 "4"
set \$ws5 "5"

bindsym \$mod+1 workspace \$ws1
bindsym \$mod+2 workspace \$ws2
bindsym \$mod+3 workspace \$ws3
bindsym \$mod+4 workspace \$ws4
bindsym \$mod+5 workspace \$ws5

# Move focused container
bindsym \$mod+Shift+1 move container to workspace \$ws1
bindsym \$mod+Shift+2 move container to workspace \$ws2
bindsym \$mod+Shift+3 move container to workspace \$ws3
bindsym \$mod+Shift+4 move container to workspace \$ws4
bindsym \$mod+Shift+5 move container to workspace \$ws5

# Split orientation
bindsym \$mod+b split h
bindsym \$mod+v split v

# Fullscreen
bindsym \$mod+f fullscreen toggle

# Floating toggle
bindsym \$mod+Shift+space floating toggle

# Status bar
bar {
    status_command i3status
}
I3CONFIG

chown -R "\$USERNAME:\$USERNAME" "/home/\$USERNAME/.config"

# ------------------------------------------------------------
# LightDM -> i3
# ------------------------------------------------------------

mkdir -p /etc/lightdm/lightdm.conf.d

cat > /etc/lightdm/lightdm.conf.d/50-i3.conf <<'LIGHTDM'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=i3
LIGHTDM

systemctl enable lightdm

# ------------------------------------------------------------
# Swap
# ------------------------------------------------------------

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# ------------------------------------------------------------
# Bootloader
# ------------------------------------------------------------

if [[ "\$BOOT_MODE" == "UEFI" ]]; then

    echo "==> Installing GRUB for UEFI..."

    grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot \
        --bootloader-id=GRUB \
        --recheck

else

    echo "==> Installing GRUB for BIOS..."

    grub-install \
        --target=i386-pc \
        --recheck \
        /dev/$(basename "\$(findmnt -no SOURCE /)") || true

fi

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Finish
# ------------------------------------------------------------

rm -f /root/configure.sh

echo
echo "=============================================="
echo "       ARCH INSTALLATION COMPLETE"
echo "=============================================="
echo
echo "User:     \$USERNAME"
echo "Hostname: \$HOSTNAME"
echo "Boot:     \$BOOT_MODE"
echo
CONFIG

chmod +x /mnt/root/configure.sh

# ------------------------------------------------------------
# Run configuration inside installed system
# ------------------------------------------------------------

arch-chroot /mnt /root/configure.sh

# Remove temporary file
rm -f /mnt/root/configure.sh

# ------------------------------------------------------------
# Unmount
# ------------------------------------------------------------

echo
echo "==> Unmounting..."
umount -R /mnt

echo
echo "=============================================="
echo "          INSTALLATION FINISHED!"
echo "=============================================="
echo
echo "Remove the Arch ISO from VirtualBox."
echo "Then reboot:"
echo
echo "    reboot"
echo
echo "You should boot directly into LightDM and i3."
echo