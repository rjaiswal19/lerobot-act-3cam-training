#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config
require_robot

print_summary

cmd=(
  lerobot-rollout
  --strategy.type=base
  --policy.path="$POLICY_REPO_ID"
  --display_data="$DISPLAY_DATA"
)
add_robot_args cmd true

run_command "${cmd[@]}"
