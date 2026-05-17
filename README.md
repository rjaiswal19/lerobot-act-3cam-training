# LeRobot 3-Camera Policy Training Scaffold

This repo is a starter setup for training a LeRobot policy with:

- one wrist RGB camera
- two RGB feeds from a ZED stereo camera, treated as `zed_left` and `zed_right`
- a Seeed / SO-101-style follower arm

The default policy is ACT. Change `POLICY_TYPE` in `configs/local.env` to another LeRobot policy type, such as `pi0` or `pi05`, after confirming your installed LeRobot version supports it. This scaffold uses RGB camera frames plus robot joint state; it does not use ZED depth.

## What File Format Is Used?

LeRobot training data is a **LeRobotDataset**, not a single config file.

When you run:

```bash
bash scripts/record_dataset.sh
```

LeRobot records a dataset under:

```text
~/.cache/huggingface/lerobot/{HF_USER_OR_ORG}/{DATASET_NAME}
```

and, if enabled, uploads the same dataset to:

```text
https://huggingface.co/datasets/{HF_USER_OR_ORG}/{DATASET_NAME}
```

Internally the dataset is stored as:

```text
meta/       schema, episode metadata, task labels, stats
data/       Apache Parquet files for state, action, timestamp, indices
videos/     MP4 files for wrist / zed_left / zed_right camera streams
```

So yes, Parquet is involved. You normally do **not** manually create a `.parquet` file. You record a LeRobotDataset, then train directly from its repo id:

```bash
lerobot-train \
  --dataset.repo_id="${HF_USER_OR_ORG}/${DATASET_NAME}" \
  --policy.type="${POLICY_TYPE}"
```

The scripts in this repo just wrap those commands so you do not have to retype all robot, camera, and dataset arguments.

## Install

Your shell showed `huggingface-cli` is not installed. Current Hugging Face docs use the newer `hf` CLI.

```bash
python -m pip install -U "huggingface_hub[cli]"
hf auth login
```

Install LeRobot from source so the CLI names match the current docs:

```bash
make init
```

Then authenticate:

```bash
hf auth login
wandb login    # only if WANDB_ENABLE=true
```

For SO-100/SO-101 hardware you may also need OS-level serial permissions on Linux, for example:

```bash
sudo usermod -a -G dialout "$USER"
```

Then log out/in or reboot.

## Configure

Edit:

```text
configs/local.env
```

The file contains shared hardware, recording, and training defaults for the 3-camera setup.

Local runtime fixes for the external LeRobot checkout are tracked as:

```text
patches/lerobot/local-runtime-fixes.patch
```

`make init` applies this patch after cloning `external/lerobot`.

Task-specific dataset names and task descriptions live in:

```text
configs/tasks/pour.env
configs/tasks/swirl.env
configs/tasks/pour_blue_to_green.env
configs/tasks/pour_yellow_to_green.env
configs/tasks/swirl_green_beaker.env
```

Policy-specific training defaults live in:

```text
configs/policies/act.env
configs/policies/pi0.env
configs/policies/pi05.env
```

You can also create a private `.env` file for local overrides such as:

```bash
HF_USER_OR_ORG="your_hf_username"
```

`.env` is gitignored.

## Workflow

1. Find camera IDs:

```bash
make cameras
```

2. Calibrate the follower and leader arms:

```bash
make calibrate-follower
make calibrate-leader
```

3. Teleoperate with all three cameras visible:

```bash
make teleop pour
```

4. Record demonstrations:

```bash
make record pour
make record swirl

# This prompts before each episode while cameras/robot stay connected.
# Continue a partially recorded dataset with resume.
make resume pour
make resume swirl

# Fully automatic mode: fixed RESET_TIME_S between episodes, no prompt.
make record-fixed pour

# Old behavior: prompt before each episode and reconnect each time.
make record-interactive pour
```

5. Train the selected policy:

```bash
make train pour
make train swirl
```

6. Run the trained policy:

```bash
make rollout pour
make rollout swirl
```

## Autonomous Chemist Demo

The chemist demo composes Pi0.5 short-horizon skills for a single-arm setup:

1. pour the blue beaker into the green beaker
2. verify
3. pour the yellow beaker into the green beaker
4. verify
5. swirl the green beaker
6. verify

Record and train each color-specific skill with Pi0.5:

```bash
make install-pi

POLICY_TYPE=pi05 make record pour_blue_to_green
POLICY_TYPE=pi05 make record pour_yellow_to_green
POLICY_TYPE=pi05 make record swirl_green_beaker

POLICY_TYPE=pi05 make train pour_blue_to_green
POLICY_TYPE=pi05 make train pour_yellow_to_green
POLICY_TYPE=pi05 make train swirl_green_beaker
```

Dry-run the full plan before moving the robot:

```bash
make chemist-demo-dry-run
```

### Pi0.5 Base Zero-Shot Handoff

For colored-water plumbing checks, the downloaded `lerobot/pi05_base`
checkpoint can be loaded in dry-run mode. These commands use hardcoded color
prompts and the back-left corner of the white pad from the robot's perspective:

```bash
make zero-shot-handoff-blue-dry-run
make zero-shot-handoff-yellow-dry-run
make zero-shot-handoff-green-dry-run
```

Zero-shot Pi0.5 base uses `sync` inference and a camera rename map in:

```text
configs/demos/zero_shot_handoff.env
```

On Jetson Orin, the Pi0.5 rollout scripts prefer `.venv-pi05-jetson` when it
exists. That env uses the Jetson CUDA 12.6 Python 3.10 torch wheel (`sm_87`)
instead of generic PyPI CUDA wheels, which do not include Orin kernels.

To avoid reloading Pi0.5 for every short-horizon task, run the async policy
server once in one terminal:

```bash
make pi05-policy-server
```

Then run short client tasks from another terminal:

```bash
make zero-shot-handoff-blue-async-dry-run
```

The policy server keeps the loaded model/processors cached and reuses them
when the next client uses the same model, device, features, and camera rename
map.

Do not run `lerobot/pi05_base` directly on the physical B601 arm. The base model
emits a 32-dimensional action vector, while the B601 follower expects 7 absolute
joint targets in degrees. The rollout path now refuses that implicit first-N
mapping. Use a B601-finetuned checkpoint or a verified robot-specific action
transform before physical execution. See:

```text
docs/PI05_B601_MAPPING_NOTES.md
```

Run the physical demo with manual verification gates:

```bash
make chemist-demo
```

The planner defaults are in:

```text
configs/demos/chemist_mix.env
```

By default, `CHEMIST_PLANNER_MODE=auto`: if `OPENAI_API_KEY` is available,
the planner uses an LLM to choose the next allowed skill; otherwise it falls
back to the fixed safe single-arm order. The LLM is constrained to known skill
IDs only. It never outputs joint commands.

For first trials, keep `CHEMIST_VERIFY_MODE=manual`. To test the loop without
prompts:

```bash
CHEMIST_VERIFY_MODE=none bash scripts/run_chemist_demo.sh --dry-run
```

You can inspect the resolved config before running anything:

```bash
make config pour
make config swirl
POLICY_TYPE=pi05 make config pour_blue_to_green
```

## Values You Need To Fill

Required before recording:

- `HF_USER_OR_ORG`: your Hugging Face username or org, in `.env`.
- `ROBOT_PORT`: serial port for the follower arm, for example `/dev/ttyACM0` or `/dev/tty.usbmodem...`.
- `ROBOT_ID`: stable follower arm name. Keep the same ID after calibration.
- `TELEOP_PORT`: serial port for the leader arm or teleop device.
- `TELEOP_ID`: stable leader arm name. Keep the same ID after calibration.
- `WRIST_CAMERA_INDEX`: OpenCV ID/path for wrist camera.
- `ZED_LEFT_CAMERA_INDEX`: OpenCV ID/path for ZED left RGB.
- `ZED_RIGHT_CAMERA_INDEX`: OpenCV ID/path for ZED right RGB.
- `WRIST_CAMERA_WIDTH`, `WRIST_CAMERA_HEIGHT`, `WRIST_CAMERA_FPS`: wrist camera capture format.
- `ZED_LEFT_CAMERA_WIDTH`, `ZED_LEFT_CAMERA_HEIGHT`, `ZED_LEFT_CAMERA_FPS`: ZED left capture format.
- `ZED_RIGHT_CAMERA_WIDTH`, `ZED_RIGHT_CAMERA_HEIGHT`, `ZED_RIGHT_CAMERA_FPS`: ZED right capture format.
- `POLICY_TYPE`: LeRobot policy type, default `act`.
- `TASK_DESCRIPTION`: exact task phrase to store with every episode, in `configs/tasks/*.env`. You can override it per run with `TEXT="Pick up the red test tube" make record pick`.

Check these defaults:

- `ROBOT_TYPE=so101_follower`
- `TELEOP_TYPE=so101_leader`
- `CAMERA_WIDTH=640`
- `CAMERA_HEIGHT=480`
- `CAMERA_FPS=30`
- `NUM_EPISODES=50`
- `EPISODE_TIME_S=60`
- `RESET_TIME_S=20`, used by automatic `make record-fixed`; manual `make record` waits for Enter instead
- `RECORD_RESUME=false`
- `POLICY_TYPE=act`
- `POLICY_DEVICE=cuda`

Dataset names are task-specific and policy-independent. Model/output names include the policy type. With:

```bash
POLICY_TYPE="act"
```

`make config pour` resolves:

```text
dataset: seeed_3cam_pour_training
policy:  act_seeed_3cam_pour
```

If you change:

```bash
POLICY_TYPE="pi0"
```

then `make config pour` resolves:

```text
dataset: seeed_3cam_pour_training
policy:  pi0_seeed_3cam_pour
```

Edit the selected policy file to tune policy-specific defaults:

```text
configs/policies/act.env
configs/policies/pi0.env
configs/policies/pi05.env
```

Current defaults:

```text
act:
  TRAIN_STEPS=50000
  TRAIN_BATCH_SIZE=8
  POLICY_CHUNK_SIZE=100
  POLICY_N_ACTION_STEPS=100
  POLICY_N_OBS_STEPS=1
  POLICY_VISION_BACKBONE=resnet18
  POLICY_USE_VAE=true
  POLICY_KL_WEIGHT=10.0
  POLICY_TEMPORAL_ENSEMBLE_COEFF=

pi0:
  TRAIN_STEPS=3000
  TRAIN_BATCH_SIZE=32
  POLICY_PRETRAINED_PATH=lerobot/pi0_base
  POLICY_COMPILE_MODEL=true
  POLICY_GRADIENT_CHECKPOINTING=true
  POLICY_DTYPE=bfloat16
  POLICY_FREEZE_VISION_ENCODER=false
  POLICY_TRAIN_EXPERT_ONLY=false
  PEFT_METHOD_TYPE=
  PEFT_R=64

pi05:
  TRAIN_STEPS=3000
  TRAIN_BATCH_SIZE=32
  POLICY_PRETRAINED_PATH=lerobot/pi05_base
  POLICY_COMPILE_MODEL=true
  POLICY_GRADIENT_CHECKPOINTING=true
  POLICY_DTYPE=bfloat16
  POLICY_FREEZE_VISION_ENCODER=false
  POLICY_TRAIN_EXPERT_ONLY=false
  POLICY_NORMALIZATION_MAPPING={"ACTION":"MEAN_STD","STATE":"MEAN_STD","VISUAL":"IDENTITY"}
  PEFT_METHOD_TYPE=
  PEFT_R=64
```

Pi0 and Pi0.5 need LeRobot's Pi dependencies on the training machine:

```bash
cd external/lerobot
python -m pip install -e ".[pi]"
```

or from this repo root:

```bash
make install-pi
```

To train Pi0/Pi0.5 with LoRA instead of normal finetuning, install PEFT support:

```bash
make install-peft
```

Then edit `configs/policies/pi0.env` or `configs/policies/pi05.env`:

```bash
PEFT_METHOD_TYPE="LORA"
PEFT_R=64
```

The train script will add:

```text
--peft.method_type=LORA
--peft.r=64
```

GPU selection for training:

```bash
# Use the default visible GPU
POLICY_DEVICE="cuda"

# Pin a specific GPU
POLICY_DEVICE="cuda:0"
POLICY_DEVICE="cuda:1"

# On Apple Silicon, only for small tests
POLICY_DEVICE="mps"
```

You can also override it for one command:

```bash
POLICY_DEVICE="cuda:1" make train pour
```

If your ZED appears as one side-by-side OpenCV stream instead of separate left/right camera IDs, this scaffold needs a small custom camera adapter or a preprocessing split step. Start by running `bash scripts/find_cameras.sh` and send me the output.

Normal recording prompts before each episode and keeps cameras connected:

```bash
make record pour
```

It starts one `lerobot-record` process, connects cameras, ZED, robot, and leader once, then waits for Enter before each episode. Type `q` then Enter at the prompt to stop without disconnect/reconnect churn.

If you stop after some completed episodes and want to continue later, run:

```bash
make resume pour
```

If you want fixed automatic timing between episodes, run:

```bash
make record-fixed pour
```

If you want the old prompt-per-episode mode that reconnects each time, run:

```bash
make record-interactive pour
```

Both resume the same dataset instead of starting from episode 1 again.

## Notes

- The dataset is recorded in LeRobot format and normally stored under `~/.cache/huggingface/lerobot/{repo-id}`.
- Training uses the camera/state/action shapes saved in the dataset, so the policy config does not need hard-coded camera count or joint dimensions.
- Keep camera placement fixed between data collection and deployment.

More detail: [docs/DATASET_FORMAT.md](docs/DATASET_FORMAT.md).
