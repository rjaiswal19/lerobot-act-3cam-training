#!/usr/bin/env python
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import draccus
import numpy as np
from PIL import Image

from lerobot.cameras import CameraConfig, make_cameras_from_configs
from lerobot.cameras.opencv import OpenCVCameraConfig  # noqa: F401
from lerobot.cameras.reachy2_camera import Reachy2CameraConfig  # noqa: F401
from lerobot.cameras.realsense import RealSenseCameraConfig  # noqa: F401
from lerobot.cameras.zmq import ZMQCameraConfig  # noqa: F401
from lerobot.utils.import_utils import register_third_party_plugins


@dataclass
class CameraCheckConfig:
    cameras: dict[str, CameraConfig]
    output_dir: Path = field(default_factory=lambda: Path("outputs/captured_images"))
    timeout_ms: int = 5000


def main() -> None:
    register_third_party_plugins()
    cfg = draccus.parse(CameraCheckConfig)

    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    cameras = make_cameras_from_configs(cfg.cameras)

    try:
        for name, camera in cameras.items():
            print(f"Connecting configured camera {name}: {camera}")
            camera.connect()

        for name, camera in cameras.items():
            frame = camera.async_read(timeout_ms=cfg.timeout_ms)
            frame = np.asarray(frame)
            path = cfg.output_dir / f"configured_{name}.png"
            Image.fromarray(frame).save(path)

            flat = frame.reshape(-1, frame.shape[-1])
            mean = flat.mean(axis=0)
            std = flat.std(axis=0)
            print(
                f"Saved {path}: shape={frame.shape} "
                f"mean={[round(float(x), 2) for x in mean]} "
                f"std={[round(float(x), 2) for x in std]}"
            )
            if float(std.sum()) < 1.0:
                print(f"WARNING: {name} looks almost flat; check this camera image.")
    finally:
        for camera in cameras.values():
            if camera.is_connected:
                camera.disconnect()


if __name__ == "__main__":
    main()
