#!/usr/bin/env python3
"""Monitor Phase W1 pose and ImpulseCollision PDUs with low-overhead SHM reads."""

from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

from hakoniwa_pdu._optional_hakopy import hakopy
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_conv_Twist import pdu_to_py_Twist
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_conv_ImpulseCollision import (
    pdu_to_py_ImpulseCollision,
)
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_conv_DroneStatus import (
    pdu_to_py_DroneStatus,
)


def plain(value: Any) -> Any:
    if is_dataclass(value):
        return {key: plain(item) for key, item in asdict(value).items()}
    if isinstance(value, dict):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    if hasattr(value, "__dict__"):
        return {
            key: plain(item)
            for key, item in vars(value).items()
            if not key.startswith("_")
        }
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def vector(value: Any) -> dict[str, float]:
    return {"x": float(value.x), "y": float(value.y), "z": float(value.z)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=10.0)
    parser.add_argument("--interval", type=float, default=0.001)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--robot", default="Drone")
    args = parser.parse_args()

    if not args.config.exists():
        raise FileNotFoundError(args.config)
    if not hakopy.init_for_external():
        raise RuntimeError("hakopy.init_for_external() failed")

    started = time.time()
    deadline = time.monotonic() + args.duration
    samples: list[dict[str, Any]] = []
    collisions: list[dict[str, Any]] = []
    status_transitions: list[dict[str, Any]] = []
    last_status_transition: dict[str, Any] | None = None
    max_status_event: dict[str, Any] | None = None
    was_colliding = False
    initial_collided_counts: int | None = None
    last_collided_counts: int | None = None
    max_collided_counts = 0
    read_errors: list[str] = []
    poll_count = 0

    while time.monotonic() < deadline:
        poll_count += 1
        elapsed = time.time() - started
        try:
            pos_raw = hakopy.pdu_read(args.robot, 1, 72)
            if pos_raw:
                pose = pdu_to_py_Twist(pos_raw)
                samples.append(
                    {
                        "elapsedSeconds": elapsed,
                        "position": vector(pose.linear),
                        "euler": vector(pose.angular),
                    }
                )
        except Exception as exc:
            read_errors.append(f"pos: {exc}")

        try:
            impulse_raw = hakopy.pdu_read(args.robot, 2, 216)
            if impulse_raw:
                impulse = pdu_to_py_ImpulseCollision(impulse_raw)
                colliding = bool(impulse.collision)
                if colliding and not was_colliding:
                    event = {
                        "elapsedSeconds": elapsed,
                        "position": samples[-1]["position"] if samples else None,
                        "impulse": plain(impulse),
                    }
                    collisions.append(event)
                    print(json.dumps({"collision": event}, ensure_ascii=False))
                was_colliding = colliding
        except Exception as exc:
            read_errors.append(f"impulse: {exc}")

        try:
            status_raw = hakopy.pdu_read(args.robot, 18, 64)
            if status_raw:
                status = pdu_to_py_DroneStatus(status_raw)
                collided_counts = int(status.collided_counts)
                if initial_collided_counts is None:
                    initial_collided_counts = collided_counts
                max_collided_counts = max(max_collided_counts, collided_counts)
                if collided_counts != last_collided_counts:
                    transition = {
                        "elapsedSeconds": elapsed,
                        "collidedCounts": collided_counts,
                        "position": samples[-1]["position"] if samples else None,
                    }
                    last_status_transition = transition
                    if len(status_transitions) < 200:
                        status_transitions.append(transition)
                    if max_status_event is None or collided_counts >= max_status_event["collidedCounts"]:
                        max_status_event = transition
                    if collided_counts > 0:
                        print(json.dumps({"droneStatusCollision": transition}, ensure_ascii=False))
                    last_collided_counts = collided_counts
        except Exception as exc:
            read_errors.append(f"status: {exc}")

        if args.interval > 0:
            time.sleep(args.interval)

    unique_positions = {
        (
            round(sample["position"]["x"], 5),
            round(sample["position"]["y"], 5),
            round(sample["position"]["z"], 5),
        )
        for sample in samples
    }
    distance = 0.0
    if len(samples) >= 2:
        first = samples[0]["position"]
        last = samples[-1]["position"]
        distance = math.sqrt(
            (last["x"] - first["x"]) ** 2
            + (last["y"] - first["y"]) ** 2
            + (last["z"] - first["z"]) ** 2
        )

    report = {
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "robot": args.robot,
        "durationSeconds": args.duration,
        "pollCount": poll_count,
        "effectivePollIntervalMilliseconds": args.duration * 1000 / max(poll_count, 1),
        "sampleCount": len(samples),
        "uniquePositionCount": len(unique_positions),
        "displacementMeters": distance,
        "firstSample": samples[0] if samples else None,
        "lastSample": samples[-1] if samples else None,
        "impulseCollisionEventCount": len(collisions),
        "impulseCollisionEvents": collisions,
        "initialCollidedCounts": initial_collided_counts,
        "maxCollidedCounts": max_collided_counts,
        "collidedCountIncrease": max_collided_counts - (initial_collided_counts or 0),
        "physicalCollisionDetected": max_collided_counts > (initial_collided_counts or 0),
        "droneStatusTransitions": status_transitions,
        "lastDroneStatusTransition": last_status_transition,
        "maxDroneStatusEvent": max_status_event,
        "readErrors": list(dict.fromkeys(read_errors)),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if samples else 1


if __name__ == "__main__":
    raise SystemExit(main())


