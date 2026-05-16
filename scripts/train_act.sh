#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config

echo "Training ACT on dataset: $DATASET_REPO_ID"
echo "Policy output repo:      $POLICY_REPO_ID"

lerobot-train \
  --dataset.repo_id="$DATASET_REPO_ID" \
  --policy.type=act \
  --output_dir="$TRAIN_OUTPUT_DIR" \
  --job_name="$JOB_NAME" \
  --policy.device="$POLICY_DEVICE" \
  --wandb.enable="$WANDB_ENABLE" \
  --policy.repo_id="$POLICY_REPO_ID" \
  --policy.push_to_hub="$POLICY_PUSH_TO_HUB" \
  --policy.private="$POLICY_PRIVATE"
