#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

target="${1:-}"

case "$target" in
  follower)
    require_robot
    lerobot-calibrate \
      --robot.type="$ROBOT_TYPE" \
      --robot.port="$ROBOT_PORT" \
      --robot.id="$ROBOT_ID"
    ;;
  leader)
    require_teleop
    lerobot-calibrate \
      --teleop.type="$TELEOP_TYPE" \
      --teleop.port="$TELEOP_PORT" \
      --teleop.id="$TELEOP_ID"
    ;;
  *)
    echo "Usage: bash scripts/calibrate_robot.sh follower|leader"
    exit 1
    ;;
esac
