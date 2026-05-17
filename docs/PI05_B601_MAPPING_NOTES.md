# Pi0.5 Base to Seeed B601 Mapping Notes

## Finding

Do not drive the Seeed B601 arm directly from `lerobot/pi05_base`.

`lerobot/pi05_base` declares `observation.state` and `action` as 32-dimensional
features. The local B601 follower exposes 7 action features:

1. `shoulder_pan.pos`
2. `shoulder_lift.pos`
3. `elbow_flex.pos`
4. `wrist_flex.pos`
5. `wrist_yaw.pos`
6. `wrist_roll.pos`
7. `gripper.pos`

The B601 driver expects those values as absolute joint targets in degrees. The
OpenPI/Pi base action convention uses robot-specific action spaces; the common
first-arm convention is six joint angles in radians plus a normalized gripper.
The Pi0.5 paper also describes fixed-size padded action vectors normalized per
dataset. That means taking the first 7 values from `pi05_base` and sending them
as B601 degrees is not a valid action transform.

## What Was Wrong

The previous async rollout path did this:

```python
{key: action_tensor[i].item() for i, key in enumerate(self.robot.action_features)}
```

For a 32-dimensional Pi0.5 base action, this silently used the first 7 values as
B601 degree targets. This explains why the rollout barely approached the blue
beaker: if those values are radian-scale or normalized gripper-scale outputs,
they are tiny or semantically wrong as B601 absolute degree commands.

## Guardrails Added

The async client now refuses implicit first-N mapping when policy action
dimensionality and robot action dimensionality differ.

The sync rollout utility now also refuses to convert a policy tensor whose size
does not exactly match the robot/dataset action schema.

The Pi0.5 base zero-shot scripts refuse physical execution of
`lerobot/pi05_base`. They are still useful for dry-run and server plumbing
checks, but physical execution needs one of:

1. A Pi0.5 checkpoint fine-tuned on the B601 action schema.
2. A verified robot-specific action transform with correct action order, units,
   gripper scale, and safety limits.
3. A non-VLA classical pick/place controller for the initial color-only demo.

## Prompt

The blue/yellow/green handoff prompts now target the actual handoff location:

`Pick up the <color> beaker and place it on the back-left corner of the white pad from the robot's perspective`

The previous prompt said `black base`, which was inconsistent with the current
workspace target. This prompt fix matters after the action path is corrected,
but it was not the primary reason for the failed motion.

## Duration

The async client now supports `run_duration_starts_on_first_action`. The
zero-shot async script enables it by default so a six-second rollout means six
seconds after the first executable action arrives, not six seconds including the
initial Pi0.5 inference latency.
