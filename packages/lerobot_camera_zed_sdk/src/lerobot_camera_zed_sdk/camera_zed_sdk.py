from __future__ import annotations

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import numpy as np
from lerobot.cameras.camera import Camera
from lerobot.cameras.configs import ColorMode
from lerobot.utils.errors import DeviceAlreadyConnectedError, DeviceNotConnectedError
from numpy.typing import NDArray

from .configuration_zed_sdk import ZedSdkCameraConfig


logger = logging.getLogger(__name__)


def _import_zed_sdk():
    try:
        import pyzed.sl as sl  # type: ignore[import-not-found]
    except ImportError as exc:
        raise ImportError(
            "pyzed is not installed in this Python environment. "
            "Install the ZED SDK Python API wheel for this venv."
        ) from exc
    return sl


def _enum_member(enum_cls: Any, name: str, field_name: str) -> Any:
    try:
        return getattr(enum_cls, name)
    except AttributeError as exc:
        available = [key for key in dir(enum_cls) if key.isupper()]
        raise ValueError(f"Unsupported ZED {field_name} '{name}'. Available: {available}") from exc


class _ZedSession:
    _sessions: dict[tuple[int | None, int | None, str, int | None, str], "_ZedSession"] = {}
    _sessions_lock = threading.Lock()

    @classmethod
    def key_from_config(cls, config: ZedSdkCameraConfig) -> tuple[int | None, int | None, str, int | None, str]:
        return (
            config.serial_number,
            config.camera_id,
            config.resolution,
            config.fps,
            config.depth_mode,
        )

    @classmethod
    def acquire(cls, config: ZedSdkCameraConfig) -> "_ZedSession":
        key = cls.key_from_config(config)
        with cls._sessions_lock:
            session = cls._sessions.get(key)
            if session is None:
                session = cls(config)
                cls._sessions[key] = session
            session._ref_count += 1
        session.open()
        return session

    def __init__(self, config: ZedSdkCameraConfig):
        self.config = config
        self.key = self.key_from_config(config)
        self._ref_count = 0
        self._lock = threading.RLock()
        self._sl = None
        self._camera = None
        self._runtime = None
        self._mats: dict[str, Any] = {}
        self._frames: dict[str, NDArray[np.uint8]] = {}
        self._fresh_sides: set[str] = set()
        self._postprocess_executor: ThreadPoolExecutor | None = None
        self._latest_t = 0.0

    @property
    def is_open(self) -> bool:
        return self._camera is not None

    def open(self) -> None:
        with self._lock:
            if self._camera is not None:
                return

            sl = _import_zed_sdk()
            init = sl.InitParameters()
            init.camera_resolution = _enum_member(sl.RESOLUTION, self.config.resolution, "resolution")
            init.depth_mode = _enum_member(sl.DEPTH_MODE, self.config.depth_mode, "depth_mode")
            if self.config.fps is not None:
                init.camera_fps = int(self.config.fps)
            if self.config.serial_number is not None:
                init.set_from_serial_number(int(self.config.serial_number))
            if self.config.camera_id is not None:
                init.set_from_camera_id(int(self.config.camera_id))

            camera = sl.Camera()
            status = camera.open(init)
            if status != sl.ERROR_CODE.SUCCESS:
                raise ConnectionError(f"Failed to open ZED SDK camera {self.key}: {status}")

            self._sl = sl
            self._camera = camera
            self._runtime = sl.RuntimeParameters()
            self._mats = {"left": sl.Mat(), "right": sl.Mat()}
            self._frames = {}
            self._fresh_sides = set()
            self._postprocess_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="zed-post")

            warmup_deadline = time.perf_counter() + max(self.config.warmup_s, 0.0)
            while time.perf_counter() < warmup_deadline:
                self._grab_locked(
                    timeout_ms=self.config.timeout_ms,
                    color_mode=self.config.color_mode,
                    width=self.config.width,
                    height=self.config.height,
                )

            logger.info("Connected ZED SDK camera %s", self.key)

    def release(self) -> None:
        with self._sessions_lock:
            self._ref_count -= 1
            if self._ref_count > 0:
                return
            self._sessions.pop(self.key, None)

        with self._lock:
            if self._camera is not None:
                self._camera.close()
            if self._postprocess_executor is not None:
                self._postprocess_executor.shutdown(wait=True)
            self._camera = None
            self._runtime = None
            self._mats = {}
            self._frames = {}
            self._fresh_sides = set()
            self._postprocess_executor = None
            self._latest_t = 0.0

    @staticmethod
    def _prepare_frame(
        frame: NDArray[np.uint8],
        color_mode: ColorMode,
        width: int | None,
        height: int | None,
    ) -> NDArray[np.uint8]:
        if frame.shape[2] == 4:
            frame = frame[:, :, :3]

        if color_mode == ColorMode.RGB:
            frame = frame[:, :, ::-1]

        if height is not None and width is not None and frame.shape[:2] != (height, width):
            import cv2  # type: ignore[import-not-found]

            frame = cv2.resize(frame, (width, height), interpolation=cv2.INTER_AREA)

        frame = np.ascontiguousarray(frame)
        return frame if frame.flags.owndata else frame.copy()

    def _grab_locked(
        self,
        timeout_ms: int,
        color_mode: ColorMode,
        width: int | None = None,
        height: int | None = None,
    ) -> None:
        if self._camera is None or self._runtime is None or self._sl is None:
            raise DeviceNotConnectedError("ZED SDK camera is not connected.")
        if self._postprocess_executor is None:
            raise DeviceNotConnectedError("ZED SDK postprocess executor is not available.")

        deadline = time.perf_counter() + timeout_ms / 1000.0
        last_status = None
        while time.perf_counter() <= deadline:
            last_status = self._camera.grab(self._runtime)
            if last_status == self._sl.ERROR_CODE.SUCCESS:
                break
            time.sleep(0.001)
        else:
            raise TimeoutError(f"Timed out waiting for ZED SDK frame: {last_status}")

        if width is not None and height is not None:
            retrieve_resolution = self._sl.Resolution(int(width), int(height))
            self._camera.retrieve_image(
                self._mats["left"], self._sl.VIEW.LEFT_BGR, self._sl.MEM.CPU, retrieve_resolution
            )
            self._camera.retrieve_image(
                self._mats["right"], self._sl.VIEW.RIGHT_BGR, self._sl.MEM.CPU, retrieve_resolution
            )
        else:
            self._camera.retrieve_image(self._mats["left"], self._sl.VIEW.LEFT_BGR)
            self._camera.retrieve_image(self._mats["right"], self._sl.VIEW.RIGHT_BGR)
        left_raw = self._mats["left"].get_data(deep_copy=False)
        right_raw = self._mats["right"].get_data(deep_copy=False)
        left_future = self._postprocess_executor.submit(
            self._prepare_frame, left_raw, color_mode, width, height
        )
        right_future = self._postprocess_executor.submit(
            self._prepare_frame, right_raw, color_mode, width, height
        )
        self._frames = {"left": left_future.result(), "right": right_future.result()}
        self._fresh_sides = {"left", "right"}
        self._latest_t = time.perf_counter()

    def get_frame(
        self,
        side: str,
        color_mode: ColorMode,
        width: int | None,
        height: int | None,
        timeout_ms: int,
    ) -> NDArray[np.uint8]:
        with self._lock:
            if side not in self._fresh_sides:
                self._grab_locked(timeout_ms=timeout_ms, color_mode=color_mode, width=width, height=height)

            self._fresh_sides.discard(side)
            return self._frames[side]


class ZedSdkCamera(Camera):
    def __init__(self, config: ZedSdkCameraConfig):
        super().__init__(config)
        self.config = config
        self._session: _ZedSession | None = None

    def __str__(self) -> str:
        target = self.config.serial_number if self.config.serial_number is not None else self.config.camera_id
        return f"ZedSdkCamera({target}, {self.config.side})"

    @property
    def is_connected(self) -> bool:
        return self._session is not None and self._session.is_open

    @staticmethod
    def find_cameras() -> list[dict[str, Any]]:
        sl = _import_zed_sdk()
        cameras = []
        for device in sl.Camera.get_device_list():
            cameras.append(
                {
                    "name": str(device.camera_model),
                    "type": "ZED SDK",
                    "id": int(device.id),
                    "serial_number": int(device.serial_number),
                    "path": str(device.path),
                    "state": str(device.camera_state),
                }
            )
        return cameras

    def connect(self, warmup: bool = True) -> None:
        if self.is_connected:
            raise DeviceAlreadyConnectedError(f"{self} already connected.")

        warmup_s = self.config.warmup_s
        if not warmup:
            self.config.warmup_s = 0.0
        try:
            self._session = _ZedSession.acquire(self.config)
        finally:
            self.config.warmup_s = warmup_s

    def read(self) -> NDArray[np.uint8]:
        return self.async_read(timeout_ms=self.config.timeout_ms)

    def async_read(self, timeout_ms: float = 200) -> NDArray[np.uint8]:
        if not self.is_connected or self._session is None:
            raise DeviceNotConnectedError(f"{self} is not connected.")

        timeout = int(timeout_ms) if timeout_ms is not None else self.config.timeout_ms
        timeout = max(timeout, self.config.timeout_ms)
        return self._session.get_frame(
            side=self.config.side,
            color_mode=self.config.color_mode,
            width=self.width,
            height=self.height,
            timeout_ms=timeout,
        )

    def read_latest(self, max_age_ms: int = 500) -> NDArray[np.uint8]:
        return self.async_read(timeout_ms=max_age_ms)

    def disconnect(self) -> None:
        if self._session is None:
            raise DeviceNotConnectedError(f"{self} is not connected.")
        self._session.release()
        self._session = None
