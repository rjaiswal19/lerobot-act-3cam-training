#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

target="${1:-}"

case "$target" in
  follower)
    require_robot
    cmd=(lerobot-calibrate)
    add_robot_args cmd false
    run_command "${cmd[@]}"
    ;;
  leader)
    require_teleop
    cmd=(lerobot-calibrate)
    add_teleop_args cmd false
    run_command "${cmd[@]}"
    ;;
  *)
    echo "Usage: bash scripts/calibrate_robot.sh follower|leader"
    exit 1
    ;;
esac
