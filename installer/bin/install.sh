#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PROJECT_ROOT
export LOG_DIR=${LOG_DIR:-/tmp/i3-installer}
export LOG_FILE=$LOG_DIR/install.log
export STATE_DIR=$LOG_DIR/state
mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck source=../lib/logging.sh
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/preflight.sh"
source "$PROJECT_ROOT/lib/disk.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/packages.sh"
source "$PROJECT_ROOT/lib/target.sh"

RESUME=0
DRY_RUN=0
DEBUG=0
CONFIG_FILE=

while (($#)); do
  case "$1" in
    --resume) RESUME=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    --debug) DEBUG=1; set -x; shift;;
    --config)
      [[ $# -ge 2 ]] || { echo '--config requires a file path.'; exit 2; }
      CONFIG_FILE=$2
      shift 2
      ;;
    --help|-h)
      cat <<HELP
Usage: $0 [--resume] [--dry-run] [--debug] [--config FILE]

  --resume   Resume completed configuration in this live session.
  --dry-run  Run discovery and validation without touching disks.
  --debug    Enable shell tracing.
  --config   Load a previously saved configuration file.
HELP
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 2;;
  esac
done

preflight
maybe_install_gum

if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  load_config "$CONFIG_FILE"
  info "Loaded configuration from $CONFIG_FILE."
  [[ "$ENCRYPTION" == luks2 ]] && ask_password 'LUKS passphrase' LUKS_PASSWORD
  ask_password "Password for user '$USERNAME'" USER_PASSWORD
elif ((RESUME)) && [[ -f "$LOG_DIR/config.env" ]]; then
  load_config "$LOG_DIR/config.env"
  info 'Loaded previous installer configuration.'
  [[ "$ENCRYPTION" == luks2 ]] && ask_password 'LUKS passphrase' LUKS_PASSWORD
  ask_password "Password for user '$USERNAME'" USER_PASSWORD
else
  # Defaults
  source "$PROJECT_ROOT/config.default"
  USER_PASSWORD=''
  LUKS_PASSWORD=''
  configuration_wizard
  ask_password "Password for user '$USERNAME'" USER_PASSWORD
  save_config
fi

if ((DRY_RUN)); then
  echo
  info "Dry run: no disk changes will be performed."
  select_disk
  info "Would install profile=$PROFILE to $DISK"
  exit 0
fi

# Final destructive confirmation with a concise summary.
cat <<SUMMARY

╔══════════════════════════════════════════════════════════════════╗
║                    FINAL INSTALL CONFIRMATION                   ║
╠══════════════════════════════════════════════════════════════════╣
║ Disk will be ERASED: $DISK
║ Hostname:             $HOSTNAME
║ User:                 $USERNAME
║ Timezone:             $TIMEZONE
║ Keyboard:             $KEYMAP
║ Encryption:           $ENCRYPTION
╚══════════════════════════════════════════════════════════════════╝
SUMMARY
confirm "ERASE $DISK and install Arch + i3?" || { warn 'Cancelled.'; exit 0; }

if [[ $ENCRYPTION == luks2 ]]; then
  [[ -n ${LUKS_PASSWORD:-} ]] || ask_password 'LUKS passphrase' LUKS_PASSWORD
fi
[[ -n ${USER_PASSWORD:-} ]] || ask_password "Password for user '$USERNAME'" USER_PASSWORD

run_stage mirror 1 5 setup_mirrors
run_stage disk 2 5 prepare_disk
restore_disk_environment
run_stage packages 3 5 install_base
run_stage target-assets 4 5 copy_runtime_assets
run_stage target-config 5 5 configure_target

# Verify installation before we let the VM reboot.
info 'Verifying installation...'
test -s /mnt/etc/fstab || { error 'fstab missing.'; exit 1; }
test -x /mnt/usr/bin/i3 || { error 'i3 executable missing.'; exit 1; }
test -x /mnt/usr/bin/lightdm || { error 'LightDM executable missing.'; exit 1; }
test -d /mnt/boot/loader/entries || { error 'Boot entries missing.'; exit 1; }
grep -qE "^$USERNAME:" /mnt/etc/passwd || { error "Target user was not created."; exit 1; }
info 'Verification passed.'

cat <<DONE

╭──────────────────────────────────────────────────────────────╮
│                    INSTALLATION COMPLETE                    │
├──────────────────────────────────────────────────────────────┤
│ Remove the Arch ISO from VirtualBox, then reboot.           │
│                                                              │
│ First login: $USERNAME                                       │
│ Bootloader:  systemd-boot                                   │
│ Desktop:     i3 + LightDM                                   │
│ Logs:        $LOG_FILE                                      │
╰──────────────────────────────────────────────────────────────╯
DONE

confirm 'Reboot now?' && { sync; umount -R /mnt; reboot; } || { info 'Leaving system mounted. Run reboot when ready.'; }
