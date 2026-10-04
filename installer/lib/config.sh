#!/usr/bin/env bash

save_config() {
  local file=${1:-$LOG_DIR/config.env}
  umask 077
  cat >"$file" <<CFG
HOSTNAME=$(printf '%q' "$HOSTNAME")
USERNAME=$(printf '%q' "$USERNAME")
TIMEZONE=$(printf '%q' "$TIMEZONE")
KEYMAP=$(printf '%q' "$KEYMAP")
LOCALE=$(printf '%q' "$LOCALE")
DISK=$(printf '%q' "$DISK")
ENCRYPTION=$(printf '%q' "$ENCRYPTION")
SEPARATE_HOME=$(printf '%q' "$SEPARATE_HOME")
MIRROR_COUNTRY=$(printf '%q' "$MIRROR_COUNTRY")
PROFILE=$(printf '%q' "$PROFILE")
INSTALL_FIREFOX=$(printf '%q' "$INSTALL_FIREFOX")
INSTALL_VIRTUALBOX=$(printf '%q' "$INSTALL_VIRTUALBOX")
CREATE_SWAPFILE=$(printf '%q' "$CREATE_SWAPFILE")
CFG
}

load_config() {
  local file=$1
  [[ -f $file ]] || return 1
  # shellcheck disable=SC1090
  source "$file"
}

configuration_wizard() {
  ui_init
  echo 'Welcome. We will configure the machine before touching the disk.'
  echo
  ask_text 'Hostname' "$HOSTNAME" HOSTNAME
  ask_text 'Username' "$USERNAME" USERNAME

  local detected_tz='UTC'
  detected_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
  [[ $detected_tz == 'Timezone' || -z $detected_tz ]] && detected_tz='UTC'
  choose 'Timezone' TIMEZONE "$detected_tz" 'America/Toronto' 'Europe/Tallinn' 'Europe/London' 'UTC' 'America/New_York' 'America/Los_Angeles'
  [[ $TIMEZONE == "$detected_tz" && $TIMEZONE != UTC ]] || true

  choose 'Keyboard layout' KEYMAP 'us' 'uk' 'de' 'fr' 'es' 'it' 'pt' 'se' 'no' 'fi' 'ru'
  loadkeys "$KEYMAP" >>"$LOG_FILE" 2>&1 || warn "Could not apply keyboard layout '$KEYMAP' to the live session."
  choose 'Disk encryption' ENCRYPTION 'none' 'luks2'
  if [[ $ENCRYPTION == luks2 ]]; then
    command -v cryptsetup >/dev/null || { warn 'cryptsetup not available; using unencrypted install.'; ENCRYPTION=none; }
    [[ $ENCRYPTION == luks2 ]] && ask_password 'LUKS passphrase' LUKS_PASSWORD
  fi

  choose 'Mirror strategy' MIRROR_COUNTRY 'auto' 'United States' 'Canada' 'Estonia' 'United Kingdom' 'Germany' 'Finland' 'Sweden'
  INSTALL_FIREFOX=true
  INSTALL_VIRTUALBOX=true

  echo
  echo 'Installation summary:'
  printf '  Hostname:     %s\n  Username:     %s\n  Timezone:     %s\n  Keyboard:     %s\n  Encryption:   %s\n  Mirrors:      %s\n  Profile:      %s\n' \
    "$HOSTNAME" "$USERNAME" "$TIMEZONE" "$KEYMAP" "$ENCRYPTION" "$MIRROR_COUNTRY" "$PROFILE"
  echo
  disk_inventory
  echo
  if ! confirm 'Continue to disk selection?'; then exit 0; fi
  select_disk
  save_config
}
