#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_robot
require_teleop

print_summary

cmd=(lerobot-teleoperate)
add_robot_args cmd true
add_teleop_args cmd
cmd+=(--display_data="$DISPLAY_DATA")

run_command "${cmd[@]}"
