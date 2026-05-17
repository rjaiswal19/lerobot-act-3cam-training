#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/python_deps.sh"
LEROBOT_DIR="$ROOT_DIR/external/lerobot"
REBOT_TELEOP_DIR="$ROOT_DIR/external/lerobot-teleoperator-rebot-arm-102"
REBOT_ROBOT_DIR="$ROOT_DIR/external/lerobot-robot-seeed-b601"
ZED_CAMERA_DIR="$ROOT_DIR/packages/lerobot_camera_zed_sdk"
LEROBOT_PATCH="$ROOT_DIR/patches/lerobot/local-runtime-fixes.patch"

apply_lerobot_patch() {
  if [[ ! -f "$LEROBOT_PATCH" ]]; then
    return 0
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

install_pyzed_for_current_python() {
  local python_bin major minor py_tag arch wheel_url
  python_bin="$(project_python)"

  if "$python_bin" -c "import pyzed.sl" >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -f /usr/local/zed/include/sl/Camera.hpp ]]; then
    echo "ZED SDK not found at /usr/local/zed; skipping pyzed install."
    return 0
  fi

  major="$(awk '/ZED_SDK_MAJOR_VERSION/ {print $3; exit}' /usr/local/zed/include/sl/Camera.hpp)"
  minor="$(awk '/ZED_SDK_MINOR_VERSION/ {print $3; exit}' /usr/local/zed/include/sl/Camera.hpp)"
  py_tag="$("$python_bin" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"
  arch="$(uname -m)"
  wheel_url="https://download.stereolabs.com/zedsdk/${major}.${minor}/whl/linux_${arch}/pyzed-${major}.${minor}-${py_tag}-${py_tag}-linux_${arch}.whl"

  echo "Installing pyzed for $py_tag from $wheel_url"
  python_install --no-deps "$wheel_url"
}

mkdir -p "$ROOT_DIR/external"

if [[ ! -d "$LEROBOT_DIR" ]]; then
  git clone https://github.com/Seeed-Projects/lerobot.git "$LEROBOT_DIR"
fi

if [[ ! -d "$REBOT_TELEOP_DIR" ]]; then
  git clone https://github.com/Seeed-Projects/lerobot-teleoperator-rebot-arm-102.git "$REBOT_TELEOP_DIR"
fi

if [[ ! -d "$REBOT_ROBOT_DIR" ]]; then
  git clone https://github.com/Seeed-Projects/lerobot-robot-seeed-b601.git "$REBOT_ROBOT_DIR"
fi

apply_lerobot_patch

python_install -U "huggingface_hub[cli]"
python_install -e "$LEROBOT_DIR[feetech,core_scripts,training]"
python_install -e "$REBOT_TELEOP_DIR" -e "$REBOT_ROBOT_DIR" motorbridge
install_pyzed_for_current_python
python_install -e "$ZED_CAMERA_DIR"

echo "Installed LeRobot from external/lerobot."
echo "Installed reBot integrations from external/lerobot-teleoperator-rebot-arm-102 and external/lerobot-robot-seeed-b601."
echo "Installed ZED SDK camera integration from packages/lerobot_camera_zed_sdk."
echo "Run: hf auth login"
