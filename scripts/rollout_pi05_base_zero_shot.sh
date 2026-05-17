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
export ROLLOUT_INFERENCE_TYPE="sync"
export ROLLOUT_FPS="${ROLLOUT_FPS:-${ZERO_SHOT_FPS:-1}}"
export ROLLOUT_DURATION_S="${ROLLOUT_DURATION_S:-${ZERO_SHOT_DURATION_S:-6}}"
export ROLLOUT_RETURN_TO_INITIAL_POSITION="${ROLLOUT_RETURN_TO_INITIAL_POSITION:-${ZERO_SHOT_RETURN_TO_INITIAL_POSITION:-true}}"
export ROLLOUT_RENAME_MAP="${ROLLOUT_RENAME_MAP:-${ZERO_SHOT_RENAME_MAP:-}}"

echo "Zero-shot Pi0.5 base rollout:"
echo "  task=$TASK"
echo "  policy=$ROLLOUT_POLICY_PATH"
echo "  inference=$ROLLOUT_INFERENCE_TYPE"
echo "  duration_s=$ROLLOUT_DURATION_S"
echo "  fps=$ROLLOUT_FPS"
echo "  rename_map=$ROLLOUT_RENAME_MAP"
echo

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

bash "$ROOT_DIR/scripts/rollout_policy.sh"
