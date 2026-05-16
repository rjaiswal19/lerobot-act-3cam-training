#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_robot

cmd=(
  python "$ROOT_DIR/scripts/check_follower_motors.py"
  --type "$ROBOT_TYPE"
  --port "$ROBOT_PORT"
  --id "$ROBOT_ID"
)
append_arg_if_set cmd "--can-adapter" "${ROBOT_CAN_ADAPTER:-}"
append_arg_if_set cmd "--dm-serial-baud" "${ROBOT_DM_SERIAL_BAUD:-}"

run_command "${cmd[@]}"
