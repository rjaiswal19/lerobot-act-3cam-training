#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config
require_robot
require_teleop

LEROBOT_DATA_HOME="${LEROBOT_DATA_HOME:-$HOME/.cache/huggingface/lerobot}"
LOCAL_DATASET_DIR="${LOCAL_DATASET_DIR:-$LEROBOT_DATA_HOME/$DATASET_REPO_ID}"

print_summary
echo "  local_dataset_dir=$LOCAL_DATASET_DIR"
setup_live_display

cmd=(lerobot-record)
add_robot_args cmd true
add_teleop_args cmd
add_display_args cmd
cmd+=(
  --dataset.repo_id="$DATASET_REPO_ID"
  --dataset.root="$LOCAL_DATASET_DIR"
  --dataset.fps="$DATASET_FPS"
  --dataset.num_episodes="$NUM_EPISODES"
  --dataset.single_task="$TASK_DESCRIPTION"
  --dataset.episode_time_s="$EPISODE_TIME_S"
  --dataset.reset_time_s="$RESET_TIME_S"
  --dataset.streaming_encoding="$STREAMING_ENCODING"
  --dataset.encoder_threads="$ENCODER_THREADS"
  --dataset.push_to_hub="$PUSH_TO_HUB"
  --resume="$RECORD_RESUME"
  --manual_episode_start="$MANUAL_EPISODE_START"
)
append_arg_if_set cmd "--dataset.camera_encoder.vcodec" "${CAMERA_ENCODER_VCODEC:-}"
append_arg_if_set cmd "--dataset.camera_encoder.preset" "${CAMERA_ENCODER_PRESET:-}"
append_arg_if_set cmd "--dataset.camera_encoder.crf" "${CAMERA_ENCODER_CRF:-}"

run_command "${cmd[@]}"
