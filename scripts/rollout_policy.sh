#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config
require_robot

print_summary
setup_live_display

cmd=(
  lerobot-rollout
  --strategy.type=base
  --policy.path="$ROLLOUT_POLICY_PATH"
  --task="$TASK_DESCRIPTION"
  --duration="$ROLLOUT_DURATION_S"
  --fps="$ROLLOUT_FPS"
  --device="$POLICY_DEVICE"
  --return_to_initial_position="$ROLLOUT_RETURN_TO_INITIAL_POSITION"
  --use_torch_compile="$ROLLOUT_USE_TORCH_COMPILE"
  --interpolation_multiplier="$ROLLOUT_INTERPOLATION_MULTIPLIER"
)
append_arg_if_set cmd "--inference.type" "${ROLLOUT_INFERENCE_TYPE:-}"
if [[ "${ROLLOUT_INFERENCE_TYPE:-}" == "rtc" ]]; then
  append_arg_if_set cmd "--inference.rtc.execution_horizon" "${ROLLOUT_RTC_EXECUTION_HORIZON:-}"
  append_arg_if_set cmd "--inference.rtc.max_guidance_weight" "${ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT:-}"
  append_arg_if_set cmd "--inference.queue_threshold" "${ROLLOUT_RTC_QUEUE_THRESHOLD:-}"
fi
append_arg_if_set cmd "--rename_map" "${ROLLOUT_RENAME_MAP:-}"
add_display_args cmd
add_robot_args cmd true

if declare -p ROLLOUT_EXTRA_ARGS >/dev/null 2>&1; then
  cmd+=("${ROLLOUT_EXTRA_ARGS[@]}")
fi

run_command "${cmd[@]}"
