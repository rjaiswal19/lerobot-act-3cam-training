#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv-pi05-jetson}"
PYTHON_BIN="${PYTHON_BIN:-python3.10}"
LEROBOT_DIR="$ROOT_DIR/external/lerobot"
LEROBOT_PATCH="$ROOT_DIR/patches/lerobot/local-runtime-fixes.patch"

run() {
  printf 'Command:'
  printf ' %q' "$@"
  printf '\n'
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN=true, not executing command."
    return 0
  fi
  "$@"
}

apply_lerobot_patch() {
  if [[ ! -f "$LEROBOT_PATCH" ]]; then
    return 0
  fi

  if [[ ! -d "$LEROBOT_DIR/.git" ]]; then
    echo "Missing $LEROBOT_DIR. Run make init first."
    exit 1
  fi

  if git -C "$LEROBOT_DIR" apply --check "$LEROBOT_PATCH" >/dev/null 2>&1; then
    echo "Applying local LeRobot runtime patch..."
    git -C "$LEROBOT_DIR" apply "$LEROBOT_PATCH"
  elif git -C "$LEROBOT_DIR" apply --reverse --check "$LEROBOT_PATCH" >/dev/null 2>&1; then
    echo "Local LeRobot runtime patch already applied."
  else
    echo "Could not apply $LEROBOT_PATCH to $LEROBOT_DIR."
    echo "Reset or update external/lerobot, then rerun this script."
    exit 1
  fi
}

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Missing $PYTHON_BIN. Install Python 3.10 or set PYTHON_BIN=/path/to/python3.10."
  exit 1
fi

apply_lerobot_patch

run "$PYTHON_BIN" -m venv "$VENV_DIR"

PIP=("$VENV_DIR/bin/python" -m pip)

run "${PIP[@]}" install --no-cache-dir --upgrade pip setuptools wheel
run "${PIP[@]}" install --no-cache-dir \
  torch==2.11.0 \
  torchvision==0.26.0 \
  --index-url=https://pypi.jetson-ai-lab.io/jp6/cu126
run "${PIP[@]}" install --no-cache-dir \
  --extra-index-url=https://pypi.nvidia.com \
  nvidia-cudss-cu12 \
  nvidia-cusparselt-cu12

# JetPack provides the cuBLAS build matched to the device driver. The PyPI
# nvidia-cublas-cu12 package can be pulled in by CUDA meta packages and may
# preload an incompatible cuBLAS before torch reaches the system library.
run "${PIP[@]}" uninstall -y nvidia-cublas-cu12

run "${PIP[@]}" install --no-cache-dir \
  -e "$LEROBOT_DIR[feetech,hardware,pi,async]" \
  -e "$ROOT_DIR/external/lerobot-teleoperator-rebot-arm-102" \
  -e "$ROOT_DIR/external/lerobot-robot-seeed-b601" \
  motorbridge \
  -e "$ROOT_DIR/packages/lerobot_camera_zed_sdk"

if [[ -f /usr/local/zed/include/sl/Camera.hpp ]]; then
  major="$(awk '/ZED_SDK_MAJOR_VERSION/ {print $3; exit}' /usr/local/zed/include/sl/Camera.hpp)"
  minor="$(awk '/ZED_SDK_MINOR_VERSION/ {print $3; exit}' /usr/local/zed/include/sl/Camera.hpp)"
  arch="$(uname -m)"
  wheel_url="https://download.stereolabs.com/zedsdk/${major}.${minor}/whl/linux_${arch}/pyzed-${major}.${minor}-cp310-cp310-linux_${arch}.whl"
  run "${PIP[@]}" install --no-cache-dir --no-deps "$wheel_url"
else
  echo "ZED SDK header not found; skipping pyzed install."
fi

echo "Pi0.5 Jetson env ready: $VENV_DIR"
