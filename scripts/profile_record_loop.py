#!/usr/bin/env python3
from __future__ import annotations

import math
import queue
import tempfile
import threading
import time
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import draccus

from lerobot.cameras import CameraConfig
from lerobot.cameras.opencv import OpenCVCameraConfig  # noqa: F401
from lerobot.cameras.reachy2_camera import Reachy2CameraConfig  # noqa: F401
from lerobot.cameras.realsense import RealSenseCameraConfig  # noqa: F401
from lerobot.cameras.zmq import ZMQCameraConfig  # noqa: F401
from lerobot.configs.video import VideoEncoderConfig
from lerobot.datasets import LeRobotDataset, aggregate_pipeline_dataset_features, create_initial_features
from lerobot.processor import make_default_processors
from lerobot.robots import make_robot_from_config
from lerobot.teleoperators import make_teleoperator_from_config
from lerobot.utils.constants import ACTION, OBS_STR
from lerobot.utils.feature_utils import build_dataset_frame, combine_feature_dicts
from lerobot.utils.import_utils import register_third_party_plugins
from lerobot.utils.robot_utils import precise_sleep
from lerobot.utils.visualization_utils import init_rerun, log_rerun_data, shutdown_rerun

from lerobot_robot_seeed_b601 import (  # noqa: F401
    SeeedB601DMFollowerConfig,
    SeeedB601RSFollowerConfig,
)
from lerobot_teleoperator_rebot_arm_102 import RebotArm102LeaderConfig  # noqa: F401


@dataclass
class ProfileConfig:
    robot_type: str
    robot_port: str
    robot_id: str
    teleop_type: str
    teleop_port: str
    teleop_id: str
    cameras: dict[str, CameraConfig] = field(default_factory=dict)
    robot_can_adapter: str = "damiao"
    robot_dm_serial_baud: int = 921600
    teleop_baudrate: int = 1_000_000
    teleop_joint_directions: dict[str, int] = field(default_factory=dict)
    fps: int = 5
    iterations: int = 20
    warmup: int = 3
    send_action: bool = True
    include_dataset: bool = True
    streaming_encoding: bool = False
    encoder_threads: int | None = None
    camera_encoder_vcodec: str | None = None
    camera_encoder_preset: str | None = None
    image_writer_processes: int = 0
    image_writer_threads_per_camera: int = 4
    display_data: bool = False
    display_ip: str | None = None
    display_port: int | None = None
    display_compressed_images: bool = False
    async_display: bool = True
    sleep_to_fps: bool = True


def make_robot_config(cfg: ProfileConfig):
    common = {
        "id": cfg.robot_id,
        "port": cfg.robot_port,
        "can_adapter": cfg.robot_can_adapter,
        "dm_serial_baud": cfg.robot_dm_serial_baud,
        "cameras": cfg.cameras,
    }
    if cfg.robot_type == "seeed_b601_dm_follower":
        return SeeedB601DMFollowerConfig(**common)
    if cfg.robot_type == "seeed_b601_rs_follower":
        return SeeedB601RSFollowerConfig(**common)
    raise ValueError(f"Unsupported robot_type for profiler: {cfg.robot_type}")


def make_teleop_config(cfg: ProfileConfig):
    if cfg.teleop_type != "rebot_arm_102_leader":
        raise ValueError(f"Unsupported teleop_type for profiler: {cfg.teleop_type}")

    kwargs: dict[str, Any] = {
        "id": cfg.teleop_id,
        "port": cfg.teleop_port,
        "baudrate": cfg.teleop_baudrate,
    }
    if cfg.teleop_joint_directions:
        kwargs["joint_directions"] = cfg.teleop_joint_directions
    return RebotArm102LeaderConfig(**kwargs)


def elapsed_ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000.0


class AsyncRerunLogger:
    def __init__(self, compress_images: bool):
        self.compress_images = compress_images
        self.queue: queue.Queue = queue.Queue(maxsize=1)
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, name="profile-rerun-display", daemon=True)
        self.dropped_frames = 0

    def start(self) -> None:
        self.thread.start()

    def submit(self, observation: dict[str, Any], action: dict[str, Any] | None) -> None:
        item = (dict(observation), dict(action) if action is not None else None)
        while True:
            try:
                self.queue.put_nowait(item)
                return
            except queue.Full:
                try:
                    self.queue.get_nowait()
                    self.queue.task_done()
                    self.dropped_frames += 1
                except queue.Empty:
                    pass

    def close(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=2.0)

    def _run(self) -> None:
        while not self.stop_event.is_set() or not self.queue.empty():
            try:
                observation, action = self.queue.get(timeout=0.1)
            except queue.Empty:
                continue
            try:
                log_rerun_data(
                    observation=observation,
                    action=action,
                    compress_images=self.compress_images,
                )
            finally:
                self.queue.task_done()


def read_observation_timed(robot) -> tuple[dict[str, Any], dict[str, float]]:
    timings: dict[str, float] = {}
    obs: dict[str, Any] = {}
    total_start = time.perf_counter()

    start = time.perf_counter()
    for motor in robot.motors.values():
        motor.request_feedback()
    timings["follower.request_feedback_ms"] = elapsed_ms(start)

    start = time.perf_counter()
    try:
        robot.bus.poll_feedback_once()
    except Exception:
        pass
    timings["follower.poll_feedback_ms"] = elapsed_ms(start)

    start = time.perf_counter()
    for motor_name, motor in robot.motors.items():
        state = motor.get_state()
        if state is not None:
            obs[f"{motor_name}.pos"] = math.degrees(state.pos)
            obs[f"{motor_name}.vel"] = math.degrees(state.vel)
            obs[f"{motor_name}.torque"] = state.torq
        else:
            obs[f"{motor_name}.pos"] = 0.0
            obs[f"{motor_name}.vel"] = 0.0
            obs[f"{motor_name}.torque"] = 0.0
    timings["follower.parse_state_ms"] = elapsed_ms(start)
    timings["follower.total_ms"] = (
        timings["follower.request_feedback_ms"]
        + timings["follower.poll_feedback_ms"]
        + timings["follower.parse_state_ms"]
    )

    camera_total = 0.0
    for cam_key, cam in robot.cameras.items():
        start = time.perf_counter()
        obs[cam_key] = cam.async_read()
        dt = elapsed_ms(start)
        timings[f"camera.{cam_key}_ms"] = dt
        camera_total += dt
    timings["camera.total_ms"] = camera_total
    timings["observation.total_ms"] = elapsed_ms(total_start)
    return obs, timings


def make_profile_dataset(cfg: ProfileConfig, robot, tmpdir: Path):
    teleop_action_processor, robot_action_processor, robot_observation_processor = make_default_processors()
    dataset_features = combine_feature_dicts(
        aggregate_pipeline_dataset_features(
            pipeline=teleop_action_processor,
            initial_features=create_initial_features(action=robot.action_features),
            use_videos=True,
        ),
        aggregate_pipeline_dataset_features(
            pipeline=robot_observation_processor,
            initial_features=create_initial_features(observation=robot.observation_features),
            use_videos=True,
        ),
    )
    dataset_root = tmpdir / "dataset"
    camera_encoder = (
        VideoEncoderConfig(vcodec=cfg.camera_encoder_vcodec, preset=cfg.camera_encoder_preset)
        if cfg.camera_encoder_vcodec
        else None
    )
    dataset = LeRobotDataset.create(
        "profile/record_loop_profile",
        cfg.fps,
        root=dataset_root,
        robot_type=robot.name,
        features=dataset_features,
        use_videos=True,
        image_writer_processes=cfg.image_writer_processes,
        image_writer_threads=cfg.image_writer_threads_per_camera * len(robot.cameras),
        camera_encoder=camera_encoder,
        streaming_encoding=cfg.streaming_encoding,
        encoder_threads=cfg.encoder_threads,
    )
    return dataset, teleop_action_processor, robot_action_processor, robot_observation_processor


def add_sample(samples: dict[str, list[float]], name: str, value: float, counted: bool) -> None:
    if counted:
        samples[name].append(value)


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = (len(ordered) - 1) * pct
    lower = int(idx)
    upper = min(lower + 1, len(ordered) - 1)
    weight = idx - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def print_summary(samples: dict[str, list[float]], cfg: ProfileConfig) -> None:
    budget_ms = 1000.0 / cfg.fps
    loop_values = samples.get("loop.total_ms", [])
    mean_loop = sum(loop_values) / len(loop_values) if loop_values else 0.0
    actual_hz = 1000.0 / mean_loop if mean_loop else 0.0

    print()
    print(f"Record loop timing profile ({len(loop_values)} measured loops, {cfg.warmup} warmup loops)")
    print(f"Target: {cfg.fps} FPS -> {budget_ms:.1f} ms budget per loop")
    print(f"Measured loop: mean={mean_loop:.1f} ms -> {actual_hz:.2f} Hz")
    print(
        f"send_action={cfg.send_action} include_dataset={cfg.include_dataset} "
        f"streaming_encoding={cfg.streaming_encoding} "
        f"camera_encoder_vcodec={cfg.camera_encoder_vcodec or 'default'} "
        f"camera_encoder_preset={cfg.camera_encoder_preset or 'default'} "
        f"async_display={cfg.async_display}"
    )
    print()
    print(f"{'component':38s} {'mean':>8s} {'p50':>8s} {'p95':>8s} {'max':>8s}")
    print("-" * 74)

    order = [
        "loop.total_ms",
        "observation.total_ms",
        "follower.total_ms",
        "follower.request_feedback_ms",
        "follower.poll_feedback_ms",
        "follower.parse_state_ms",
        "camera.total_ms",
        "camera.wrist_ms",
        "camera.zed_left_ms",
        "camera.zed_right_ms",
        "observation_processor_ms",
        "dataset.build_observation_frame_ms",
        "teleop.get_action_ms",
        "teleop_action_processor_ms",
        "robot_action_processor_ms",
        "robot.send_action_ms",
        "dataset.build_action_frame_ms",
        "dataset.add_frame_ms",
        "display.submit_rerun_data_ms",
        "display.log_rerun_data_ms",
    ]
    for name in order:
        values = samples.get(name)
        if not values:
            continue
        mean = sum(values) / len(values)
        print(
            f"{name:38s} "
            f"{mean:8.1f} "
            f"{percentile(values, 0.50):8.1f} "
            f"{percentile(values, 0.95):8.1f} "
            f"{max(values):8.1f}"
        )


def main() -> int:
    register_third_party_plugins()
    cfg = draccus.parse(ProfileConfig)

    robot = make_robot_from_config(make_robot_config(cfg))
    teleop = make_teleoperator_from_config(make_teleop_config(cfg))

    samples: dict[str, list[float]] = defaultdict(list)
    tmp = tempfile.TemporaryDirectory(prefix="lerobot-record-loop-profile-")
    dataset = None
    rerun_started = False
    display_logger = AsyncRerunLogger(cfg.display_compressed_images) if cfg.display_data and cfg.async_display else None

    try:
        if cfg.display_data:
            init_rerun("record_loop_profile", ip=cfg.display_ip, port=cfg.display_port)
            rerun_started = True
            if display_logger is not None:
                display_logger.start()

        print("Connecting robot and teleop...")
        robot.connect(calibrate=False)
        teleop.connect(calibrate=False)

        (
            dataset,
            teleop_action_processor,
            robot_action_processor,
            robot_observation_processor,
        ) = make_profile_dataset(cfg, robot, Path(tmp.name))

        total_loops = cfg.warmup + cfg.iterations
        budget_s = 1.0 / cfg.fps
        print(f"Profiling {cfg.iterations} loops after {cfg.warmup} warmup loops...")
        for index in range(total_loops):
            counted = index >= cfg.warmup
            loop_start = time.perf_counter()

            obs, obs_timings = read_observation_timed(robot)
            for name, value in obs_timings.items():
                add_sample(samples, name, value, counted)

            start = time.perf_counter()
            obs_processed = robot_observation_processor(obs)
            add_sample(samples, "observation_processor_ms", elapsed_ms(start), counted)

            if cfg.include_dataset:
                start = time.perf_counter()
                observation_frame = build_dataset_frame(dataset.features, obs_processed, prefix=OBS_STR)
                add_sample(samples, "dataset.build_observation_frame_ms", elapsed_ms(start), counted)
            else:
                observation_frame = {}

            start = time.perf_counter()
            act = teleop.get_action()
            add_sample(samples, "teleop.get_action_ms", elapsed_ms(start), counted)

            start = time.perf_counter()
            action_values = teleop_action_processor((act, obs))
            add_sample(samples, "teleop_action_processor_ms", elapsed_ms(start), counted)

            start = time.perf_counter()
            robot_action_to_send = robot_action_processor((action_values, obs))
            add_sample(samples, "robot_action_processor_ms", elapsed_ms(start), counted)

            if cfg.send_action:
                start = time.perf_counter()
                robot.send_action(robot_action_to_send)
                add_sample(samples, "robot.send_action_ms", elapsed_ms(start), counted)

            if cfg.include_dataset:
                start = time.perf_counter()
                action_frame = build_dataset_frame(dataset.features, action_values, prefix=ACTION)
                add_sample(samples, "dataset.build_action_frame_ms", elapsed_ms(start), counted)

                start = time.perf_counter()
                dataset.add_frame({**observation_frame, **action_frame, "task": "record loop profile"})
                add_sample(samples, "dataset.add_frame_ms", elapsed_ms(start), counted)

            if cfg.display_data:
                start = time.perf_counter()
                if display_logger is not None:
                    display_logger.submit(observation=obs_processed, action=action_values)
                    add_sample(samples, "display.submit_rerun_data_ms", elapsed_ms(start), counted)
                else:
                    log_rerun_data(
                        observation=obs_processed,
                        action=action_values,
                        compress_images=cfg.display_compressed_images,
                    )
                    add_sample(samples, "display.log_rerun_data_ms", elapsed_ms(start), counted)

            loop_dt = time.perf_counter() - loop_start
            add_sample(samples, "loop.total_ms", loop_dt * 1000.0, counted)
            if cfg.sleep_to_fps:
                precise_sleep(max(budget_s - loop_dt, 0.0))

        print_summary(samples, cfg)
        return 0
    finally:
        if display_logger is not None:
            display_logger.close()
            print(f"Async display dropped {display_logger.dropped_frames} frame(s).")
        if dataset is not None:
            try:
                dataset.clear_episode_buffer(delete_images=True)
            except Exception:
                pass
            try:
                dataset.finalize()
            except Exception:
                pass
        if robot.is_connected:
            robot.disconnect()
        if teleop.is_connected:
            teleop.disconnect()
        if rerun_started:
            try:
                shutdown_rerun()
            except Exception:
                pass
        tmp.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
