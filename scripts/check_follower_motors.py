#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os

from lerobot_robot_seeed_b601 import (
    SeeedB601DMFollower,
    SeeedB601DMFollowerConfig,
    SeeedB601RSFollower,
    SeeedB601RSFollowerConfig,
)


class NoConfigureDMFollower(SeeedB601DMFollower):
    def configure(self) -> None:
        print("Skipping mode configuration; polling feedback only.", flush=True)


class NoConfigureRSFollower(SeeedB601RSFollower):
    def configure(self) -> None:
        print("Skipping mode configuration; polling feedback only.", flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Poll B601 follower motor feedback without commanding movement.")
    parser.add_argument("--type", default=os.environ.get("ROBOT_TYPE", "seeed_b601_dm_follower"))
    parser.add_argument("--port", default=os.environ.get("ROBOT_PORT", ""))
    parser.add_argument("--id", default=os.environ.get("ROBOT_ID", "follower1"))
    parser.add_argument("--can-adapter", default=os.environ.get("ROBOT_CAN_ADAPTER", "damiao"))
    parser.add_argument("--dm-serial-baud", type=int, default=int(os.environ.get("ROBOT_DM_SERIAL_BAUD", "921600")))
    parser.add_argument("--polls", type=int, default=int(os.environ.get("FOLLOWER_MOTOR_CHECK_POLLS", "1")))
    parser.add_argument(
        "--poll-interval-s",
        type=float,
        default=float(os.environ.get("FOLLOWER_MOTOR_CHECK_POLL_INTERVAL_S", "0.05")),
    )
    parser.add_argument("--require-all", action="store_true", default=os.environ.get("FOLLOWER_MOTOR_CHECK_REQUIRE_ALL", "").lower() in {"1", "true", "yes", "on"})
    return parser.parse_args()


def make_follower(args: argparse.Namespace):
    if not args.port:
        raise SystemExit("Missing follower port. Set ROBOT_PORT or pass --port.")

    common = {
        "id": args.id,
        "port": args.port,
        "can_adapter": args.can_adapter,
        "dm_serial_baud": args.dm_serial_baud,
        "cameras": {},
    }
    if args.type == "seeed_b601_dm_follower":
        return NoConfigureDMFollower(SeeedB601DMFollowerConfig(**common))
    if args.type == "seeed_b601_rs_follower":
        return NoConfigureRSFollower(SeeedB601RSFollowerConfig(**common))

    raise SystemExit(f"Unsupported follower type for this diagnostic: {args.type}")


def main() -> int:
    args = parse_args()
    print(
        f"Follower motor check: type={args.type} port={args.port} "
        f"can_adapter={args.can_adapter} dm_serial_baud={args.dm_serial_baud}",
        flush=True,
    )

    robot = make_follower(args)
    try:
        robot.connect(calibrate=False)
        for poll_idx in range(max(args.polls, 1)):
            for motor_name, motor in robot.motors.items():
                try:
                    motor.request_feedback()
                    if poll_idx == 0:
                        print(f"requested {motor_name}", flush=True)
                except Exception as exc:
                    print(f"request FAIL {motor_name}: {exc!r}", flush=True)

            try:
                robot.bus.poll_feedback_once()
                print(f"poll {poll_idx + 1}/{max(args.polls, 1)} ok", flush=True)
            except Exception as exc:
                print(f"poll {poll_idx + 1}/{max(args.polls, 1)} FAIL: {exc!r}", flush=True)

            if poll_idx + 1 < max(args.polls, 1):
                import time

                time.sleep(args.poll_interval_s)

        seen = []
        for motor_name, motor in robot.motors.items():
            state = motor.get_state()
            if state is None:
                print(f"state {motor_name}: None", flush=True)
                continue
            seen.append(motor_name)
            print(
                f"state {motor_name}: pos={state.pos:.6f} "
                f"vel={state.vel:.6f} torque={state.torq:.6f}",
                flush=True,
            )

        if seen:
            print(f"states seen: {', '.join(seen)}", flush=True)
            missing = [motor_name for motor_name in robot.motors if motor_name not in seen]
            if missing:
                print(f"states missing: {', '.join(missing)}", flush=True)
                if args.require_all:
                    return 1
            return 0

        print("states seen: none", flush=True)
        return 1
    finally:
        try:
            robot.disconnect()
        except Exception as exc:
            print(f"disconnect skipped/failed: {exc!r}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
