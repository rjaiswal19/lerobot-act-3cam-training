#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

echo "--- Configured camera capture ---"
cmd=(
  python "$ROOT_DIR/scripts/check_config_cameras.py"
  --cameras="$(camera_spec)"
  --output_dir="$ROOT_DIR/outputs/captured_images"
)
run_command "${cmd[@]}"
