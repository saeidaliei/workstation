#!/usr/bin/env bash

copy_runtime_assets() {
  mkdir -p /mnt/opt/i3-omarchy-installer
  cp -a "$PROJECT_ROOT/firstboot" /mnt/opt/i3-omarchy-installer/
  cp -a "$PROJECT_ROOT/assets" /mnt/opt/i3-omarchy-installer/
  chmod +x /mnt/opt/i3-omarchy-installer/firstboot/*.sh
}

write_target_script() {
  cat > /mnt/root/i3-target-setup.sh <<'TARGET'
#!/usr/bin/env bash
set -euo pipefail
source /root/i3-installer-vars

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i "s/^#\($LOCALE UTF-8\)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname
cat >/etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

printf 'root:%s\n' "$USER_PASSWORD" | chpasswd
if id "$USERNAME" >/dev/null 2>&1; then
  usermod -aG wheel,video,audio,storage,input "$USERNAME"
else
  useradd -m -G wheel,video,audio,storage,input -s /bin/bash "$USERNAME"
fi
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers

systemctl enable NetworkManager
systemctl enable lightdm
systemctl enable systemd-timesyncd || true
systemctl enable vboxservice 2>/dev/null || true

mkdir -p "/home/$USERNAME/.config/i3" "/home/$USERNAME/.config/picom" "/home/$USERNAME/.config/dunst" "/home/$USERNAME/.config/alacritty"
cat >"/home/$USERNAME/.config/i3/config" <<'I3'
set $mod Mod4
font pango:JetBrains Mono Nerd Font 10

# Applications
bindsym $mod+Return exec alacritty
bindsym $mod+d exec rofi -show drun
bindsym $mod+Shift+d exec rofi -show run
bindsym $mod+Shift+q kill
bindsym $mod+Shift+r reload

# Focus / movement
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

# Workspaces
set $ws1 "1:term"
set $ws2 "2:web"
set $ws3 "3:code"
set $ws4 "4:media"
set $ws5 "5:misc"
bindsym $mod+1 workspace $ws1
bindsym $mod+2 workspace $ws2
bindsym $mod+3 workspace $ws3
bindsym $mod+4 workspace $ws4
bindsym $mod+5 workspace $ws5

# Volume / brightness
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle

# Startup
exec_always --no-startup-id feh --bg-fill /opt/i3-omarchy-installer/assets/misty-mountain.png
exec --no-startup-id picom --config /home/$USERNAME/.config/picom/picom.conf
exec --no-startup-id dunst
exec --no-startup-id nm-applet
exec --no-startup-id /opt/i3-omarchy-installer/firstboot/firstboot.sh

# Minimal status bar
bar {
  status_command i3status
  position top
  tray_output primary
  font pango:JetBrains Mono Nerd Font 10
  colors {
    background #0d1117
    statusline #c9d1d9
    separator #30363d
    focused_workspace #30363d #30363d #ffffff
    active_workspace #21262d #21262d #ffffff
    inactive_workspace #0d1117 #0d1117 #8b949e
    urgent_workspace #f85149 #f85149 #ffffff
  }
}
I3

cat >"/home/$USERNAME/.config/picom/picom.conf" <<'PICOM'
backend = "glx";
vsync = true;
fading = true;
shadow = true;
shadow-radius = 12;
shadow-opacity = 0.28;
corner-radius = 10;
rounded-corners-exclude = [ "class_g = 'i3bar'" ];
opacity-rule = [ "92:class_g = 'Alacritty'" ];
PICOM

cat >"/home/$USERNAME/.config/alacritty/alacritty.toml" <<'ALACRITTY'
[window]
padding = { x = 16, y = 14 }
decorations = "full"
opacity = 0.94

[font]
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
size = 11.0

[colors.primary]
background = "#0d1117"
foreground = "#c9d1d9"

[colors.cursor]
text = "#0d1117"
cursor = "#8ab4f8"
ALACRITTY

cat > /etc/lightdm/lightdm.conf.d/50-i3.conf <<'LIGHTDM'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=i3
LIGHTDM

if [[ "$ENCRYPTION" == luks2 ]]; then
  sed -i "s|^HOOKS=.*|HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)|" /etc/mkinitcpio.conf
  mkinitcpio -P
  bootctl install
  mkdir -p /boot/loader/entries
  ROOT_UUID=$(blkid -s UUID -o value "$ROOT_RAW")
  cat >/boot/loader/loader.conf <<EOF2

default arch.conf
timeout 2
editor no
EOF2
  cat >/boot/loader/entries/arch.conf <<EOF2
title   Arch Linux
linux   /vmlinuz-linux
initrd  /$MICROCODE_FILE
initrd  /initramfs-linux.img
options rd.luks.uuid=$ROOT_UUID root=/dev/mapper/cryptroot rw quiet
EOF2
else
  bootctl install
  mkdir -p /boot/loader/entries
  cat >/boot/loader/loader.conf <<EOF2
default arch.conf
timeout 2
editor no
EOF2
  cat >/boot/loader/entries/arch.conf <<EOF2
title   Arch Linux
linux   /vmlinuz-linux
initrd  /$MICROCODE_FILE
initrd  /initramfs-linux.img
options root=PARTUUID=$ROOT_PARTUUID rw quiet
EOF2
fi

# Remove empty microcode line if no ucode package was installed.
sed -i '/initrd  \/$/d' /boot/loader/entries/arch.conf

if [[ "$CREATE_SWAPFILE" == true && ! -e /swapfile ]]; then
  if fallocate -l 2G /swapfile >/dev/null 2>&1; then
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
  else
    warn_swap=1
  fi
fi

mkdir -p /etc/sysctl.d
cat >/etc/sysctl.d/90-i3-vm.conf <<EOF2
vm.swappiness=10
EOF2

install -Dm644 /opt/i3-omarchy-installer/firstboot/welcome.desktop /etc/xdg/autostart/i3-omarchy-welcome.desktop
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config"
chmod 700 "/home/$USERNAME/.config"

rm -f /root/i3-target-setup.sh /root/i3-installer-vars
TARGET
  chmod +x /mnt/root/i3-target-setup.sh
}

configure_target() {
  mkdir -p /mnt/root
  local userpass_q=$(printf '%q' "$USER_PASSWORD")
  local luks_q=$(printf '%q' "${LUKS_PASSWORD:-}")
  local micro=''
  if grep -q GenuineIntel /proc/cpuinfo; then micro='intel-ucode.img'; elif grep -q AuthenticAMD /proc/cpuinfo; then micro='amd-ucode.img'; fi
  local rpuuid="${ROOT_PARTUUID:-$(blkid -s PARTUUID -o value "$ROOT_RAW")}"
  cat >/mnt/root/i3-installer-vars <<VARS
HOSTNAME=$(printf '%q' "$HOSTNAME")
USERNAME=$(printf '%q' "$USERNAME")
TIMEZONE=$(printf '%q' "$TIMEZONE")
KEYMAP=$(printf '%q' "$KEYMAP")
LOCALE=$(printf '%q' "$LOCALE")
ENCRYPTION=$(printf '%q' "$ENCRYPTION")
USER_PASSWORD=$userpass_q
LUKS_PASSWORD=$luks_q
ROOT_RAW=$(printf '%q' "${ROOT_RAW:-$ROOT}")
ROOT=$ROOT
ROOT_PARTUUID=$(printf '%q' "$rpuuid")
MICROCODE_FILE=$(printf '%q' "$micro")
CREATE_SWAPFILE=$(printf '%q' "$CREATE_SWAPFILE")
VARS
  write_target_script
  arch-chroot /mnt /root/i3-target-setup.sh >>"$LOG_FILE" 2>&1
}
