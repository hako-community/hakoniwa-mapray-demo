#!/usr/bin/env python3
"""Drive the Phase W1 drone through a known Shibuya building wall."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

import hakoniwa_pdu.apps.drone.hakosim as hakosim


def pose_dict(pose: Any) -> dict[str, Any] | None:
    if pose is None:
        return None
    p = pose.position
    q = pose.orientation
    return {
        "position": {"x": p.x_val, "y": p.y_val, "z": p.z_val},
        "orientation": {
            "x": q.x_val,
            "y": q.y_val,
            "z": q.z_val,
            "w": q.w_val,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--robot", default="Drone")
    parser.add_argument("--takeoff-height", type=float, default=18.0)
    parser.add_argument("--target-x", type=float, default=-25.0)
    parser.add_argument("--target-y", type=float, default=10.9)
    parser.add_argument("--target-z", type=float, default=18.0)
    parser.add_argument("--speed", type=float, default=5.0)
    parser.add_argument("--move-timeout", type=float, default=20.0)
    args = parser.parse_args()

    client = hakosim.MultirotorClient(str(args.config), args.robot)
    if not client.confirmConnection():
        raise RuntimeError("hakopy.init_for_external() failed")
    client.enableApiControl(True, args.robot)
    client.armDisarm(True, args.robot)

    before = pose_dict(client.simGetVehiclePose(args.robot))
    print(f"pose before takeoff: {before}")

    takeoff_ok = bool(client.takeoff(args.takeoff_height, args.robot))
    after_takeoff = pose_dict(client.simGetVehiclePose(args.robot))
    print(f"pose after takeoff: {after_takeoff}")

    move_ok = bool(
        client.moveToPosition(
            args.target_x,
            args.target_y,
            args.target_z,
            args.speed,
            timeout_sec=args.move_timeout,
            vehicle_name=args.robot,
        )
    )
    time.sleep(1.0)
    client.run_nowait()
    after_move = pose_dict(client.simGetVehiclePose(args.robot))

    report = {
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "robot": args.robot,
        "before": before,
        "takeoffHeight": args.takeoff_height,
        "takeoffSucceeded": takeoff_ok,
        "afterTakeoff": after_takeoff,
        "target": {
            "x": args.target_x,
            "y": args.target_y,
            "z": args.target_z,
            "speed": args.speed,
        },
        "moveSucceeded": move_ok,
        "afterMove": after_move,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if takeoff_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
