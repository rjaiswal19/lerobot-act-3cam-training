#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ZERO_SHOT_CONFIG:-$ROOT_DIR/configs/demos/zero_shot_handoff.env}"
PRIVATE_ENV_FILE="${PRIVATE_ENV_FILE:-$ROOT_DIR/.env}"

if [[ -z "${VENV_DIR:-}" && -x "$ROOT_DIR/.venv-pi05-jetson/bin/python" ]]; then
  export VENV_DIR="$ROOT_DIR/.venv-pi05-jetson"
fi

if [[ -f "$CONFIG_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_PATH"
fi

if [[ -f "$PRIVATE_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PRIVATE_ENV_FILE"
fi

TASK_NAME="${1:-${TASK:-handoff_blue}}"

case "$TASK_NAME" in
  blue) TASK_NAME="handoff_blue" ;;
  yellow) TASK_NAME="handoff_yellow" ;;
  green) TASK_NAME="handoff_green" ;;
esac

case "$TASK_NAME" in
  handoff_blue|handoff_yellow|handoff_green) ;;
  *)
    echo "Choose one of: handoff_blue, handoff_yellow, handoff_green"
    exit 1
    ;;
esac

export TASK="$TASK_NAME"
export POLICY_TYPE="pi05"
export ROLLOUT_POLICY_PATH="${ROLLOUT_POLICY_PATH:-${ZERO_SHOT_POLICY_PATH:-lerobot/pi05_base}}"
export ROLLOUT_FPS="${ROLLOUT_FPS:-${ZERO_SHOT_FPS:-1}}"
export ROLLOUT_DURATION_S="${ROLLOUT_DURATION_S:-${ZERO_SHOT_DURATION_S:-6}}"
export ROLLOUT_RETURN_TO_INITIAL_POSITION="${ROLLOUT_RETURN_TO_INITIAL_POSITION:-${ZERO_SHOT_RETURN_TO_INITIAL_POSITION:-true}}"
export ROLLOUT_RENAME_MAP="${ROLLOUT_RENAME_MAP:-${ZERO_SHOT_RENAME_MAP:-}}"

source "$ROOT_DIR/scripts/common.sh"

if [[ "${DRY_RUN:-false}" != "true" && "$ROLLOUT_POLICY_PATH" == "lerobot/pi05_base" ]]; then
  echo "Refusing physical zero-shot rollout with lerobot/pi05_base."
  echo "Reason: pi05_base emits a generic 32-dim action vector, while the B601 arm"
  echo "expects 7 absolute joint targets in degrees. The OpenPI/Pi action-space"
  echo "convention is not a verified B601 action order or unit convention."
  echo
  echo "Use a B601-finetuned Pi0.5 checkpoint or a robot-specific action transform first."
  echo "For no-motion checks, run with DRY_RUN=true."
  exit 2
fi

require_hf
require_task_config
require_robot

print_summary

SERVER_ADDRESS="${PI05_POLICY_SERVER_ADDR:-${PI05_POLICY_SERVER_HOST:-127.0.0.1}:${PI05_POLICY_SERVER_PORT:-8080}}"
ACTIONS_PER_CHUNK="${PI05_ACTIONS_PER_CHUNK:-1}"
CHUNK_SIZE_THRESHOLD="${PI05_CHUNK_SIZE_THRESHOLD:-0.5}"
CLIENT_DEVICE="${PI05_CLIENT_DEVICE:-cpu}"
RETURN_DURATION="${PI05_RETURN_TO_INITIAL_DURATION_S:-2.0}"
RUN_DURATION_STARTS_ON_FIRST_ACTION="${PI05_RUN_DURATION_STARTS_ON_FIRST_ACTION:-true}"
ACTION_INDEX_MAP="${PI05_ACTION_INDEX_MAP:-}"

echo "Zero-shot Pi0.5 async rollout:"
echo "  task=$TASK"
echo "  policy=$ROLLOUT_POLICY_PATH"
echo "  server=$SERVER_ADDRESS"
echo "  duration_s=$ROLLOUT_DURATION_S"
echo "  fps=$ROLLOUT_FPS"
echo "  actions_per_chunk=$ACTIONS_PER_CHUNK"
echo "  rename_map=$ROLLOUT_RENAME_MAP"
echo "  run_duration_starts_on_first_action=$RUN_DURATION_STARTS_ON_FIRST_ACTION"
if [[ -n "$ACTION_INDEX_MAP" ]]; then
  echo "  action_index_map=$ACTION_INDEX_MAP"
fi
echo

cmd=(
  python
  -m
  lerobot.async_inference.robot_client
  --server_address="$SERVER_ADDRESS"
  --policy_type="pi05"
  --pretrained_name_or_path="$ROLLOUT_POLICY_PATH"
  --policy_device="$POLICY_DEVICE"
  --client_device="$CLIENT_DEVICE"
  --actions_per_chunk="$ACTIONS_PER_CHUNK"
  --chunk_size_threshold="$CHUNK_SIZE_THRESHOLD"
  --fps="$ROLLOUT_FPS"
  --task="$TASK_DESCRIPTION"
  --rename_map="$ROLLOUT_RENAME_MAP"
  --run_duration_s="$ROLLOUT_DURATION_S"
  --run_duration_starts_on_first_action="$RUN_DURATION_STARTS_ON_FIRST_ACTION"
  --return_to_initial_position="$ROLLOUT_RETURN_TO_INITIAL_POSITION"
  --return_to_initial_duration_s="$RETURN_DURATION"
)
append_arg_if_set cmd "--action_index_map" "$ACTION_INDEX_MAP"
add_robot_args cmd true

run_command "${cmd[@]}"
