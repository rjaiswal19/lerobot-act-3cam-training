#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEROBOT_DIR="$ROOT_DIR/external/lerobot"

if [[ ! -d "$LEROBOT_DIR" ]]; then
  echo "Missing $LEROBOT_DIR."
  echo "Run: make init"
  exit 1
fi

python -m pip install -e "$LEROBOT_DIR[peft]"
