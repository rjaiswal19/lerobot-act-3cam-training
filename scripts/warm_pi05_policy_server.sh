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

export TASK="${TASK:-handoff_blue}"
export POLICY_TYPE="pi05"
export ROLLOUT_POLICY_PATH="${ROLLOUT_POLICY_PATH:-${ZERO_SHOT_POLICY_PATH:-lerobot/pi05_base}}"
export ROLLOUT_RENAME_MAP="${ROLLOUT_RENAME_MAP:-${ZERO_SHOT_RENAME_MAP:-}}"

source "$ROOT_DIR/scripts/common.sh"
require_robot

SERVER_ADDRESS="${PI05_POLICY_SERVER_ADDR:-${PI05_POLICY_SERVER_HOST:-127.0.0.1}:${PI05_POLICY_SERVER_PORT:-8080}}"
ACTIONS_PER_CHUNK="${PI05_ACTIONS_PER_CHUNK:-1}"

export POLICY_DEVICE ROBOT_ID ROBOT_PORT
export ROBOT_CAN_ADAPTER="${ROBOT_CAN_ADAPTER:-damiao}"
export TASK_DESCRIPTION="${TASK_DESCRIPTION:-}"
export CAMERA_WIDTH="${CAMERA_WIDTH:-640}"
export CAMERA_HEIGHT="${CAMERA_HEIGHT:-480}"
export CAMERA_FPS="${CAMERA_FPS:-30}"
export WRIST_CAMERA_INDEX="${WRIST_CAMERA_INDEX:-1}"
export WRIST_CAMERA_WIDTH="${WRIST_CAMERA_WIDTH:-$CAMERA_WIDTH}"
export WRIST_CAMERA_HEIGHT="${WRIST_CAMERA_HEIGHT:-$CAMERA_HEIGHT}"
export WRIST_CAMERA_FPS="${WRIST_CAMERA_FPS:-$CAMERA_FPS}"
export ZED_CAMERA_SERIAL_NUMBER="${ZED_CAMERA_SERIAL_NUMBER:-0}"
export ZED_CAMERA_RESOLUTION="${ZED_CAMERA_RESOLUTION:-HD1080}"
export ZED_CAMERA_DEPTH_MODE="${ZED_CAMERA_DEPTH_MODE:-NONE}"
export ZED_CAMERA_WIDTH="${ZED_CAMERA_WIDTH:-1280}"
export ZED_CAMERA_HEIGHT="${ZED_CAMERA_HEIGHT:-720}"
export ZED_CAMERA_FPS="${ZED_CAMERA_FPS:-15}"
export ZED_CAMERA_COLOR_MODE="${ZED_CAMERA_COLOR_MODE:-rgb}"
export ZED_CAMERA_TIMEOUT_MS="${ZED_CAMERA_TIMEOUT_MS:-2000}"
export ZED_CAMERA_WARMUP_S="${ZED_CAMERA_WARMUP_S:-0.5}"
export ZED_LEFT_CAMERA_SIDE="${ZED_LEFT_CAMERA_SIDE:-left}"
export ZED_LEFT_CAMERA_WIDTH="${ZED_LEFT_CAMERA_WIDTH:-$ZED_CAMERA_WIDTH}"
export ZED_LEFT_CAMERA_HEIGHT="${ZED_LEFT_CAMERA_HEIGHT:-$ZED_CAMERA_HEIGHT}"
export ZED_LEFT_CAMERA_FPS="${ZED_LEFT_CAMERA_FPS:-$ZED_CAMERA_FPS}"
export ZED_RIGHT_CAMERA_SIDE="${ZED_RIGHT_CAMERA_SIDE:-right}"
export ZED_RIGHT_CAMERA_WIDTH="${ZED_RIGHT_CAMERA_WIDTH:-$ZED_CAMERA_WIDTH}"
export ZED_RIGHT_CAMERA_HEIGHT="${ZED_RIGHT_CAMERA_HEIGHT:-$ZED_CAMERA_HEIGHT}"
export ZED_RIGHT_CAMERA_FPS="${ZED_RIGHT_CAMERA_FPS:-$ZED_CAMERA_FPS}"
export PI05_ACTIONS_PER_CHUNK="$ACTIONS_PER_CHUNK"

echo "Warming Pi0.5 policy server:"
echo "  server=$SERVER_ADDRESS"
echo "  policy=$ROLLOUT_POLICY_PATH"
echo "  device=$POLICY_DEVICE"
echo "  actions_per_chunk=$ACTIONS_PER_CHUNK"
echo "  rename_map=$ROLLOUT_RENAME_MAP"
echo

python - <<'PY'
import json
import os
import pickle
import time

import grpc
import numpy as np

from lerobot.async_inference.helpers import (
    RemotePolicyConfig,
    TimedObservation,
    map_robot_keys_to_lerobot_features,
)
from lerobot.cameras.opencv import OpenCVCameraConfig
from lerobot.robots import make_robot_from_config
from lerobot.transport import services_pb2, services_pb2_grpc
from lerobot.transport.utils import grpc_channel_options, send_bytes_in_chunks
from lerobot_camera_zed_sdk import ZedSdkCameraConfig
from lerobot_robot_seeed_b601 import SeeedB601DMFollowerConfig


def env_int(name: str, default: int) -> int:
    return int(os.environ.get(name) or default)


rename_map = json.loads(os.environ["ROLLOUT_RENAME_MAP"]) if os.environ.get("ROLLOUT_RENAME_MAP") else {}
server_address = os.environ.get("PI05_POLICY_SERVER_ADDR") or (
    f"{os.environ.get('PI05_POLICY_SERVER_HOST', '127.0.0.1')}:"
    f"{os.environ.get('PI05_POLICY_SERVER_PORT', '8080')}"
)

cfg = SeeedB601DMFollowerConfig(
    id=os.environ["ROBOT_ID"],
    port=os.environ["ROBOT_PORT"],
    can_adapter=os.environ.get("ROBOT_CAN_ADAPTER") or "damiao",
    cameras={
        "wrist": OpenCVCameraConfig(
            index_or_path=env_int("WRIST_CAMERA_INDEX", 1),
            width=env_int("WRIST_CAMERA_WIDTH", env_int("CAMERA_WIDTH", 640)),
            height=env_int("WRIST_CAMERA_HEIGHT", env_int("CAMERA_HEIGHT", 480)),
            fps=env_int("WRIST_CAMERA_FPS", env_int("CAMERA_FPS", 30)),
        ),
        "zed_left": ZedSdkCameraConfig(
            serial_number=env_int("ZED_CAMERA_SERIAL_NUMBER", 0),
            side=os.environ.get("ZED_LEFT_CAMERA_SIDE", "left"),
            resolution=os.environ.get("ZED_CAMERA_RESOLUTION", "HD1080"),
            depth_mode=os.environ.get("ZED_CAMERA_DEPTH_MODE", "NONE"),
            width=env_int("ZED_LEFT_CAMERA_WIDTH", env_int("ZED_CAMERA_WIDTH", 1280)),
            height=env_int("ZED_LEFT_CAMERA_HEIGHT", env_int("ZED_CAMERA_HEIGHT", 720)),
            fps=env_int("ZED_LEFT_CAMERA_FPS", env_int("ZED_CAMERA_FPS", 15)),
            color_mode=os.environ.get("ZED_CAMERA_COLOR_MODE", "rgb"),
            timeout_ms=env_int("ZED_CAMERA_TIMEOUT_MS", 2000),
            warmup_s=float(os.environ.get("ZED_CAMERA_WARMUP_S", "0.5")),
        ),
        "zed_right": ZedSdkCameraConfig(
            serial_number=env_int("ZED_CAMERA_SERIAL_NUMBER", 0),
            side=os.environ.get("ZED_RIGHT_CAMERA_SIDE", "right"),
            resolution=os.environ.get("ZED_CAMERA_RESOLUTION", "HD1080"),
            depth_mode=os.environ.get("ZED_CAMERA_DEPTH_MODE", "NONE"),
            width=env_int("ZED_RIGHT_CAMERA_WIDTH", env_int("ZED_CAMERA_WIDTH", 1280)),
            height=env_int("ZED_RIGHT_CAMERA_HEIGHT", env_int("ZED_CAMERA_HEIGHT", 720)),
            fps=env_int("ZED_RIGHT_CAMERA_FPS", env_int("ZED_CAMERA_FPS", 15)),
            color_mode=os.environ.get("ZED_CAMERA_COLOR_MODE", "rgb"),
            timeout_ms=env_int("ZED_CAMERA_TIMEOUT_MS", 2000),
            warmup_s=float(os.environ.get("ZED_CAMERA_WARMUP_S", "0.5")),
        ),
    },
)

robot = make_robot_from_config(cfg)
features = map_robot_keys_to_lerobot_features(robot)
policy_config = RemotePolicyConfig(
    os.environ.get("POLICY_TYPE", "pi05"),
    os.environ["ROLLOUT_POLICY_PATH"],
    features,
    env_int("PI05_ACTIONS_PER_CHUNK", 1),
    os.environ["POLICY_DEVICE"],
    rename_map,
)

channel = grpc.insecure_channel(server_address, grpc_channel_options(initial_backoff="0.1000s"))
stub = services_pb2_grpc.AsyncInferenceStub(channel)
stub.Ready(services_pb2.Empty())
print("Sending policy instructions...", flush=True)
t0 = time.perf_counter()
stub.SendPolicyInstructions(services_pb2.PolicySetup(data=pickle.dumps(policy_config)), timeout=900)
print(f"Policy server warm in {time.perf_counter() - t0:.1f}s", flush=True)

if os.environ.get("PI05_WARM_SMOKE_INFERENCE", "").lower() in {"1", "true", "yes", "on"}:
    raw_observation = {
        "wrist": np.zeros(
            (env_int("WRIST_CAMERA_HEIGHT", 480), env_int("WRIST_CAMERA_WIDTH", 640), 3),
            dtype=np.uint8,
        ),
        "zed_left": np.zeros(
            (env_int("ZED_LEFT_CAMERA_HEIGHT", env_int("ZED_CAMERA_HEIGHT", 720)),
             env_int("ZED_LEFT_CAMERA_WIDTH", env_int("ZED_CAMERA_WIDTH", 1280)),
             3),
            dtype=np.uint8,
        ),
        "zed_right": np.zeros(
            (env_int("ZED_RIGHT_CAMERA_HEIGHT", env_int("ZED_CAMERA_HEIGHT", 720)),
             env_int("ZED_RIGHT_CAMERA_WIDTH", env_int("ZED_CAMERA_WIDTH", 1280)),
             3),
            dtype=np.uint8,
        ),
        "task": os.environ.get("TASK_DESCRIPTION") or "Pick up the blue beaker",
    }
    for key in robot.observation_features:
        raw_observation.setdefault(key, 0.0)

    observation = TimedObservation(
        timestamp=time.time(),
        timestep=0,
        observation=raw_observation,
        must_go=True,
    )
    observation_iterator = send_bytes_in_chunks(
        pickle.dumps(observation),
        services_pb2.Observation,
        log_prefix="[SMOKE] Observation",
        silent=True,
    )
    print("Sending synthetic observation...", flush=True)
    stub.SendObservations(observation_iterator, timeout=60)
    response = stub.GetActions(services_pb2.Empty(), timeout=float(os.environ.get("PI05_SMOKE_TIMEOUT_S", "300")))
    if not response.data:
        raise RuntimeError("Policy server returned no action for synthetic observation")
    timed_actions = pickle.loads(response.data)
    if not timed_actions:
        raise RuntimeError("Policy server returned an empty action chunk")
    first_action = timed_actions[0].get_action()
    flat_action = first_action.flatten().detach().cpu().tolist()
    preview = ", ".join(f"{value:.4f}" for value in flat_action[:10])
    print(
        f"Smoke inference action chunk: count={len(timed_actions)} "
        f"shape={tuple(first_action.shape)} dtype={first_action.dtype} "
        f"device={first_action.device} first_values=[{preview}]",
        flush=True,
    )
channel.close()
PY
