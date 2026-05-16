#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_robot
require_teleop

print_summary
setup_live_display

cmd=(lerobot-teleoperate)
add_robot_args cmd true
add_teleop_args cmd
add_display_args cmd

run_command "${cmd[@]}"
