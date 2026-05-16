# LeRobot Dataset Format For This Setup

You were remembering the right thing: LeRobot uses Parquet.

For this setup, the data flow is:

```text
robot + cameras
  -> lerobot-record
  -> LeRobotDataset folder / Hugging Face dataset repo
  -> lerobot-train --policy.type="$POLICY_TYPE"
```

## What Gets Stored

LeRobotDataset v3 stores low-dimensional signals and camera video separately:

```text
meta/
  info.json          dataset schema: feature names, dtypes, shapes, fps
  stats.json         normalization stats
  tasks.jsonl        task text mapped to task ids
  episodes/          episode boundaries and offsets

data/
  *.parquet          tabular frame data:
                    observation.state
                    action
                    timestamp
                    episode/frame indices
                    task ids

videos/
  wrist/*.mp4        wrist camera frames
  zed_left/*.mp4     ZED left RGB frames
  zed_right/*.mp4    ZED right RGB frames
```

The exact shard filenames may vary by LeRobot version. Use the folder names above as the mental model.

## What The Policy Reads

During training, the policy receives samples like:

```text
observation.state
observation.images.wrist
observation.images.zed_left
observation.images.zed_right
action
```

The camera count, image shapes, joint-state dimension, and action dimension are inferred from the dataset metadata.

That is why `scripts/train_policy.sh` only needs:

```bash
--dataset.repo_id="$HF_USER_OR_ORG/$DATASET_NAME"
--policy.type="$POLICY_TYPE"
```

## What You Need To Fill

You only fill the real-world capture parameters in `configs/local.env`:

```text
ROBOT_PORT
TELEOP_PORT
WRIST_CAMERA_INDEX
ZED_LEFT_CAMERA_INDEX
ZED_RIGHT_CAMERA_INDEX
TASK_DESCRIPTION
HF_USER_OR_ORG
```

After that, `lerobot-record` builds the Parquet/video/meta dataset automatically.

## When Would You Manually Create Parquet?

Only if you are importing an existing dataset that was recorded outside LeRobot.

For your setup, the normal path is easier:

```bash
make record pour
make train pour
```
