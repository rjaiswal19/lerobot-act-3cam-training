#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

require_hf
require_task_config

cmd=(
  lerobot-train
  --dataset.repo_id="$DATASET_REPO_ID"
  --policy.type="$POLICY_TYPE"
  --output_dir="$TRAIN_OUTPUT_DIR"
  --job_name="$JOB_NAME"
  --policy.device="$POLICY_DEVICE"
  --wandb.enable="$WANDB_ENABLE"
  --policy.repo_id="$POLICY_REPO_ID"
  --policy.push_to_hub="$POLICY_PUSH_TO_HUB"
  --policy.private="$POLICY_PRIVATE"
)

append_arg_if_set() {
  local flag="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    cmd+=("$flag=$value")
  fi
}

append_arg_if_set "--steps" "${TRAIN_STEPS:-}"
append_arg_if_set "--batch_size" "${TRAIN_BATCH_SIZE:-}"
append_arg_if_set "--policy.pretrained_path" "${POLICY_PRETRAINED_PATH:-}"
append_arg_if_set "--policy.compile_model" "${POLICY_COMPILE_MODEL:-}"
append_arg_if_set "--policy.gradient_checkpointing" "${POLICY_GRADIENT_CHECKPOINTING:-}"
append_arg_if_set "--policy.dtype" "${POLICY_DTYPE:-}"
append_arg_if_set "--policy.freeze_vision_encoder" "${POLICY_FREEZE_VISION_ENCODER:-}"
append_arg_if_set "--policy.train_expert_only" "${POLICY_TRAIN_EXPERT_ONLY:-}"
append_arg_if_set "--policy.normalization_mapping" "${POLICY_NORMALIZATION_MAPPING:-}"
append_arg_if_set "--policy.use_relative_actions" "${POLICY_USE_RELATIVE_ACTIONS:-}"
append_arg_if_set "--policy.relative_exclude_joints" "${POLICY_RELATIVE_EXCLUDE_JOINTS:-}"
append_arg_if_set "--policy.n_obs_steps" "${POLICY_N_OBS_STEPS:-}"
append_arg_if_set "--policy.chunk_size" "${POLICY_CHUNK_SIZE:-}"
append_arg_if_set "--policy.n_action_steps" "${POLICY_N_ACTION_STEPS:-}"
append_arg_if_set "--policy.vision_backbone" "${POLICY_VISION_BACKBONE:-}"
append_arg_if_set "--policy.pretrained_backbone_weights" "${POLICY_PRETRAINED_BACKBONE_WEIGHTS:-}"
append_arg_if_set "--policy.replace_final_stride_with_dilation" "${POLICY_REPLACE_FINAL_STRIDE_WITH_DILATION:-}"
append_arg_if_set "--policy.dim_model" "${POLICY_DIM_MODEL:-}"
append_arg_if_set "--policy.n_heads" "${POLICY_N_HEADS:-}"
append_arg_if_set "--policy.dim_feedforward" "${POLICY_DIM_FEEDFORWARD:-}"
append_arg_if_set "--policy.n_encoder_layers" "${POLICY_N_ENCODER_LAYERS:-}"
append_arg_if_set "--policy.n_decoder_layers" "${POLICY_N_DECODER_LAYERS:-}"
append_arg_if_set "--policy.use_vae" "${POLICY_USE_VAE:-}"
append_arg_if_set "--policy.latent_dim" "${POLICY_LATENT_DIM:-}"
append_arg_if_set "--policy.n_vae_encoder_layers" "${POLICY_N_VAE_ENCODER_LAYERS:-}"
append_arg_if_set "--policy.dropout" "${POLICY_DROPOUT:-}"
append_arg_if_set "--policy.kl_weight" "${POLICY_KL_WEIGHT:-}"
append_arg_if_set "--policy.temporal_ensemble_coeff" "${POLICY_TEMPORAL_ENSEMBLE_COEFF:-}"
append_arg_if_set "--policy.optimizer_lr" "${POLICY_OPTIMIZER_LR:-}"
append_arg_if_set "--policy.optimizer_weight_decay" "${POLICY_OPTIMIZER_WEIGHT_DECAY:-}"
append_arg_if_set "--policy.optimizer_lr_backbone" "${POLICY_OPTIMIZER_LR_BACKBONE:-}"
append_arg_if_set "--peft.method_type" "${PEFT_METHOD_TYPE:-}"
append_arg_if_set "--peft.r" "${PEFT_R:-}"
append_arg_if_set "--peft.target_modules" "${PEFT_TARGET_MODULES:-}"
append_arg_if_set "--peft.full_training_modules" "${PEFT_FULL_TRAINING_MODULES:-}"

if declare -p POLICY_EXTRA_ARGS >/dev/null 2>&1; then
  cmd+=("${POLICY_EXTRA_ARGS[@]}")
fi

echo "Training $POLICY_TYPE on dataset: $DATASET_REPO_ID"
echo "Policy output repo:      $POLICY_REPO_ID"
echo "Policy config:           $POLICY_CONFIG_FILE"
printf 'Command:'
printf ' %q' "${cmd[@]}"
printf '\n'

"${cmd[@]}"
