#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/configs/local.env}"
PRIVATE_ENV_FILE="${PRIVATE_ENV_FILE:-$ROOT_DIR/.env}"
TASK="${TASK:-}"
TASK_CONFIG_FILE=""
OVERRIDE_POLICY_DEVICE="${POLICY_DEVICE:-}"
OVERRIDE_POLICY_TYPE="${POLICY_TYPE:-}"
OVERRIDE_RECORD_RESUME="${RECORD_RESUME:-}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE"
  echo "Create it from configs/local.env.example."
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [[ -f "$PRIVATE_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PRIVATE_ENV_FILE"
fi

if [[ -n "$TASK" ]]; then
  TASK_CONFIG_FILE="${TASK_CONFIG_FILE:-$ROOT_DIR/configs/tasks/${TASK}.env}"
  if [[ ! -f "$TASK_CONFIG_FILE" ]]; then
    echo "Missing task config: $TASK_CONFIG_FILE"
    echo "Available tasks:"
    find "$ROOT_DIR/configs/tasks" -maxdepth 1 -name '*.env' -exec basename {} .env \; | sort
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$TASK_CONFIG_FILE"
fi

if [[ -n "$OVERRIDE_POLICY_DEVICE" ]]; then
  POLICY_DEVICE="$OVERRIDE_POLICY_DEVICE"
fi

if [[ -n "$OVERRIDE_POLICY_TYPE" ]]; then
  POLICY_TYPE="$OVERRIDE_POLICY_TYPE"
fi

POLICY_TYPE="${POLICY_TYPE:-act}"
POLICY_CONFIG_FILE="${POLICY_CONFIG_FILE:-$ROOT_DIR/configs/policies/${POLICY_TYPE}.env}"
if [[ ! -f "$POLICY_CONFIG_FILE" ]]; then
  echo "Missing policy config: $POLICY_CONFIG_FILE"
  echo "Available policies:"
  find "$ROOT_DIR/configs/policies" -maxdepth 1 -name '*.env' -exec basename {} .env \; | sort
  exit 1
fi
# shellcheck disable=SC1090
source "$POLICY_CONFIG_FILE"

if [[ -n "$OVERRIDE_RECORD_RESUME" ]]; then
  RECORD_RESUME="$OVERRIDE_RECORD_RESUME"
fi

HF_USER_OR_ORG="${HF_USER_OR_ORG:-}"
TASK_SLUG="${TASK_SLUG:-$TASK}"
if [[ -z "${DATASET_NAME_TEMPLATE:-}" ]]; then
  DATASET_NAME_TEMPLATE="seeed_3cam_{task}_training"
fi
if [[ -z "${POLICY_NAME_TEMPLATE:-}" ]]; then
  POLICY_NAME_TEMPLATE="{policy}_seeed_3cam_{task}"
fi
if [[ -z "${TRAIN_OUTPUT_DIR_TEMPLATE:-}" ]]; then
  TRAIN_OUTPUT_DIR_TEMPLATE="outputs/train/{policy}_seeed_3cam_{task}"
fi
if [[ -z "${JOB_NAME_TEMPLATE:-}" ]]; then
  JOB_NAME_TEMPLATE="{policy}_seeed_3cam_{task}"
fi
TASK_DESCRIPTION="${TASK_DESCRIPTION:-}"

template_value() {
  local template="$1"
  local value="${template//\{policy\}/$POLICY_TYPE}"
  value="${value//\{task\}/$TASK_SLUG}"
  printf '%s' "$value"
}

DATASET_NAME="${DATASET_NAME:-$(template_value "$DATASET_NAME_TEMPLATE")}"
POLICY_NAME="${POLICY_NAME:-$(template_value "$POLICY_NAME_TEMPLATE")}"
TRAIN_OUTPUT_DIR="${TRAIN_OUTPUT_DIR:-$(template_value "$TRAIN_OUTPUT_DIR_TEMPLATE")}"
JOB_NAME="${JOB_NAME:-$(template_value "$JOB_NAME_TEMPLATE")}"

DATASET_REPO_ID="${HF_USER_OR_ORG:-CHANGE_ME_HF_USER_OR_ORG}/${DATASET_NAME:-CHANGE_ME_DATASET_NAME}"
POLICY_REPO_ID="${HF_USER_OR_ORG:-CHANGE_ME_HF_USER_OR_ORG}/${POLICY_NAME:-CHANGE_ME_POLICY_NAME}"

is_placeholder() {
  local value="${1:-}"
  [[ -z "$value" || "$value" == CHANGE_ME* || "$value" == *CHANGE_ME* || "$value" == TODO* ]]
}

require_value() {
  local name="$1"
  local value="${!name:-}"
  if is_placeholder "$value"; then
    echo "Config value $name is not filled: $value"
    echo "Edit $CONFIG_FILE."
    exit 1
  fi
}

require_hf() {
  require_value HF_USER_OR_ORG
}

require_task_config() {
  if is_placeholder "$TASK"; then
    echo "Choose a task, for example: make record pour OR make train swirl"
    exit 1
  fi
  require_value DATASET_NAME
  require_value POLICY_NAME
  require_value POLICY_TYPE
  require_value TASK_SLUG
  require_value TASK_DESCRIPTION
  require_value TRAIN_OUTPUT_DIR
  require_value JOB_NAME
}

require_robot() {
  require_value ROBOT_TYPE
  require_value ROBOT_PORT
  require_value ROBOT_ID
}

require_teleop() {
  require_value TELEOP_TYPE
  require_value TELEOP_PORT
  require_value TELEOP_ID
}

camera_spec() {
  printf '{ wrist: {type: opencv, index_or_path: %s, width: %s, height: %s, fps: %s}, zed_left: {type: opencv, index_or_path: %s, width: %s, height: %s, fps: %s}, zed_right: {type: opencv, index_or_path: %s, width: %s, height: %s, fps: %s}}' \
    "$WRIST_CAMERA_INDEX" "$WRIST_CAMERA_WIDTH" "$WRIST_CAMERA_HEIGHT" "$WRIST_CAMERA_FPS" \
    "$ZED_LEFT_CAMERA_INDEX" "$ZED_LEFT_CAMERA_WIDTH" "$ZED_LEFT_CAMERA_HEIGHT" "$ZED_LEFT_CAMERA_FPS" \
    "$ZED_RIGHT_CAMERA_INDEX" "$ZED_RIGHT_CAMERA_WIDTH" "$ZED_RIGHT_CAMERA_HEIGHT" "$ZED_RIGHT_CAMERA_FPS"
}

print_camera_summary() {
  echo "Cameras:"
  printf '  %-10s index_or_path=%s width=%s height=%s fps=%s\n' \
    "wrist" "$WRIST_CAMERA_INDEX" "$WRIST_CAMERA_WIDTH" "$WRIST_CAMERA_HEIGHT" "$WRIST_CAMERA_FPS"
  printf '  %-10s index_or_path=%s width=%s height=%s fps=%s\n' \
    "zed_left" "$ZED_LEFT_CAMERA_INDEX" "$ZED_LEFT_CAMERA_WIDTH" "$ZED_LEFT_CAMERA_HEIGHT" "$ZED_LEFT_CAMERA_FPS"
  printf '  %-10s index_or_path=%s width=%s height=%s fps=%s\n' \
    "zed_right" "$ZED_RIGHT_CAMERA_INDEX" "$ZED_RIGHT_CAMERA_WIDTH" "$ZED_RIGHT_CAMERA_HEIGHT" "$ZED_RIGHT_CAMERA_FPS"
}

print_summary() {
  echo "Config: $CONFIG_FILE"
  if [[ -n "$TASK" ]]; then
    echo "Task:   $TASK ($TASK_CONFIG_FILE)"
    echo "Policy type: $POLICY_TYPE"
    echo "Policy config: $POLICY_CONFIG_FILE"
    echo "Dataset repo: $DATASET_REPO_ID"
    echo "Policy repo:  $POLICY_REPO_ID"
  else
    echo "Task:   none selected"
  fi
  echo "Robot:        $ROBOT_TYPE at $ROBOT_PORT id=$ROBOT_ID"
  echo "Teleop:       $TELEOP_TYPE at $TELEOP_PORT id=$TELEOP_ID"
  print_camera_summary
  echo "Training:"
  echo "  policy_type=$POLICY_TYPE"
  echo "  policy_device=$POLICY_DEVICE"
  echo "  steps=${TRAIN_STEPS:-}"
  echo "  batch_size=${TRAIN_BATCH_SIZE:-}"
  echo "  pretrained_path=${POLICY_PRETRAINED_PATH:-}"
  echo "  wandb_enable=$WANDB_ENABLE"
  echo "  policy_push_to_hub=$POLICY_PUSH_TO_HUB"
  echo "Recording:"
  echo "  num_episodes=$NUM_EPISODES"
  echo "  episode_time_s=$EPISODE_TIME_S"
  echo "  reset_time_s=$RESET_TIME_S"
  echo "  push_to_hub=$PUSH_TO_HUB"
  echo "  resume=$RECORD_RESUME"
}
