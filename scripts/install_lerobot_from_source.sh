#!/usr/bin/env bash
set -euo pipefail

mkdir -p external

if [[ ! -d external/lerobot ]]; then
  git clone https://github.com/huggingface/lerobot.git external/lerobot
fi

python -m pip install -U "huggingface_hub[cli]"
python -m pip install -e "external/lerobot[feetech]"

echo "Installed LeRobot from external/lerobot."
echo "Run: hf auth login"
