# LeRobot ACT 3-Camera Training Scaffold

This repo is a starter setup for training a LeRobot ACT policy with:

- one wrist RGB camera
- two RGB feeds from a ZED stereo camera, treated as `zed_left` and `zed_right`
- a Seeed / SO-101-style follower arm

ACT uses RGB camera frames plus robot joint state and learns to predict future actions. It does not use ZED depth in this scaffold.

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

So yes, Parquet is involved. But for ACT you normally do **not** manually create a `.parquet` file. You record a LeRobotDataset, then train directly from its repo id:

```bash
lerobot-train \
  --dataset.repo_id="${HF_USER_OR_ORG}/${DATASET_NAME}" \
  --policy.type=act
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

The file contains shared hardware defaults for ACT and the 3-camera setup.

Task-specific dataset names and task descriptions live in:

```text
configs/tasks/pour.env
configs/tasks/swirl.env
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

# These are interactive: press Enter before each next episode.
# Continue a partially recorded dataset the same way.
make resume pour
make resume swirl

# Optional old behavior: run continuously with fixed RESET_TIME_S.
make record-fixed pour
```

5. Train ACT:

```bash
make train pour
make train swirl
```

6. Run the trained policy:

```bash
make rollout pour
make rollout swirl
```

You can inspect the resolved config before running anything:

```bash
make config pour
make config swirl
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
- `TASK_DESCRIPTION`: exact task phrase to store with every episode, in `configs/tasks/pour.env` or `configs/tasks/swirl.env`.

Check these defaults:

- `ROBOT_TYPE=so101_follower`
- `TELEOP_TYPE=so101_leader`
- `CAMERA_WIDTH=640`
- `CAMERA_HEIGHT=480`
- `CAMERA_FPS=30`
- `NUM_EPISODES=50`
- `EPISODE_TIME_S=60`
- `RESET_TIME_S=20`, only used by `make record-fixed`
- `RECORD_RESUME=false`
- `POLICY_DEVICE=cuda`

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

Normal recording is interactive:

```bash
make record pour
```

It waits for Enter before each episode, records one episode, then returns to the prompt. The next episode number is computed from the local dataset metadata and increments automatically.

If you stop after some completed episodes and want to continue later, run the same command:

```bash
make record pour
```

or:

```bash
make resume pour
```

Both resume the same dataset instead of starting from episode 1 again.

## Notes

- The dataset is recorded in LeRobot format and normally stored under `~/.cache/huggingface/lerobot/{repo-id}`.
- Training uses the camera/state/action shapes saved in the dataset, so the ACT config does not need hard-coded camera count or joint dimensions.
- Keep camera placement fixed between data collection and deployment.

More detail: [docs/DATASET_FORMAT.md](docs/DATASET_FORMAT.md).
