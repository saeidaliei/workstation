#!/usr/bin/env bash

LOG_DIR=${LOG_DIR:-/tmp/i3-installer}
LOG_FILE=${LOG_FILE:-$LOG_DIR/install.log}
STATE_DIR=${STATE_DIR:-$LOG_DIR/state}
mkdir -p "$LOG_DIR" "$STATE_DIR"

exec 3>>"$LOG_FILE"

log() {
  local level=$1; shift
  printf '[%s] %-5s %s\n' "$(date '+%F %T')" "$level" "$*" | tee -a /dev/fd/3 >&2
}
info(){ log INFO "$@"; }
warn(){ log WARN "$@"; }
error(){ log ERROR "$@"; }

run() {
  info "+ $*"
  "$@" >>"$LOG_FILE" 2>&1
}

retry() {
  local attempts=$1; shift
  local n=1
  while true; do
    if "$@" >>"$LOG_FILE" 2>&1; then return 0; fi
    if (( n >= attempts )); then
      error "Command failed after $n attempt(s): $*"
      return 1
    fi
    warn "Command failed (attempt $n/$attempts). Retrying..."
    sleep $((n * 2))
    ((n++))
  done
}

stage_begin() {
  STAGE_NAME=$1
  if [[ -f "$STATE_DIR/$STAGE_NAME.done" ]]; then
    info "Skipping completed stage: $STAGE_NAME"
    return 1
  fi
  info "===== STAGE: $STAGE_NAME ====="
  return 0
}

stage_done() {
  printf '%s\n' "$(date -Is)" >"$STATE_DIR/$STAGE_NAME.done"
}

trap 'rc=$?; if ((rc)); then error "Installer failed (exit $rc). Log: $LOG_FILE"; fi' EXIT


recover_stage() {
  local stage=$1
  echo
  error "Stage '$stage' failed. The installer will NOT continue automatically."
  echo "Recent log output:"
  tail -n 40 "$LOG_FILE" || true
  echo
  echo 'Recovery options:'
  echo '  1) Retry this stage'
  echo '  2) Open a root shell for debugging'
  echo '  3) Abort installation'
  local choice
  while true; do
    read -rp 'Select [1-3]: ' choice
    case "$choice" in
      1) return 10;;
      2) /bin/bash; return 11;;
      3) return 12;;
    esac
  done
}

run_stage() {
  local stage=$1 number=$2 total=$3 fn=$4
  STAGE_NAME=$stage
  if [[ -f "$STATE_DIR/$stage.done" ]]; then
    info "[$number/$total] $stage — already complete"
    return 0
  fi

  while true; do
    printf '\n'
    progress "$(( (number-1) * 100 / total ))" "Starting $stage"
    info "[$number/$total] $stage"
    if "$fn"; then
      stage_done
      progress "$(( number * 100 / total ))" "$stage complete"
      return 0
    fi

    local recovery_rc=0
    if recover_stage "$stage"; then
      recovery_rc=0
    else
      recovery_rc=$?
    fi
    case "$recovery_rc" in
      10) warn "Retrying stage '$stage'..."; continue;;
      11) warn "Returned from recovery shell for '$stage'."; continue;;
      12) error 'Installation aborted.'; return 1;;
      *) return 1;;
    esac
  done
}
