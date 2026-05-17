#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config
require_robot
require_teleop

LEROBOT_DATA_HOME="${LEROBOT_DATA_HOME:-$HOME/.cache/huggingface/lerobot}"
BASE_LOCAL_DATASET_DIR="$LEROBOT_DATA_HOME/$DATASET_REPO_ID"

count_completed_episodes() {
  python "$ROOT_DIR/scripts/count_dataset_episodes.py" "$LOCAL_DATASET_DIR"
}

flush_pending_input() {
  if [[ ! -t 0 ]]; then
    return 0
  fi

  local _
  while IFS= read -r -s -t 0.05 -n 1 _; do
    :
  done
}

dataset_fps() {
  local dataset_dir="$1"
  python - "$dataset_dir" <<'PY'
import json
import sys
from pathlib import Path

info_path = Path(sys.argv[1]) / "meta" / "info.json"
try:
    info = json.loads(info_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)

fps = info.get("fps")
if isinstance(fps, int):
    print(fps)
PY
}

dataset_matches_fps() {
  local dataset_dir="$1"
  local fps
  fps="$(dataset_fps "$dataset_dir")"
  [[ -z "$fps" || "$fps" == "$DATASET_FPS" ]]
}

resolve_local_dataset_dir() {
  if [[ -d "$BASE_LOCAL_DATASET_DIR" ]]; then
    if dataset_matches_fps "$BASE_LOCAL_DATASET_DIR"; then
      printf '%s\n' "$BASE_LOCAL_DATASET_DIR"
      return 0
    fi
    echo "Skipping $BASE_LOCAL_DATASET_DIR because its fps=$(dataset_fps "$BASE_LOCAL_DATASET_DIR") but DATASET_FPS=$DATASET_FPS." >&2
  fi

  local parent base_name
  parent="$(dirname "$BASE_LOCAL_DATASET_DIR")"
  base_name="$(basename "$BASE_LOCAL_DATASET_DIR")"

  if [[ ! -d "$parent" ]]; then
    printf '%s\n' "$BASE_LOCAL_DATASET_DIR"
    return 0
  fi

  local candidates=()
  mapfile -t candidates < <(
    find "$parent" -maxdepth 1 -type d -name "${base_name}_*" -printf '%T@ %p\n' \
      | sort -rn \
      | cut -d' ' -f2-
  )

  local candidate count
  for candidate in "${candidates[@]}"; do
    if ! dataset_matches_fps "$candidate"; then
      continue
    fi
    count="$(python "$ROOT_DIR/scripts/count_dataset_episodes.py" "$candidate")"
    if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$BASE_LOCAL_DATASET_DIR"
}

LOCAL_DATASET_DIR="$(resolve_local_dataset_dir)"
completed="$(count_completed_episodes)"
if [[ ! "$completed" =~ ^[0-9]+$ ]]; then
  completed=0
fi

print_summary
echo "Interactive recording:"
echo "  base_dataset_dir=$BASE_LOCAL_DATASET_DIR"
echo "  local_dataset_dir=$LOCAL_DATASET_DIR"
echo "  completed_episodes=$completed"
echo
setup_live_display
echo

while (( completed < NUM_EPISODES )); do
  next_episode=$((completed + 1))

  flush_pending_input
  printf 'Press Enter to record episode %d/%d, or type q then Enter to stop: ' "$next_episode" "$NUM_EPISODES"
  read -r answer
  case "$answer" in
    q|Q|quit|QUIT|exit|EXIT)
      echo "Stopped before episode $next_episode. Resume later with: make record $TASK"
      exit 0
      ;;
  esac

  resume_flag=false
  if (( completed > 0 )); then
    resume_flag=true
  fi

  cmd=(lerobot-record)
  add_robot_args cmd true
  add_teleop_args cmd
  add_display_args cmd
  cmd+=(
    --dataset.repo_id="$DATASET_REPO_ID"
    --dataset.root="$LOCAL_DATASET_DIR"
    --dataset.fps="$DATASET_FPS"
    --dataset.num_episodes=1
    --dataset.single_task="$TASK_DESCRIPTION"
    --dataset.episode_time_s="$EPISODE_TIME_S"
    --dataset.reset_time_s=0
    --dataset.streaming_encoding="$STREAMING_ENCODING"
    --dataset.encoder_threads="$ENCODER_THREADS"
    --dataset.push_to_hub="$PUSH_TO_HUB"
    --resume="$resume_flag"
  )
  append_arg_if_set cmd "--dataset.camera_encoder.vcodec" "${CAMERA_ENCODER_VCODEC:-}"
  append_arg_if_set cmd "--dataset.camera_encoder.preset" "${CAMERA_ENCODER_PRESET:-}"
  append_arg_if_set cmd "--dataset.camera_encoder.crf" "${CAMERA_ENCODER_CRF:-}"

  run_command "${cmd[@]}"

  new_completed="$(count_completed_episodes)"
  if [[ "$new_completed" =~ ^[0-9]+$ ]] && (( new_completed >= next_episode )); then
    completed="$new_completed"
  else
    completed="$next_episode"
    echo "Could not verify episode count from local metadata; continuing from $completed."
  fi

  echo
  echo "Completed episodes: $completed/$NUM_EPISODES"
  echo
done

echo "Finished recording $NUM_EPISODES/$NUM_EPISODES episodes."
