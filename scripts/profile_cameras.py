#!/usr/bin/env python3
from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass, field

import draccus
import numpy as np

from lerobot.cameras import CameraConfig, make_cameras_from_configs
from lerobot.cameras.opencv import OpenCVCameraConfig  # noqa: F401
from lerobot.cameras.reachy2_camera import Reachy2CameraConfig  # noqa: F401
from lerobot.cameras.realsense import RealSenseCameraConfig  # noqa: F401
from lerobot.cameras.zmq import ZMQCameraConfig  # noqa: F401
from lerobot.utils.import_utils import register_third_party_plugins
from lerobot.utils.robot_utils import precise_sleep
from lerobot.utils.visualization_utils import init_rerun, log_rerun_data, shutdown_rerun


@dataclass
class CameraProfileConfig:
    cameras: dict[str, CameraConfig]
    fps: int = 10
    iterations: int = 20
    warmup: int = 3
    timeout_ms: int = 5000
    display_data: bool = False
    display_ip: str | None = None
    display_port: int | None = None
    display_compressed_images: bool = False
    sleep_to_fps: bool = True


def elapsed_ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000.0


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = (len(ordered) - 1) * pct
    lower = int(idx)
    upper = min(lower + 1, len(ordered) - 1)
    weight = idx - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def add_sample(samples: dict[str, list[float]], name: str, value: float, counted: bool) -> None:
    if counted:
        samples[name].append(value)


def print_summary(samples: dict[str, list[float]], shapes: dict[str, tuple[int, ...]], cfg: CameraProfileConfig) -> None:
    budget_ms = 1000.0 / cfg.fps
    loop_values = samples.get("loop.total_ms", [])
    mean_loop = sum(loop_values) / len(loop_values) if loop_values else 0.0
    actual_hz = 1000.0 / mean_loop if mean_loop else 0.0

    print()
    print(f"Camera timing profile ({len(loop_values)} measured loops, {cfg.warmup} warmup loops)")
    print(f"Target: {cfg.fps} FPS -> {budget_ms:.1f} ms budget per loop")
    print(f"Measured loop: mean={mean_loop:.1f} ms -> {actual_hz:.2f} Hz")
    print(
        f"display_data={cfg.display_data} "
        f"display_compressed_images={cfg.display_compressed_images}"
    )
    print()
    if shapes:
        print("Frame shapes:")
        for name, shape in shapes.items():
            print(f"  {name}: {shape}")
        print()

    print(f"{'component':34s} {'mean':>8s} {'p50':>8s} {'p95':>8s} {'max':>8s}")
    print("-" * 70)
    for name in sorted(samples):
        values = samples[name]
        mean = sum(values) / len(values)
        print(
            f"{name:34s} "
            f"{mean:8.1f} "
            f"{percentile(values, 0.50):8.1f} "
            f"{percentile(values, 0.95):8.1f} "
            f"{max(values):8.1f}"
        )


def main() -> int:
    register_third_party_plugins()
    cfg = draccus.parse(CameraProfileConfig)

    cameras = make_cameras_from_configs(cfg.cameras)
    samples: dict[str, list[float]] = defaultdict(list)
    shapes: dict[str, tuple[int, ...]] = {}
    rerun_started = False

    try:
        if cfg.display_data:
            init_rerun("camera_profile", ip=cfg.display_ip, port=cfg.display_port)
            rerun_started = True

        for name, camera in cameras.items():
            print(f"Connecting camera {name}: {camera}", flush=True)
            camera.connect()

        total_loops = cfg.warmup + cfg.iterations
        budget_s = 1.0 / cfg.fps
        print(f"Profiling {cfg.iterations} loops after {cfg.warmup} warmup loops...", flush=True)

        for index in range(total_loops):
            counted = index >= cfg.warmup
            loop_start = time.perf_counter()
            observation: dict[str, np.ndarray] = {}

            for name, camera in cameras.items():
                start = time.perf_counter()
                frame = np.asarray(camera.async_read(timeout_ms=cfg.timeout_ms))
                dt = elapsed_ms(start)
                observation[name] = frame
                shapes.setdefault(name, frame.shape)
                add_sample(samples, f"camera.{name}_ms", dt, counted)

            add_sample(samples, "camera.total_ms", elapsed_ms(loop_start), counted)

            if cfg.display_data:
                start = time.perf_counter()
                log_rerun_data(
                    observation=observation,
                    action=None,
                    compress_images=cfg.display_compressed_images,
                )
                add_sample(samples, "display.log_rerun_data_ms", elapsed_ms(start), counted)

            loop_dt = time.perf_counter() - loop_start
            add_sample(samples, "loop.total_ms", loop_dt * 1000.0, counted)
            if cfg.sleep_to_fps:
                precise_sleep(max(budget_s - loop_dt, 0.0))

        print_summary(samples, shapes, cfg)
        return 0
    finally:
        for camera in cameras.values():
            if camera.is_connected:
                camera.disconnect()
        if rerun_started:
            try:
                shutdown_rerun()
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
