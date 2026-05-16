#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config
require_robot

print_summary

lerobot-rollout \
  --strategy.type=base \
  --policy.path="$POLICY_REPO_ID" \
  --robot.type="$ROBOT_TYPE" \
  --robot.port="$ROBOT_PORT" \
  --robot.id="$ROBOT_ID" \
  --robot.cameras="$(camera_spec)" \
  --display_data="$DISPLAY_DATA"
