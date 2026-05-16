#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config
require_robot
require_teleop

print_summary

cmd=(lerobot-record)
add_robot_args cmd true
add_teleop_args cmd
cmd+=(
  --display_data="$DISPLAY_DATA"
  --dataset.repo_id="$DATASET_REPO_ID"
  --dataset.num_episodes="$NUM_EPISODES"
  --dataset.single_task="$TASK_DESCRIPTION"
  --dataset.episode_time_s="$EPISODE_TIME_S"
  --dataset.reset_time_s="$RESET_TIME_S"
  --dataset.streaming_encoding="$STREAMING_ENCODING"
  --dataset.encoder_threads="$ENCODER_THREADS"
  --dataset.push_to_hub="$PUSH_TO_HUB"
  --resume="$RECORD_RESUME"
)

run_command "${cmd[@]}"
