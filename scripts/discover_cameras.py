#!/usr/bin/env python
from __future__ import annotations

import argparse
import glob
import multiprocessing as mp
import os
import re
import time
from pathlib import Path
from queue import Empty
from typing import Any

import numpy as np
from PIL import Image


def _frame_stats(frame: np.ndarray) -> tuple[list[float], list[float]]:
    flat = frame.reshape(-1, frame.shape[-1])
    mean = [round(float(x), 2) for x in flat.mean(axis=0)]
    std = [round(float(x), 2) for x in flat.std(axis=0)]
    return mean, std


def _video_index(path: str) -> int:
    match = re.search(r"/dev/video(\d+)$", path)
    if match is None:
        return -1
    return int(match.group(1))


def _opencv_probe_worker(
    device: str,
    output_dir: str,
    width: int,
    height: int,
    fps: int,
    queue: mp.Queue,
) -> None:
    result: dict[str, Any] = {"device": device, "opened": False, "ok": False}
    cap = None
    try:
        import cv2  # type: ignore[import-not-found]

        cap = cv2.VideoCapture(device, cv2.CAP_V4L2)
        result["opened"] = bool(cap.isOpened())
        if not cap.isOpened():
            queue.put(result)
            return

        cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        cap.set(cv2.CAP_PROP_FPS, fps)

        frame = None
        for _ in range(8):
            ok, candidate = cap.read()
            if ok and candidate is not None:
                frame = candidate
                break
            time.sleep(0.1)

        result["actual_width"] = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        result["actual_height"] = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        result["actual_fps"] = round(float(cap.get(cv2.CAP_PROP_FPS)), 2)

        if frame is None:
            queue.put(result)
            return

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        output_path = Path(output_dir) / f"opencv__dev_video{_video_index(device)}.png"
        Image.fromarray(rgb).save(output_path)

        mean, std = _frame_stats(rgb)
        result.update(
            {
                "ok": True,
                "shape": list(rgb.shape),
                "mean": mean,
                "std": std,
                "flat": float(sum(std)) < 1.0,
                "saved": str(output_path),
            }
        )
        queue.put(result)
    except Exception as exc:
        result["error"] = repr(exc)
        queue.put(result)
    finally:
        if cap is not None:
            cap.release()


def probe_opencv_device(
    device: str,
    output_dir: Path,
    width: int,
    height: int,
    fps: int,
    timeout_s: float,
) -> dict[str, Any]:
    queue: mp.Queue = mp.Queue()
    process = mp.Process(
        target=_opencv_probe_worker,
        args=(device, str(output_dir), width, height, fps, queue),
    )
    process.start()
    process.join(timeout_s)
    if process.is_alive():
        process.terminate()
        process.join(1)
        return {"device": device, "opened": False, "ok": False, "timeout": True}

    try:
        return queue.get_nowait()
    except Empty:
        return {"device": device, "opened": False, "ok": False, "error": "No probe result returned."}


def discover_opencv(args: argparse.Namespace) -> None:
    devices = sorted(glob.glob("/dev/video*"), key=_video_index)
    print("--- OpenCV /dev/video discovery ---")
    if not devices:
        print("No /dev/video* devices found.")
        print()
        return

    by_path = sorted(glob.glob("/dev/v4l/by-path/*"))
    if by_path:
        print("Stable paths:")
        for link in by_path:
            try:
                target = os.path.realpath(link)
            except OSError:
                target = "unreadable"
            print(f"  {link} -> {target}")
        print()

    for device in devices:
        index = _video_index(device)
        print(f"index={index} path={device}")
        result = probe_opencv_device(
            device=device,
            output_dir=args.output_dir,
            width=args.width,
            height=args.height,
            fps=args.fps,
            timeout_s=args.timeout_s,
        )
        if result.get("timeout"):
            print(f"  timed out after {args.timeout_s}s while probing")
            continue
        if result.get("error"):
            print(f"  error={result['error']}")
            continue
        if not result.get("opened"):
            print("  could not open")
            continue
        if not result.get("ok"):
            print(
                "  opened but no frame "
                f"actual={result.get('actual_width')}x{result.get('actual_height')}@{result.get('actual_fps')}"
            )
            continue

        print(
            "  frame ok "
            f"actual={result['actual_width']}x{result['actual_height']}@{result['actual_fps']} "
            f"shape={tuple(result['shape'])}"
        )
        print(f"  saved={result['saved']}")
        print(f"  mean={result['mean']} std={result['std']}")
        if result.get("flat"):
            print("  WARNING: frame is nearly flat; do not use this as a normal RGB camera.")
    print()


def _zed_enum_member(enum_cls: Any, name: str) -> Any:
    return getattr(enum_cls, name)


def discover_zed_sdk(args: argparse.Namespace) -> None:
    print("--- ZED SDK discovery ---")
    try:
        import pyzed.sl as sl  # type: ignore[import-not-found]
    except ImportError as exc:
        print(f"pyzed is not installed: {exc}")
        print()
        return

    devices = list(sl.Camera.get_device_list())
    if not devices:
        print("No ZED SDK cameras found.")
        print()
        return

    for device in devices:
        serial_number = int(device.serial_number)
        camera_id = int(device.id)
        print(
            f"id={camera_id} serial_number={serial_number} "
            f"model={device.camera_model} state={device.camera_state} path={device.path}"
        )

        camera = sl.Camera()
        init = sl.InitParameters()
        init.camera_resolution = _zed_enum_member(sl.RESOLUTION, args.zed_resolution)
        init.depth_mode = sl.DEPTH_MODE.NONE
        init.camera_fps = int(args.fps)
        init.set_from_serial_number(serial_number)

        status = camera.open(init)
        if status != sl.ERROR_CODE.SUCCESS:
            print(f"  could not open through ZED SDK: {status}")
            continue

        try:
            runtime = sl.RuntimeParameters()
            deadline = time.perf_counter() + args.timeout_s
            last_status = None
            while time.perf_counter() <= deadline:
                last_status = camera.grab(runtime)
                if last_status == sl.ERROR_CODE.SUCCESS:
                    break
                time.sleep(0.01)
            else:
                print(f"  timed out waiting for ZED SDK frame: {last_status}")
                continue

            for side, view in (("left", sl.VIEW.LEFT), ("right", sl.VIEW.RIGHT)):
                mat = sl.Mat()
                camera.retrieve_image(mat, view)
                bgra = mat.get_data().copy()
                rgb = bgra[:, :, :3][:, :, ::-1]
                output_path = args.output_dir / f"zed_sdk_{side}.png"
                Image.fromarray(rgb).save(output_path)
                mean, std = _frame_stats(rgb)
                print(
                    f"  {side}: shape={rgb.shape} saved={output_path} "
                    f"mean={mean} std={std}"
                )
        finally:
            camera.close()
    print()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_dir", type=Path, default=Path("outputs/captured_images"))
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--timeout_s", type=float, default=2.0)
    parser.add_argument("--zed_resolution", default="HD1200")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    discover_opencv(args)
    discover_zed_sdk(args)
    print(f"Images saved in {args.output_dir}")


if __name__ == "__main__":
    main()
