#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_robot
require_teleop

PROFILE_FPS="${PROFILE_FPS:-$DATASET_FPS}"
PROFILE_ITERATIONS="${PROFILE_ITERATIONS:-20}"
PROFILE_WARMUP="${PROFILE_WARMUP:-3}"
PROFILE_SEND_ACTION="${PROFILE_SEND_ACTION:-true}"
PROFILE_INCLUDE_DATASET="${PROFILE_INCLUDE_DATASET:-true}"
PROFILE_STREAMING_ENCODING="${PROFILE_STREAMING_ENCODING:-${STREAMING_ENCODING:-false}}"
PROFILE_CAMERA_ENCODER_VCODEC="${PROFILE_CAMERA_ENCODER_VCODEC:-${CAMERA_ENCODER_VCODEC:-}}"
PROFILE_CAMERA_ENCODER_PRESET="${PROFILE_CAMERA_ENCODER_PRESET:-${CAMERA_ENCODER_PRESET:-}}"
PROFILE_IMAGE_WRITER_PROCESSES="${PROFILE_IMAGE_WRITER_PROCESSES:-0}"
PROFILE_IMAGE_WRITER_THREADS_PER_CAMERA="${PROFILE_IMAGE_WRITER_THREADS_PER_CAMERA:-4}"
PROFILE_DISPLAY_DATA="${PROFILE_DISPLAY_DATA:-$DISPLAY_DATA}"
PROFILE_DISPLAY_COMPRESSED_IMAGES="${PROFILE_DISPLAY_COMPRESSED_IMAGES:-${DISPLAY_COMPRESSED_IMAGES:-false}}"
PROFILE_ASYNC_DISPLAY="${PROFILE_ASYNC_DISPLAY:-true}"
PROFILE_SLEEP_TO_FPS="${PROFILE_SLEEP_TO_FPS:-true}"

if truthy "$PROFILE_DISPLAY_DATA"; then
  DISPLAY_DATA="$PROFILE_DISPLAY_DATA"
  setup_live_display
fi

cmd=(
  python "$ROOT_DIR/scripts/profile_record_loop.py"
  --robot_type="$ROBOT_TYPE"
  --robot_port="$ROBOT_PORT"
  --robot_id="$ROBOT_ID"
  --robot_can_adapter="${ROBOT_CAN_ADAPTER:-damiao}"
  --robot_dm_serial_baud="${ROBOT_DM_SERIAL_BAUD:-921600}"
  --teleop_type="$TELEOP_TYPE"
  --teleop_port="$TELEOP_PORT"
  --teleop_id="$TELEOP_ID"
  --teleop_baudrate="${TELEOP_BAUDRATE:-1000000}"
  --cameras="$(camera_spec)"
  --fps="$PROFILE_FPS"
  --iterations="$PROFILE_ITERATIONS"
  --warmup="$PROFILE_WARMUP"
  --send_action="$PROFILE_SEND_ACTION"
  --include_dataset="$PROFILE_INCLUDE_DATASET"
  --streaming_encoding="$PROFILE_STREAMING_ENCODING"
  --image_writer_processes="$PROFILE_IMAGE_WRITER_PROCESSES"
  --image_writer_threads_per_camera="$PROFILE_IMAGE_WRITER_THREADS_PER_CAMERA"
  --display_data="$PROFILE_DISPLAY_DATA"
  --display_compressed_images="$PROFILE_DISPLAY_COMPRESSED_IMAGES"
  --async_display="$PROFILE_ASYNC_DISPLAY"
  --sleep_to_fps="$PROFILE_SLEEP_TO_FPS"
)
append_arg_if_set cmd "--teleop_joint_directions" "${TELEOP_JOINT_DIRECTIONS:-}"
append_arg_if_set cmd "--encoder_threads" "${ENCODER_THREADS:-}"
append_arg_if_set cmd "--camera_encoder_vcodec" "$PROFILE_CAMERA_ENCODER_VCODEC"
append_arg_if_set cmd "--camera_encoder_preset" "$PROFILE_CAMERA_ENCODER_PRESET"
append_arg_if_set cmd "--display_ip" "${DISPLAY_IP:-}"
append_arg_if_set cmd "--display_port" "${DISPLAY_PORT:-}"

echo "This profiles the record loop against the real robot hardware."
echo "PROFILE_SEND_ACTION=$PROFILE_SEND_ACTION (true commands the follower like make record)."
run_command "${cmd[@]}"
