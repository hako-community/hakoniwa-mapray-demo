#!/usr/bin/env python3
"""Observe W5 collision events through the browser WebSocket path."""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import time
from pathlib import Path

import websockets

from hakoniwa_pdu.impl.data_packet import DataPacket
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_conv_Twist import pdu_to_py_Twist
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_conv_DroneStatus import (
    pdu_to_py_DroneStatus,
)
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_conv_ImpulseCollision import (
    pdu_to_py_ImpulseCollision,
)


def vector(value: object) -> list[float]:
    return [float(value.x), float(value.y), float(value.z)]


def magnitude(value: list[float]) -> float:
    return math.sqrt(sum(item * item for item in value))


def normalize(value: list[float], fallback: list[float] | None = None) -> list[float]:
    length = magnitude(value)
    if length < 1e-6:
        return list(fallback or [0.0, 0.0, 1.0])
    return [item / length for item in value]


class TerrainHeightSampler:
    """Bilinear sampler for the compact browser/MuJoCo terrain grid."""

    def __init__(self, path: Path):
        data = json.loads(path.read_text(encoding="utf-8"))
        self.rows = int(data["rows"])
        self.columns = int(data["columns"])
        self.x_min = float(data["xMinM"])
        self.x_max = float(data["xMaxM"])
        self.y_min = float(data["yMinM"])
        self.y_max = float(data["yMaxM"])
        self.heights = [float(value) for value in data["modelHeightsM"]]
        if self.rows < 2 or self.columns < 2:
            raise ValueError("Terrain grid must have at least two rows and columns")
        if len(self.heights) != self.rows * self.columns:
            raise ValueError("Terrain grid height count does not match its dimensions")

    def sample(self, x_m: float, y_m: float) -> float | None:
        if not (self.x_min <= x_m <= self.x_max and self.y_min <= y_m <= self.y_max):
            return None
        column_value = (x_m - self.x_min) / (self.x_max - self.x_min) * (self.columns - 1)
        row_value = (y_m - self.y_min) / (self.y_max - self.y_min) * (self.rows - 1)
        column = min(math.floor(column_value), self.columns - 2)
        row = min(math.floor(row_value), self.rows - 2)
        dx = column_value - column
        dy = row_value - row

        def at(grid_row: int, grid_column: int) -> float:
            return self.heights[grid_row * self.columns + grid_column]

        return (
            at(row, column) * (1 - dx) * (1 - dy)
            + at(row, column + 1) * dx * (1 - dy)
            + at(row + 1, column) * (1 - dx) * dy
            + at(row + 1, column + 1) * dx * dy
        )


def classify_surface(
    position: list[float], normal: list[float], terrain_height_m: float | None = None
) -> str:
    near_ground = (
        position[2] <= 1.5
        if terrain_height_m is None
        else abs(position[2] - terrain_height_m) <= 1.5
    )
    if near_ground and normal[2] >= 0.35:
        return "ground"
    if abs(normal[2]) >= 0.65:
        return "roof"
    return "wall"


async def monitor(
    uri: str, duration: float, terrain_grid: TerrainHeightSampler | None = None
) -> dict[str, object]:
    deadline = time.monotonic() + duration
    channels: dict[int, int] = {}
    position: list[float] | None = None
    previous_position: list[float] | None = None
    previous_position_at: float | None = None
    recent_velocity = [0.0, 0.0, 0.0]
    recent_velocity_at = -math.inf
    initial_count: int | None = None
    last_count: int | None = None
    max_count = 0
    impulse_active = False
    sequence = 0
    events: list[dict[str, object]] = []

    async with websockets.connect(uri, compression=None, max_size=10 * 1024 * 1024) as socket:
        while time.monotonic() < deadline:
            remaining = max(0.01, min(1.0, deadline - time.monotonic()))
            try:
                raw = await asyncio.wait_for(socket.recv(), timeout=remaining)
            except asyncio.TimeoutError:
                continue
            if isinstance(raw, str):
                continue
            packet = DataPacket.decode(bytearray(raw), "v2")
            if packet is None:
                continue
            channel = int(packet.channel_id)
            channels[channel] = len(packet.body_data)
            now = time.monotonic()

            if channel == 1:
                pose = pdu_to_py_Twist(packet.body_data)
                next_position = vector(pose.linear)
                if previous_position is not None and previous_position_at is not None:
                    elapsed = max(now - previous_position_at, 1e-3)
                    velocity = [
                        (next_position[index] - previous_position[index]) / elapsed
                        for index in range(3)
                    ]
                    if magnitude(velocity) >= 0.05:
                        recent_velocity = velocity
                        recent_velocity_at = now
                previous_position = next_position
                previous_position_at = now
                position = next_position
                continue

            if channel == 2:
                impulse = pdu_to_py_ImpulseCollision(packet.body_data)
                active = bool(impulse.collision)
                if active and not impulse_active and position is not None:
                    sequence += 1
                    normal = normalize(vector(impulse.normal), normalize([-v for v in recent_velocity]))
                    terrain_height = (
                        terrain_grid.sample(position[0], position[1]) if terrain_grid else None
                    )
                    events.append(
                        {
                            "eventId": f"Drone:impulse:{sequence}",
                            "source": "ImpulseCollision",
                            "positionRos": position,
                            "normalRos": normal,
                            "impactSpeedMps": magnitude(recent_velocity),
                            "impactMeasure": "velocity_proxy",
                            "surfaceType": classify_surface(position, normal, terrain_height),
                            "terrainHeightM": terrain_height,
                            "estimated": False,
                        }
                    )
                impulse_active = active
                continue

            if channel == 18:
                status = pdu_to_py_DroneStatus(packet.body_data)
                count = int(status.collided_counts)
                if initial_count is None:
                    initial_count = count
                    last_count = count
                max_count = max(max_count, count)
                if last_count is not None and count > last_count and position is not None:
                    velocity = recent_velocity if now - recent_velocity_at <= 0.75 else [0.0, 0.0, 0.0]
                    normal = normalize([-value for value in velocity])
                    terrain_height = (
                        terrain_grid.sample(position[0], position[1]) if terrain_grid else None
                    )
                    surface = classify_surface(position, normal, terrain_height)
                    duplicate = False
                    if events:
                        latest = events[-1]
                        separation = magnitude(
                            [position[index] - latest["positionRos"][index] for index in range(3)]
                        )
                        duplicate = latest["surfaceType"] == surface and separation < 1.0
                    if not duplicate:
                        events.append(
                            {
                                "eventId": f"Drone:status:{count}",
                                "source": "DroneStatus.collided_counts",
                                "positionRos": position,
                                "normalRos": normal,
                                "impactSpeedMps": magnitude(velocity),
                                "impactMeasure": "velocity_proxy",
                                "surfaceType": surface,
                                "terrainHeightM": terrain_height,
                                "estimated": True,
                                "countDelta": count - last_count,
                            }
                        )
                last_count = count

    return {
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "uri": uri,
        "durationSeconds": duration,
        "channels": {str(key): value for key, value in sorted(channels.items())},
        "initialCollidedCounts": initial_count,
        "maxCollidedCounts": max_count,
        "collidedCountIncrease": max_count - (initial_count or 0),
        "collisionEvents": events,
        "collisionEventCount": len(events),
        "surfaceTypes": sorted({str(event["surfaceType"]) for event in events}),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="ws://127.0.0.1:8765")
    parser.add_argument("--duration", type=float, default=35.0)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expect-surface", choices=("wall", "roof", "ground"))
    parser.add_argument("--terrain-grid", type=Path)
    args = parser.parse_args()
    terrain_grid = TerrainHeightSampler(args.terrain_grid) if args.terrain_grid else None
    report = asyncio.run(monitor(args.uri, args.duration, terrain_grid))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    passed = report["collidedCountIncrease"] > 0 and report["collisionEventCount"] > 0
    if args.expect_surface:
        passed = passed and args.expect_surface in report["surfaceTypes"]
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
