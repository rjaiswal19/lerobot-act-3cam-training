#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

if ! command -v lerobot-find-cameras >/dev/null 2>&1; then
  echo "lerobot-find-cameras is not installed."
  echo "Run: bash scripts/install_lerobot_from_source.sh"
  exit 1
fi

lerobot-find-cameras opencv
