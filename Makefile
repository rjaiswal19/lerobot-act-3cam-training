SHELL := /usr/bin/env bash

KNOWN_TASKS := pour swirl pick
TASK_FROM_GOALS := $(filter $(KNOWN_TASKS),$(MAKECMDGOALS))
TASK ?= $(firstword $(TASK_FROM_GOALS))

.PHONY: help init setup install-pi install-peft config cameras check-cameras check-follower-motors follower-motor-check calibrate-follower calibrate-leader teleop record resume record-fixed viz train rollout $(KNOWN_TASKS)

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
	@echo "  make record-fixed pour"
	@echo "  make viz pour EPISODE=0"
	@echo "  make train pour"
	@echo "  make rollout pour"
	@echo "  make record swirl"
	@echo "  make train swirl"
	@echo "  make record pick"
	@echo "  make record pick TEXT=\"Pick up the red test tube\""
	@echo "  make train pick"
	@echo ""
	@echo "Other:"
	@echo "  make init"
	@echo "  make setup"
	@echo "  make install-pi"
	@echo "  make install-peft"
	@echo "  make cameras"
	@echo "  make check-cameras"
	@echo "  make check-follower-motors"
	@echo "  make follower-motor-check"
	@echo "  make calibrate-follower"
	@echo "  make calibrate-leader"

init:
	$(call run_command,bash scripts/init_setup.sh)

setup: init

install-pi:
	$(call run_command,bash scripts/install_pi_deps.sh)

install-peft:
	$(call run_command,bash scripts/install_peft_deps.sh)

config:
	$(call run_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/show_config.sh)

cameras:
	$(call run_command,bash scripts/find_cameras.sh)

check-cameras:
	$(call run_command,bash scripts/check_configured_cameras.sh)

check-follower-motors:
	$(call run_command,bash scripts/check_follower_motors.sh)

follower-motor-check:
	$(call run_command,bash scripts/check_follower_motors.sh)

calibrate-follower:
	$(call run_command,bash scripts/calibrate_robot.sh follower)

calibrate-leader:
	$(call run_command,bash scripts/calibrate_robot.sh leader)

teleop:
	$(call run_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/teleoperate_3cam.sh)

record:
	$(call show_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_interactive.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make record pour OR make record swirl OR make record pick"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_interactive.sh

resume:
	$(call show_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_interactive.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make resume pour OR make resume swirl OR make resume pick"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_interactive.sh

record-fixed:
	$(call show_command,TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh)
	@test -n "$(TASK)" || (echo "Choose a task: make record-fixed pour OR make record-fixed swirl OR make record-fixed pick"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/record_dataset.sh

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
	@test -n "$(TASK)" || (echo "Choose a task: make rollout pour OR make rollout swirl OR make rollout pick"; exit 1)
	@TASK="$(TASK)" TEXT="$(TEXT)" TASK_TEXT="$(TASK_TEXT)" TASK_DESCRIPTION="$(TASK_DESCRIPTION)" bash scripts/rollout_policy.sh

$(KNOWN_TASKS):
	@:
