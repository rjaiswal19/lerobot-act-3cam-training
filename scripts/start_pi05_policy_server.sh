#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export POLICY_TYPE="${POLICY_TYPE:-pi05}"
if [[ -z "${VENV_DIR:-}" && -x "$ROOT_DIR/.venv-pi05-jetson/bin/python" ]]; then
  export VENV_DIR="$ROOT_DIR/.venv-pi05-jetson"
fi

source "$ROOT_DIR/scripts/common.sh"

require_hf

HOST="${PI05_POLICY_SERVER_HOST:-127.0.0.1}"
PORT="${PI05_POLICY_SERVER_PORT:-8080}"
SERVER_FPS="${PI05_POLICY_SERVER_FPS:-${ROLLOUT_FPS:-1}}"
INFERENCE_LATENCY="${PI05_POLICY_SERVER_INFERENCE_LATENCY:-0.05}"
OBS_QUEUE_TIMEOUT="${PI05_POLICY_SERVER_OBS_QUEUE_TIMEOUT:-2.0}"
export PI05_POLICY_DTYPE="${PI05_POLICY_DTYPE:-bfloat16}"

echo "Pi0.5 policy server:"
echo "  address=$HOST:$PORT"
echo "  fps=$SERVER_FPS"
echo "  inference_latency=$INFERENCE_LATENCY"
echo "  obs_queue_timeout=$OBS_QUEUE_TIMEOUT"
echo "  pi05_dtype=$PI05_POLICY_DTYPE"
echo

cmd=(
  python
  -m
  lerobot.async_inference.policy_server
  --host="$HOST"
  --port="$PORT"
  --fps="$SERVER_FPS"
  --inference_latency="$INFERENCE_LATENCY"
  --obs_queue_timeout="$OBS_QUEUE_TIMEOUT"
)

run_command "${cmd[@]}"
