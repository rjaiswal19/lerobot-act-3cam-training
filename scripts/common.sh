#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/configs/local.env}"
PRIVATE_ENV_FILE="${PRIVATE_ENV_FILE:-$ROOT_DIR/.env}"
TASK="${TASK:-}"
TASK_CONFIG_FILE=""

VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
if [[ -d "$VENV_DIR/bin" ]]; then
  PATH="$VENV_DIR/bin:$PATH"
  export PATH

  PYTHON_SITE_PACKAGES="$("$VENV_DIR/bin/python" -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || true)"
  if [[ -n "$PYTHON_SITE_PACKAGES" ]]; then
    for CUDA_LIB_DIR in \
      "$PYTHON_SITE_PACKAGES/nvidia/cu12/lib" \
      "$PYTHON_SITE_PACKAGES/nvidia/cusparselt/lib" \
      "$PYTHON_SITE_PACKAGES/nvidia/cuda_nvrtc/lib"; do
      if [[ -d "$CUDA_LIB_DIR" ]]; then
        LD_LIBRARY_PATH="$CUDA_LIB_DIR:${LD_LIBRARY_PATH:-}"
      fi
    done
    CUDA_SYSTEM_LIB_DIR="${CUDA_HOME:-${CUDA_PATH:-/usr/local/cuda}}/targets/$(uname -m)-linux/lib"
    if [[ -d "$CUDA_SYSTEM_LIB_DIR" ]]; then
      LD_LIBRARY_PATH="$CUDA_SYSTEM_LIB_DIR:${LD_LIBRARY_PATH:-}"
    fi
    export LD_LIBRARY_PATH
  fi
fi
OVERRIDE_POLICY_DEVICE="${POLICY_DEVICE:-}"
OVERRIDE_POLICY_TYPE="${POLICY_TYPE:-}"
OVERRIDE_RECORD_RESUME="${RECORD_RESUME:-}"
OVERRIDE_PEFT_METHOD_TYPE="${PEFT_METHOD_TYPE:-}"
OVERRIDE_PEFT_R="${PEFT_R:-}"
OVERRIDE_DATASET_FPS="${DATASET_FPS:-}"
OVERRIDE_NUM_EPISODES="${NUM_EPISODES:-}"
OVERRIDE_EPISODE_TIME_S="${EPISODE_TIME_S:-}"
OVERRIDE_RESET_TIME_S="${RESET_TIME_S:-}"
OVERRIDE_MANUAL_EPISODE_START="${MANUAL_EPISODE_START:-}"
OVERRIDE_PUSH_TO_HUB="${PUSH_TO_HUB:-}"
OVERRIDE_DISPLAY_DATA="${DISPLAY_DATA:-}"
OVERRIDE_DISPLAY_IP="${DISPLAY_IP:-}"
OVERRIDE_DISPLAY_PORT="${DISPLAY_PORT:-}"
OVERRIDE_DISPLAY_COMPRESSED_IMAGES="${DISPLAY_COMPRESSED_IMAGES:-}"
OVERRIDE_RERUN_LIVE_VIEW="${RERUN_LIVE_VIEW:-}"
OVERRIDE_STREAMING_ENCODING="${STREAMING_ENCODING:-}"
OVERRIDE_ENCODER_THREADS="${ENCODER_THREADS:-}"
OVERRIDE_CAMERA_ENCODER_VCODEC="${CAMERA_ENCODER_VCODEC:-}"
OVERRIDE_CAMERA_ENCODER_PRESET="${CAMERA_ENCODER_PRESET:-}"
OVERRIDE_CAMERA_ENCODER_CRF="${CAMERA_ENCODER_CRF:-}"
OVERRIDE_ROLLOUT_POLICY_PATH="${ROLLOUT_POLICY_PATH:-}"
OVERRIDE_ROLLOUT_FPS="${ROLLOUT_FPS:-}"
OVERRIDE_ROLLOUT_DURATION_S="${ROLLOUT_DURATION_S:-}"
OVERRIDE_ROLLOUT_INFERENCE_TYPE="${ROLLOUT_INFERENCE_TYPE:-}"
OVERRIDE_ROLLOUT_RTC_EXECUTION_HORIZON="${ROLLOUT_RTC_EXECUTION_HORIZON:-}"
OVERRIDE_ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT="${ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT:-}"
OVERRIDE_ROLLOUT_RTC_QUEUE_THRESHOLD="${ROLLOUT_RTC_QUEUE_THRESHOLD:-}"
OVERRIDE_ROLLOUT_RETURN_TO_INITIAL_POSITION="${ROLLOUT_RETURN_TO_INITIAL_POSITION:-}"
OVERRIDE_ROLLOUT_USE_TORCH_COMPILE="${ROLLOUT_USE_TORCH_COMPILE:-}"
OVERRIDE_ROLLOUT_INTERPOLATION_MULTIPLIER="${ROLLOUT_INTERPOLATION_MULTIPLIER:-}"
OVERRIDE_ROLLOUT_RENAME_MAP="${ROLLOUT_RENAME_MAP:-}"
OVERRIDE_TASK_DESCRIPTION="${TEXT:-${TASK_TEXT:-${TASK_PROMPT:-${PROMPT:-${TASK_DESCRIPTION:-}}}}}"
RERUN_SERVER_PID=""

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

if [[ -n "$OVERRIDE_PEFT_METHOD_TYPE" ]]; then
  PEFT_METHOD_TYPE="$OVERRIDE_PEFT_METHOD_TYPE"
fi

if [[ -n "$OVERRIDE_PEFT_R" ]]; then
  PEFT_R="$OVERRIDE_PEFT_R"
fi

if [[ -n "$OVERRIDE_TASK_DESCRIPTION" ]]; then
  TASK_DESCRIPTION="$OVERRIDE_TASK_DESCRIPTION"
fi

if [[ -n "$OVERRIDE_DATASET_FPS" ]]; then
  DATASET_FPS="$OVERRIDE_DATASET_FPS"
fi

if [[ -n "$OVERRIDE_NUM_EPISODES" ]]; then
  NUM_EPISODES="$OVERRIDE_NUM_EPISODES"
fi

if [[ -n "$OVERRIDE_EPISODE_TIME_S" ]]; then
  EPISODE_TIME_S="$OVERRIDE_EPISODE_TIME_S"
fi

if [[ -n "$OVERRIDE_RESET_TIME_S" ]]; then
  RESET_TIME_S="$OVERRIDE_RESET_TIME_S"
fi

if [[ -n "$OVERRIDE_MANUAL_EPISODE_START" ]]; then
  MANUAL_EPISODE_START="$OVERRIDE_MANUAL_EPISODE_START"
fi

if [[ -n "$OVERRIDE_PUSH_TO_HUB" ]]; then
  PUSH_TO_HUB="$OVERRIDE_PUSH_TO_HUB"
fi

if [[ -n "$OVERRIDE_DISPLAY_DATA" ]]; then
  DISPLAY_DATA="$OVERRIDE_DISPLAY_DATA"
fi

if [[ -n "$OVERRIDE_DISPLAY_IP" ]]; then
  DISPLAY_IP="$OVERRIDE_DISPLAY_IP"
fi

if [[ -n "$OVERRIDE_DISPLAY_PORT" ]]; then
  DISPLAY_PORT="$OVERRIDE_DISPLAY_PORT"
fi

if [[ -n "$OVERRIDE_DISPLAY_COMPRESSED_IMAGES" ]]; then
  DISPLAY_COMPRESSED_IMAGES="$OVERRIDE_DISPLAY_COMPRESSED_IMAGES"
fi

if [[ -n "$OVERRIDE_RERUN_LIVE_VIEW" ]]; then
  RERUN_LIVE_VIEW="$OVERRIDE_RERUN_LIVE_VIEW"
fi

if [[ -n "$OVERRIDE_STREAMING_ENCODING" ]]; then
  STREAMING_ENCODING="$OVERRIDE_STREAMING_ENCODING"
fi

if [[ -n "$OVERRIDE_ENCODER_THREADS" ]]; then
  ENCODER_THREADS="$OVERRIDE_ENCODER_THREADS"
fi

if [[ -n "$OVERRIDE_CAMERA_ENCODER_VCODEC" ]]; then
  CAMERA_ENCODER_VCODEC="$OVERRIDE_CAMERA_ENCODER_VCODEC"
fi

if [[ -n "$OVERRIDE_CAMERA_ENCODER_PRESET" ]]; then
  CAMERA_ENCODER_PRESET="$OVERRIDE_CAMERA_ENCODER_PRESET"
fi

if [[ -n "$OVERRIDE_CAMERA_ENCODER_CRF" ]]; then
  CAMERA_ENCODER_CRF="$OVERRIDE_CAMERA_ENCODER_CRF"
fi

if [[ -n "$OVERRIDE_ROLLOUT_POLICY_PATH" ]]; then
  ROLLOUT_POLICY_PATH="$OVERRIDE_ROLLOUT_POLICY_PATH"
fi

if [[ -n "$OVERRIDE_ROLLOUT_FPS" ]]; then
  ROLLOUT_FPS="$OVERRIDE_ROLLOUT_FPS"
fi

if [[ -n "$OVERRIDE_ROLLOUT_DURATION_S" ]]; then
  ROLLOUT_DURATION_S="$OVERRIDE_ROLLOUT_DURATION_S"
fi

if [[ -n "$OVERRIDE_ROLLOUT_INFERENCE_TYPE" ]]; then
  ROLLOUT_INFERENCE_TYPE="$OVERRIDE_ROLLOUT_INFERENCE_TYPE"
fi

if [[ -n "$OVERRIDE_ROLLOUT_RTC_EXECUTION_HORIZON" ]]; then
  ROLLOUT_RTC_EXECUTION_HORIZON="$OVERRIDE_ROLLOUT_RTC_EXECUTION_HORIZON"
fi

if [[ -n "$OVERRIDE_ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT" ]]; then
  ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT="$OVERRIDE_ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT"
fi

if [[ -n "$OVERRIDE_ROLLOUT_RTC_QUEUE_THRESHOLD" ]]; then
  ROLLOUT_RTC_QUEUE_THRESHOLD="$OVERRIDE_ROLLOUT_RTC_QUEUE_THRESHOLD"
fi

if [[ -n "$OVERRIDE_ROLLOUT_RETURN_TO_INITIAL_POSITION" ]]; then
  ROLLOUT_RETURN_TO_INITIAL_POSITION="$OVERRIDE_ROLLOUT_RETURN_TO_INITIAL_POSITION"
fi

if [[ -n "$OVERRIDE_ROLLOUT_USE_TORCH_COMPILE" ]]; then
  ROLLOUT_USE_TORCH_COMPILE="$OVERRIDE_ROLLOUT_USE_TORCH_COMPILE"
fi

if [[ -n "$OVERRIDE_ROLLOUT_INTERPOLATION_MULTIPLIER" ]]; then
  ROLLOUT_INTERPOLATION_MULTIPLIER="$OVERRIDE_ROLLOUT_INTERPOLATION_MULTIPLIER"
fi

if [[ -n "$OVERRIDE_ROLLOUT_RENAME_MAP" ]]; then
  ROLLOUT_RENAME_MAP="$OVERRIDE_ROLLOUT_RENAME_MAP"
fi

DISPLAY_DATA="${DISPLAY_DATA:-false}"
DISPLAY_IP="${DISPLAY_IP:-}"
DISPLAY_PORT="${DISPLAY_PORT:-}"
DISPLAY_COMPRESSED_IMAGES="${DISPLAY_COMPRESSED_IMAGES:-}"
RERUN_LIVE_VIEW="${RERUN_LIVE_VIEW:-true}"
RERUN_WEB_PORT="${RERUN_WEB_PORT:-${VIZ_WEB_PORT:-9090}}"
RERUN_GRPC_PORT="${RERUN_GRPC_PORT:-${VIZ_GRPC_PORT:-9876}}"
RERUN_SERVER_MEMORY_LIMIT="${RERUN_SERVER_MEMORY_LIMIT:-25%}"
DATASET_FPS="${DATASET_FPS:-30}"
NUM_EPISODES="${NUM_EPISODES:-50}"
EPISODE_TIME_S="${EPISODE_TIME_S:-60}"
RESET_TIME_S="${RESET_TIME_S:-20}"
MANUAL_EPISODE_START="${MANUAL_EPISODE_START:-false}"
STREAMING_ENCODING="${STREAMING_ENCODING:-false}"
ENCODER_THREADS="${ENCODER_THREADS:-}"
CAMERA_ENCODER_VCODEC="${CAMERA_ENCODER_VCODEC:-}"
CAMERA_ENCODER_PRESET="${CAMERA_ENCODER_PRESET:-}"
CAMERA_ENCODER_CRF="${CAMERA_ENCODER_CRF:-}"
ROLLOUT_FPS="${ROLLOUT_FPS:-$DATASET_FPS}"
ROLLOUT_DURATION_S="${ROLLOUT_DURATION_S:-${EPISODE_TIME_S:-60}}"
ROLLOUT_INFERENCE_TYPE="${ROLLOUT_INFERENCE_TYPE:-sync}"
ROLLOUT_RETURN_TO_INITIAL_POSITION="${ROLLOUT_RETURN_TO_INITIAL_POSITION:-true}"
ROLLOUT_USE_TORCH_COMPILE="${ROLLOUT_USE_TORCH_COMPILE:-false}"
ROLLOUT_INTERPOLATION_MULTIPLIER="${ROLLOUT_INTERPOLATION_MULTIPLIER:-1}"

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
ROLLOUT_POLICY_PATH="${ROLLOUT_POLICY_PATH:-$POLICY_REPO_ID}"

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

camera_value() {
  local prefix="$1"
  local suffix="$2"
  local default="${3:-}"
  local name="${prefix}_CAMERA_${suffix}"
  printf '%s' "${!name:-$default}"
}

append_camera_field() {
  local -n spec_ref="$1"
  local name="$2"
  local value="${3:-}"
  if [[ -n "$value" ]]; then
    spec_ref+=", $name: $value"
  fi
}

camera_spec_entry() {
  local label="$1"
  local prefix="$2"
  local type
  type="$(camera_value "$prefix" TYPE opencv)"

  local width height fps spec
  width="$(camera_value "$prefix" WIDTH "${CAMERA_WIDTH:-}")"
  height="$(camera_value "$prefix" HEIGHT "${CAMERA_HEIGHT:-}")"
  fps="$(camera_value "$prefix" FPS "${CAMERA_FPS:-}")"
  spec="$label: {type: $type"

  case "$type" in
    opencv)
      append_camera_field spec index_or_path "$(camera_value "$prefix" INDEX)"
      append_camera_field spec width "$width"
      append_camera_field spec height "$height"
      append_camera_field spec fps "$fps"
      append_camera_field spec fourcc "$(camera_value "$prefix" FOURCC)"
      ;;
    zed_sdk)
      append_camera_field spec serial_number "${ZED_CAMERA_SERIAL_NUMBER:-}"
      append_camera_field spec camera_id "${ZED_CAMERA_ID:-}"
      append_camera_field spec side "$(camera_value "$prefix" SIDE)"
      append_camera_field spec resolution "${ZED_CAMERA_RESOLUTION:-HD1200}"
      append_camera_field spec depth_mode "${ZED_CAMERA_DEPTH_MODE:-NONE}"
      append_camera_field spec width "$width"
      append_camera_field spec height "$height"
      append_camera_field spec fps "$fps"
      append_camera_field spec color_mode "${ZED_CAMERA_COLOR_MODE:-rgb}"
      append_camera_field spec timeout_ms "${ZED_CAMERA_TIMEOUT_MS:-2000}"
      append_camera_field spec warmup_s "${ZED_CAMERA_WARMUP_S:-0.5}"
      ;;
    *)
      echo "Unsupported camera type '$type' for $label." >&2
      exit 1
      ;;
  esac

  printf '%s}' "$spec"
}

camera_spec() {
  printf '{ %s, %s, %s}' \
    "$(camera_spec_entry wrist WRIST)" \
    "$(camera_spec_entry zed_left ZED_LEFT)" \
    "$(camera_spec_entry zed_right ZED_RIGHT)"
}

append_arg_if_set() {
  local -n cmd_ref="$1"
  local flag="$2"
  local value="${3:-}"
  if [[ -n "$value" ]]; then
    cmd_ref+=("$flag=$value")
  fi
}

add_robot_args() {
  local -n cmd_ref="$1"
  local include_cameras="${2:-true}"

  cmd_ref+=(
    --robot.type="$ROBOT_TYPE"
    --robot.port="$ROBOT_PORT"
    --robot.id="$ROBOT_ID"
  )
  append_arg_if_set "$1" "--robot.can_adapter" "${ROBOT_CAN_ADAPTER:-}"
  append_arg_if_set "$1" "--robot.dm_serial_baud" "${ROBOT_DM_SERIAL_BAUD:-}"

  if [[ "$include_cameras" == "true" ]]; then
    cmd_ref+=(--robot.cameras="$(camera_spec)")
  fi
}

add_teleop_args() {
  local -n cmd_ref="$1"
  local include_optional="${2:-true}"

  cmd_ref+=(
    --teleop.type="$TELEOP_TYPE"
    --teleop.port="$TELEOP_PORT"
    --teleop.id="$TELEOP_ID"
  )
  if [[ "$include_optional" == "true" ]]; then
    append_arg_if_set "$1" "--teleop.can_adapter" "${TELEOP_CAN_ADAPTER:-}"
    append_arg_if_set "$1" "--teleop.joint_directions" "${TELEOP_JOINT_DIRECTIONS:-}"
    append_arg_if_set "$1" "--teleop.baudrate" "${TELEOP_BAUDRATE:-}"
  fi
}

truthy() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

detect_viewer_host() {
  if [[ -n "${VIEWER_HOST:-}" ]]; then
    printf '%s' "$VIEWER_HOST"
    return 0
  fi
  if [[ -n "${RERUN_HOST:-}" ]]; then
    printf '%s' "$RERUN_HOST"
    return 0
  fi
  if [[ -n "${VIZ_HOST:-}" ]]; then
    printf '%s' "$VIZ_HOST"
    return 0
  fi

  if command -v tailscale >/dev/null 2>&1; then
    local tailscale_ip
    tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
    if [[ -n "$tailscale_ip" ]]; then
      printf '%s' "$tailscale_ip"
      return 0
    fi
  fi

  local host_ip
  host_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  if [[ -n "$host_ip" ]]; then
    printf '%s' "$host_ip"
    return 0
  fi

  return 1
}

tcp_port_open() {
  local port="$1"
  timeout 1 bash -c ":</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1
}

print_rerun_live_links() {
  local web_port="$1"
  local grpc_port="$2"
  local viewer_host

  if viewer_host="$(detect_viewer_host)"; then
    echo
    echo "Live Rerun stream:"
    echo "  Open on your MacBook: http://$viewer_host:$web_port?url=rerun%2Bhttp%3A%2F%2F$viewer_host%3A$grpc_port%2Fproxy"
    echo "  Native Rerun viewer: rerun rerun+http://$viewer_host:$grpc_port/proxy"
  else
    echo
    echo "Live Rerun stream is enabled, but this machine's IP could not be auto-detected."
    echo "Set it explicitly, for example: RERUN_HOST=<tailscale-ip> make record $TASK"
  fi
}

stop_rerun_live_server() {
  if [[ -n "${RERUN_SERVER_PID:-}" ]] && kill -0 "$RERUN_SERVER_PID" >/dev/null 2>&1; then
    kill "$RERUN_SERVER_PID" >/dev/null 2>&1 || true
  fi
}

setup_live_display() {
  if ! truthy "$DISPLAY_DATA"; then
    return 0
  fi

  if [[ -n "$DISPLAY_IP" && -n "$DISPLAY_PORT" ]]; then
    print_rerun_live_links "${RERUN_WEB_PORT:-9090}" "$DISPLAY_PORT"
    return 0
  fi

  if ! truthy "$RERUN_LIVE_VIEW"; then
    return 0
  fi

  if ! command -v rerun >/dev/null 2>&1; then
    echo "DISPLAY_DATA=true, but rerun is not installed."
    echo "Set DISPLAY_DATA=false or install LeRobot visualization dependencies."
    exit 1
  fi

  DISPLAY_IP="127.0.0.1"
  DISPLAY_PORT="$RERUN_GRPC_PORT"
  export DISPLAY_IP DISPLAY_PORT

  print_rerun_live_links "$RERUN_WEB_PORT" "$RERUN_GRPC_PORT"

  if tcp_port_open "$RERUN_WEB_PORT" || tcp_port_open "$RERUN_GRPC_PORT"; then
    echo "Using existing Rerun server on web port $RERUN_WEB_PORT / gRPC port $RERUN_GRPC_PORT."
    return 0
  fi

  local log_file="/tmp/lerobot-rerun-live-${RERUN_WEB_PORT}-${RERUN_GRPC_PORT}.log"
  local cmd=(
    rerun
    --serve-web
    --bind 0.0.0.0
    --port "$RERUN_GRPC_PORT"
    --web-viewer-port "$RERUN_WEB_PORT"
    --server-memory-limit "$RERUN_SERVER_MEMORY_LIMIT"
  )

  print_command "${cmd[@]}"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN=true, not starting Rerun server."
    return 0
  fi

  "${cmd[@]}" >"$log_file" 2>&1 &
  RERUN_SERVER_PID="$!"
  trap stop_rerun_live_server EXIT
  sleep 2

  if ! kill -0 "$RERUN_SERVER_PID" >/dev/null 2>&1; then
    echo "Rerun live server failed to start. Log:"
    tail -50 "$log_file" || true
    exit 1
  fi
}

add_display_args() {
  local -n cmd_ref="$1"
  cmd_ref+=(--display_data="$DISPLAY_DATA")
  append_arg_if_set "$1" "--display_ip" "${DISPLAY_IP:-}"
  append_arg_if_set "$1" "--display_port" "${DISPLAY_PORT:-}"
  append_arg_if_set "$1" "--display_compressed_images" "${DISPLAY_COMPRESSED_IMAGES:-}"
}

print_command() {
  printf 'Command:'
  printf ' %q' "$@"
  printf '\n'
}

run_command() {
  print_command "$@"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN=true, not executing command."
    return 0
  fi
  "$@"
}

print_camera_summary() {
  echo "Cameras:"
  print_camera_line "wrist" WRIST
  print_camera_line "zed_left" ZED_LEFT
  print_camera_line "zed_right" ZED_RIGHT
}

print_camera_line() {
  local label="$1"
  local prefix="$2"
  local type width height fps
  type="$(camera_value "$prefix" TYPE opencv)"
  width="$(camera_value "$prefix" WIDTH "${CAMERA_WIDTH:-}")"
  height="$(camera_value "$prefix" HEIGHT "${CAMERA_HEIGHT:-}")"
  fps="$(camera_value "$prefix" FPS "${CAMERA_FPS:-}")"

  if [[ "$type" == "opencv" ]]; then
    printf '  %-10s type=%s index_or_path=%s width=%s height=%s fps=%s\n' \
      "$label" "$type" "$(camera_value "$prefix" INDEX)" "$width" "$height" "$fps"
  elif [[ "$type" == "zed_sdk" ]]; then
    printf '  %-10s type=%s side=%s serial_number=%s width=%s height=%s fps=%s\n' \
      "$label" "$type" "$(camera_value "$prefix" SIDE)" "${ZED_CAMERA_SERIAL_NUMBER:-default}" "$width" "$height" "$fps"
  else
    printf '  %-10s type=%s width=%s height=%s fps=%s\n' "$label" "$type" "$width" "$height" "$fps"
  fi
}

print_summary() {
  echo "Config: $CONFIG_FILE"
  if [[ -n "$TASK" ]]; then
    echo "Task:   $TASK ($TASK_CONFIG_FILE)"
    echo "Task text: $TASK_DESCRIPTION"
    echo "Policy type: $POLICY_TYPE"
    echo "Policy config: $POLICY_CONFIG_FILE"
    echo "Dataset repo: $DATASET_REPO_ID"
    echo "Policy repo:  $POLICY_REPO_ID"
  else
    echo "Task:   none selected"
  fi
  echo "Robot:        $ROBOT_TYPE at $ROBOT_PORT id=$ROBOT_ID"
  if [[ -n "${ROBOT_CAN_ADAPTER:-}" ]]; then
    echo "  can_adapter=$ROBOT_CAN_ADAPTER"
  fi
  if [[ -n "${ROBOT_DM_SERIAL_BAUD:-}" ]]; then
    echo "  dm_serial_baud=$ROBOT_DM_SERIAL_BAUD"
  fi
  echo "Teleop:       $TELEOP_TYPE at $TELEOP_PORT id=$TELEOP_ID"
  if [[ -n "${TELEOP_CAN_ADAPTER:-}" ]]; then
    echo "  can_adapter=$TELEOP_CAN_ADAPTER"
  fi
  if [[ -n "${TELEOP_JOINT_DIRECTIONS:-}" ]]; then
    echo "  joint_directions=$TELEOP_JOINT_DIRECTIONS"
  fi
  print_camera_summary
  echo "Training:"
  echo "  policy_type=$POLICY_TYPE"
  echo "  policy_device=$POLICY_DEVICE"
  echo "  steps=${TRAIN_STEPS:-}"
  echo "  batch_size=${TRAIN_BATCH_SIZE:-}"
  echo "  pretrained_path=${POLICY_PRETRAINED_PATH:-}"
  echo "  chunk_size=${POLICY_CHUNK_SIZE:-}"
  echo "  n_action_steps=${POLICY_N_ACTION_STEPS:-}"
  echo "  n_obs_steps=${POLICY_N_OBS_STEPS:-}"
  echo "  temporal_ensemble_coeff=${POLICY_TEMPORAL_ENSEMBLE_COEFF:-}"
  echo "  peft_method=${PEFT_METHOD_TYPE:-}"
  echo "  peft_r=${PEFT_R:-}"
  echo "  wandb_enable=$WANDB_ENABLE"
  echo "  policy_push_to_hub=$POLICY_PUSH_TO_HUB"
  echo "Recording:"
  echo "  dataset_fps=$DATASET_FPS"
  echo "  num_episodes=$NUM_EPISODES"
  echo "  episode_time_s=$EPISODE_TIME_S"
  echo "  reset_time_s=$RESET_TIME_S"
  echo "  manual_episode_start=$MANUAL_EPISODE_START"
  echo "  push_to_hub=$PUSH_TO_HUB"
  echo "  resume=$RECORD_RESUME"
  echo "  display_data=$DISPLAY_DATA"
  echo "  display_compressed_images=${DISPLAY_COMPRESSED_IMAGES:-}"
  echo "  streaming_encoding=$STREAMING_ENCODING"
  echo "  encoder_threads=${ENCODER_THREADS:-}"
  echo "  camera_encoder_vcodec=${CAMERA_ENCODER_VCODEC:-default}"
  echo "  camera_encoder_preset=${CAMERA_ENCODER_PRESET:-default}"
  echo "  camera_encoder_crf=${CAMERA_ENCODER_CRF:-default}"
  echo "Rollout:"
  echo "  policy_path=$ROLLOUT_POLICY_PATH"
  echo "  fps=$ROLLOUT_FPS"
  echo "  duration_s=$ROLLOUT_DURATION_S"
  echo "  inference_type=$ROLLOUT_INFERENCE_TYPE"
  echo "  rtc_execution_horizon=${ROLLOUT_RTC_EXECUTION_HORIZON:-}"
  echo "  rtc_max_guidance_weight=${ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT:-}"
  echo "  rtc_queue_threshold=${ROLLOUT_RTC_QUEUE_THRESHOLD:-}"
  echo "  return_to_initial_position=$ROLLOUT_RETURN_TO_INITIAL_POSITION"
  echo "  rename_map=${ROLLOUT_RENAME_MAP:-}"
}
