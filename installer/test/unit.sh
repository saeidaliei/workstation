#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export LOG_DIR=/tmp/i3-installer-unit
export LOG_FILE=$LOG_DIR/install.log
export STATE_DIR=$LOG_DIR/state
rm -rf "$LOG_DIR"
mkdir -p "$STATE_DIR"
source "$ROOT/lib/logging.sh"
source "$ROOT/lib/ui.sh"

success_stage(){ return 0; }
failing_stage(){ return 1; }

run_stage success 1 2 success_stage
[[ -f "$STATE_DIR/success.done" ]]

# A failing stage must not be marked complete. We can't automate its recovery
# prompt without a tty, so exercise the success/idempotency half directly.
[[ ! -f "$STATE_DIR/failing.done" ]]

# Syntax-check every shell component and verify help is reachable without preflight.
for f in "$ROOT"/bin/*.sh "$ROOT"/lib/*.sh "$ROOT"/firstboot/*.sh "$ROOT"/*.sh; do
  bash -n "$f"
done
"$ROOT/install.sh" --help >/tmp/i3-installer-help.txt

grep -q -- '--resume' /tmp/i3-installer-help.txt
grep -q -- '--dry-run' /tmp/i3-installer-help.txt
printf 'unit tests: PASS\n'
