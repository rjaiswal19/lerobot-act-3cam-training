SHELL := /usr/bin/env bash

KNOWN_TASKS := pour swirl
TASK_FROM_GOALS := $(filter $(KNOWN_TASKS),$(MAKECMDGOALS))
TASK ?= $(firstword $(TASK_FROM_GOALS))

.PHONY: help init setup config cameras calibrate-follower calibrate-leader teleop record train rollout $(KNOWN_TASKS)

help:
	@echo "Usage:"
	@echo "  make config pour"
	@echo "  make record pour"
	@echo "  make train pour"
	@echo "  make rollout pour"
	@echo "  make record swirl"
	@echo "  make train swirl"
	@echo ""
	@echo "Other:"
	@echo "  make init"
	@echo "  make setup"
	@echo "  make cameras"
	@echo "  make calibrate-follower"
	@echo "  make calibrate-leader"

init:
	@bash scripts/init_setup.sh

setup: init

config:
	@TASK="$(TASK)" bash scripts/show_config.sh

cameras:
	@bash scripts/find_cameras.sh

calibrate-follower:
	@bash scripts/calibrate_robot.sh follower

calibrate-leader:
	@bash scripts/calibrate_robot.sh leader

teleop:
	@TASK="$(TASK)" bash scripts/teleoperate_3cam.sh

record:
	@test -n "$(TASK)" || (echo "Choose a task: make record pour OR make record swirl"; exit 1)
	@TASK="$(TASK)" bash scripts/record_dataset.sh

train:
	@test -n "$(TASK)" || (echo "Choose a task: make train pour OR make train swirl"; exit 1)
	@TASK="$(TASK)" bash scripts/train_act.sh

rollout:
	@test -n "$(TASK)" || (echo "Choose a task: make rollout pour OR make rollout swirl"; exit 1)
	@TASK="$(TASK)" bash scripts/rollout_policy.sh

$(KNOWN_TASKS):
	@:
