SHELL := /usr/bin/env bash

KNOWN_TASKS := pour swirl pick pour_blue pour_yellow pour_blue_to_green pour_yellow_to_green swirl_green_beaker handoff_blue handoff_yellow handoff_green
TASK_FROM_GOALS := $(filter $(KNOWN_TASKS),$(MAKECMDGOALS))
TASK ?= $(firstword $(TASK_FROM_GOALS))

.PHONY: help init setup install-pi install-pi05-jetson install-peft config cameras check-cameras profile-cameras camera-profiler camera-only-profiler check-follower-motors follower-motor-check profile-record-loop calibrate-follower calibrate-leader teleop record resume record-fixed record-interactive viz train rollout pi05-policy-server chemist-demo chemist-demo-dry-run zero-shot-handoff-blue zero-shot-handoff-yellow zero-shot-handoff-green zero-shot-handoff-blue-dry-run zero-shot-handoff-yellow-dry-run zero-shot-handoff-green-dry-run zero-shot-handoff-blue-async zero-shot-handoff-yellow-async zero-shot-handoff-green-async zero-shot-handoff-blue-async-dry-run zero-shot-handoff-yellow-async-dry-run zero-shot-handoff-green-async-dry-run $(KNOWN_TASKS)

define show_command
	@printf 'Make command: %s\n' '$(strip $(1))'
endef

define run_command
	$(call show_command,$(1))
	@$(1)
endef

help:
	$(call show_command,make help)
	@echo "Usage:"
	@echo "  make config pour"
	@echo "  make record pour"
	@echo "  make resume pour"
	@echo "  make record-interactive pour"
	@echo "  make viz pour EPISODE=0"
	@echo "  make train pour"
	@echo "  make rollout pour"
	@echo "  make record swirl"
	@echo "  make train swirl"
	@echo "  make record pick"
	@echo "  make record pick TEXT=\"Pick up the red test tube\""
	@echo "  make train pick"
	@echo "  make record pour_blue"
	@echo "  make record pour_yellow"
	@echo "  POLICY_TYPE=pi05 make record pour_blue_to_green"
	@echo "  POLICY_TYPE=pi05 make record pour_yellow_to_green"
	@echo "  POLICY_TYPE=pi05 make record swirl_green_beaker"
	@echo "  POLICY_TYPE=pi05 make train pour_blue_to_green"
	@echo "  POLICY_TYPE=pi05 make train pour_yellow_to_green"
	@echo "  POLICY_TYPE=pi05 make train swirl_green_beaker"
	@echo "  make chemist-demo-dry-run"
	@echo "  make chemist-demo"
	@echo "  make zero-shot-handoff-blue-dry-run"
	@echo "  make pi05-policy-server"
	@echo "  make zero-shot-handoff-blue-async-dry-run"
	@echo "  # physical pi05_base zero-shot targets are refused without a B601-compatible policy"
	@echo ""
	@echo "Other:"
	@echo "  make init"
	@echo "  make setup"
	@echo "  make install-pi"
	@echo "  make install-pi05-jetson"
	@echo "  make install-peft"
	@echo "  make cameras"
	@echo "  make check-cameras"
	@echo "  make profile-cameras"
	@echo "  make check-follower-motors"
	@echo "  make follower-motor-check"
	@echo "  make profile-record-loop"
	@echo "  make calibrate-follower"
	@echo "  make calibrate-leader"

init:
	$(call run_command,bash scripts/init_setup.sh)

setup: init

install-pi:
	$(call run_command,bash scripts/install_pi_deps.sh)

install-pi05-jetson:
	$(call run_command,bash scripts/install_pi05_jetson_env.sh)

install-peft:
	$(call run_command,bash scripts/install_peft_deps.sh)

config:
	$(call run_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/show_config.sh)

cameras:
	$(call run_command,bash scripts/find_cameras.sh)

check-cameras:
	$(call run_command,bash scripts/check_configured_cameras.sh)

profile-cameras:
	$(call run_command,bash scripts/profile_cameras.sh)

camera-profiler: profile-cameras

camera-only-profiler: profile-cameras

check-follower-motors:
	$(call run_command,bash scripts/check_follower_motors.sh)

follower-motor-check:
	$(call run_command,bash scripts/check_follower_motors.sh)

profile-record-loop:
	$(call run_command,bash scripts/profile_record_loop.sh)

calibrate-follower:
	$(call run_command,bash scripts/calibrate_robot.sh follower)

calibrate-leader:
	$(call run_command,bash scripts/calibrate_robot.sh leader)

teleop:
	$(call run_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/teleoperate_3cam.sh)

record:
	$(call show_command,MANUAL_EPISODE_START=true TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make record pour OR make record swirl OR make record pick"; exit 1)
	@MANUAL_EPISODE_START=true TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh

resume:
	$(call show_command,RECORD_RESUME=true MANUAL_EPISODE_START=true TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make resume pour OR make resume swirl OR make resume pick"; exit 1)
	@RECORD_RESUME=true MANUAL_EPISODE_START=true TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh

record-fixed:
	$(call show_command,MANUAL_EPISODE_START=false TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make record-fixed pour OR make record-fixed swirl OR make record-fixed pick"; exit 1)
	@MANUAL_EPISODE_START=false TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh

record-interactive:
	$(call show_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_interactive.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make record-interactive pour OR make record-interactive swirl OR make record-interactive pick"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_interactive.sh

viz:
	$(call show_command,TASK="$(TASK)" EPISODE="$(EPISODE)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/visualize_dataset.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make viz pour EPISODE=0 OR make viz swirl EPISODE=0 OR make viz pick EPISODE=0"; exit 1)
	@TASK="$(TASK)" EPISODE="$(EPISODE)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/visualize_dataset.sh

train:
	$(call show_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/train_policy.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make train pour OR make train swirl OR make train pick"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/train_policy.sh

rollout:
	$(call show_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/rollout_policy.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make rollout pour OR make rollout swirl OR make rollout pick OR make rollout pour_blue_to_green"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/rollout_policy.sh

pi05-policy-server:
	$(call run_command,bash scripts/start_pi05_policy_server.sh)

chemist-demo:
	$(call run_command,bash scripts/run_chemist_demo.sh)

chemist-demo-dry-run:
	$(call run_command,bash scripts/run_chemist_demo.sh --dry-run)

zero-shot-handoff-blue:
	$(call run_command,bash scripts/rollout_pi05_base_zero_shot.sh handoff_blue)

zero-shot-handoff-yellow:
	$(call run_command,bash scripts/rollout_pi05_base_zero_shot.sh handoff_yellow)

zero-shot-handoff-green:
	$(call run_command,bash scripts/rollout_pi05_base_zero_shot.sh handoff_green)

zero-shot-handoff-blue-dry-run:
	$(call run_command,DRY_RUN=true bash scripts/rollout_pi05_base_zero_shot.sh handoff_blue)

zero-shot-handoff-yellow-dry-run:
	$(call run_command,DRY_RUN=true bash scripts/rollout_pi05_base_zero_shot.sh handoff_yellow)

zero-shot-handoff-green-dry-run:
	$(call run_command,DRY_RUN=true bash scripts/rollout_pi05_base_zero_shot.sh handoff_green)

zero-shot-handoff-blue-async:
	$(call run_command,bash scripts/rollout_pi05_base_zero_shot_async.sh handoff_blue)

zero-shot-handoff-yellow-async:
	$(call run_command,bash scripts/rollout_pi05_base_zero_shot_async.sh handoff_yellow)

zero-shot-handoff-green-async:
	$(call run_command,bash scripts/rollout_pi05_base_zero_shot_async.sh handoff_green)

zero-shot-handoff-blue-async-dry-run:
	$(call run_command,DRY_RUN=true bash scripts/rollout_pi05_base_zero_shot_async.sh handoff_blue)

zero-shot-handoff-yellow-async-dry-run:
	$(call run_command,DRY_RUN=true bash scripts/rollout_pi05_base_zero_shot_async.sh handoff_yellow)

zero-shot-handoff-green-async-dry-run:
	$(call run_command,DRY_RUN=true bash scripts/rollout_pi05_base_zero_shot_async.sh handoff_green)

$(KNOWN_TASKS):
	@:
