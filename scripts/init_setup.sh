#!/usr/bin/env bash
set -euo pipefail

echo "Installing Hugging Face CLI..."
python -m pip install -U "huggingface_hub[cli]"

echo "Installing LeRobot from source..."
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/install_lerobot_from_source.sh"

echo
echo "Setup finished."
echo
echo "Next interactive login steps:"
echo "  hf auth login"
echo "  wandb login    # only needed if WANDB_ENABLE=true"
echo
echo "Then verify:"
echo "  make config pour"
echo "  make config swirl"
