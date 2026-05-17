#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

PROFILE_FPS="${PROFILE_FPS:-$DATASET_FPS}"
PROFILE_ITERATIONS="${PROFILE_ITERATIONS:-20}"
PROFILE_WARMUP="${PROFILE_WARMUP:-3}"
PROFILE_CAMERA_TIMEOUT_MS="${PROFILE_CAMERA_TIMEOUT_MS:-5000}"
PROFILE_DISPLAY_DATA="${PROFILE_DISPLAY_DATA:-$DISPLAY_DATA}"
PROFILE_DISPLAY_COMPRESSED_IMAGES="${PROFILE_DISPLAY_COMPRESSED_IMAGES:-${DISPLAY_COMPRESSED_IMAGES:-false}}"
PROFILE_SLEEP_TO_FPS="${PROFILE_SLEEP_TO_FPS:-true}"

if truthy "$PROFILE_DISPLAY_DATA"; then
  DISPLAY_DATA="$PROFILE_DISPLAY_DATA"
  setup_live_display
fi

cmd=(
  python "$ROOT_DIR/scripts/profile_cameras.py"
  --cameras="$(camera_spec)"
  --fps="$PROFILE_FPS"
  --iterations="$PROFILE_ITERATIONS"
  --warmup="$PROFILE_WARMUP"
  --timeout_ms="$PROFILE_CAMERA_TIMEOUT_MS"
  --display_data="$PROFILE_DISPLAY_DATA"
  --display_compressed_images="$PROFILE_DISPLAY_COMPRESSED_IMAGES"
  --sleep_to_fps="$PROFILE_SLEEP_TO_FPS"
)
append_arg_if_set cmd "--display_ip" "${DISPLAY_IP:-}"
append_arg_if_set cmd "--display_port" "${DISPLAY_PORT:-}"

echo "This profiles configured cameras only. It does not connect the follower or leader arms."
run_command "${cmd[@]}"
