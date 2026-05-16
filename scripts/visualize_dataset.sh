#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config

EPISODE="${EPISODE:-0}"
VIZ_WEB_PORT="${VIZ_WEB_PORT:-9090}"
VIZ_GRPC_PORT="${VIZ_GRPC_PORT:-9876}"
VIZ_BATCH_SIZE="${VIZ_BATCH_SIZE:-32}"
VIZ_NUM_WORKERS="${VIZ_NUM_WORKERS:-0}"
VIZ_TOLERANCE_S="${VIZ_TOLERANCE_S:-1e-4}"
VIZ_DISPLAY_COMPRESSED_IMAGES="${VIZ_DISPLAY_COMPRESSED_IMAGES:-false}"
LEROBOT_DATA_HOME="${LEROBOT_DATA_HOME:-$HOME/.cache/huggingface/lerobot}"
LOCAL_DATASET_DIR="$LEROBOT_DATA_HOME/$DATASET_REPO_ID"

cmd=(lerobot-dataset-viz)
cmd+=(
  --repo-id "$DATASET_REPO_ID"
  --episode-index "$EPISODE"
  --mode distant
  --web-port "$VIZ_WEB_PORT"
  --grpc-port "$VIZ_GRPC_PORT"
  --batch-size "$VIZ_BATCH_SIZE"
  --num-workers "$VIZ_NUM_WORKERS"
  --tolerance-s "$VIZ_TOLERANCE_S"
)

if [[ -d "$LOCAL_DATASET_DIR" ]]; then
  cmd+=(--root "$LOCAL_DATASET_DIR")
fi

if [[ "$VIZ_DISPLAY_COMPRESSED_IMAGES" == "true" ]]; then
  cmd+=(--display-compressed-images)
fi

echo "Dataset visualization:"
echo "  dataset_repo=$DATASET_REPO_ID"
echo "  episode=$EPISODE"
if [[ -d "$LOCAL_DATASET_DIR" ]]; then
  echo "  local_dataset_dir=$LOCAL_DATASET_DIR"
else
  echo "  local_dataset_dir=$LOCAL_DATASET_DIR (not found; LeRobot may try the Hub/cache)"
fi

if viewer_host="$(detect_viewer_host)"; then
  echo
  echo "Open on your MacBook:"
  echo "  http://$viewer_host:$VIZ_WEB_PORT?url=rerun%2Bhttp%3A%2F%2F$viewer_host%3A$VIZ_GRPC_PORT%2Fproxy"
  echo
  echo "Native Rerun viewer:"
  echo "  rerun rerun+http://$viewer_host:$VIZ_GRPC_PORT/proxy"
else
  echo
  echo "Could not auto-detect this machine's IP."
  echo "Set it explicitly, for example: VIZ_HOST=<tailscale-ip> make viz $TASK EPISODE=$EPISODE"
fi
echo
echo "Keep this command running while viewing. Press Ctrl-C to stop."

run_command "${cmd[@]}"
