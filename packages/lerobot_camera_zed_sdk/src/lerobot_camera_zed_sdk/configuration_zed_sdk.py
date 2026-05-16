from dataclasses import dataclass

from lerobot.cameras.configs import CameraConfig, ColorMode


_RESOLUTION_SIZES = {
    "HD2K": (2208, 1242),
    "HD1200": (1920, 1200),
    "HD1080": (1920, 1080),
    "HD720": (1280, 720),
    "VGA": (672, 376),
}


@CameraConfig.register_subclass("zed_sdk")
@dataclass(kw_only=True)
class ZedSdkCameraConfig(CameraConfig):
    """Camera config for one view from a Stereolabs ZED SDK camera.

    Configure two LeRobot cameras with the same serial number and different sides
    ("left" and "right") to record synchronized stereo images from one ZED.
    """

    side: str = "left"
    serial_number: int | None = None
    camera_id: int | None = None
    resolution: str = "HD1200"
    depth_mode: str = "NONE"
    color_mode: ColorMode = ColorMode.RGB
    warmup_s: float = 0.5
    timeout_ms: int = 2000

    def __post_init__(self) -> None:
        self.side = self.side.lower()
        if self.side not in {"left", "right"}:
            raise ValueError("ZedSdkCameraConfig.side must be 'left' or 'right'.")

        self.resolution = self.resolution.upper()
        if self.width is None or self.height is None:
            try:
                self.width, self.height = _RESOLUTION_SIZES[self.resolution]
            except KeyError as exc:
                raise ValueError(
                    f"Set width/height for unsupported ZED resolution '{self.resolution}'."
                ) from exc

        self.depth_mode = self.depth_mode.upper()
        self.color_mode = ColorMode(self.color_mode)
