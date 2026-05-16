#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/python_deps.sh"
LEROBOT_DIR="$ROOT_DIR/external/lerobot"
REBOT_TELEOP_DIR="$ROOT_DIR/external/lerobot-teleoperator-rebot-arm-102"
REBOT_ROBOT_DIR="$ROOT_DIR/external/lerobot-robot-seeed-b601"

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

python_install -U "huggingface_hub[cli]"
python_install -e "$LEROBOT_DIR[feetech,core_scripts,training]"
python_install -e "$REBOT_TELEOP_DIR" -e "$REBOT_ROBOT_DIR" motorbridge

echo "Installed LeRobot from external/lerobot."
echo "Installed reBot integrations from external/lerobot-teleoperator-rebot-arm-102 and external/lerobot-robot-seeed-b601."
echo "Run: hf auth login"
