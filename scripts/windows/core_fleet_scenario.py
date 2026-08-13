"""Deterministic wide-area fleet scenario driven by Hakoniwa simulation time."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


EARTH_RADIUS_M = 6_378_137.0


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def _hash_unit(seed: int, index: int) -> float:
    value = (int(seed) ^ (((index + 1) * 0x9E3779B1) & 0xFFFFFFFF)) & 0xFFFFFFFF
    value ^= value >> 16
    value = (value * 0x7FEB352D) & 0xFFFFFFFF
    value ^= value >> 15
    value = (value * 0x846CA68B) & 0xFFFFFFFF
    value ^= value >> 16
    return value / 0x1_0000_0000


def _segment_length_m(a: list[float], b: list[float]) -> float:
    mean_latitude = math.radians((float(a[1]) + float(b[1])) * 0.5)
    east = math.radians(float(b[0]) - float(a[0])) * EARTH_RADIUS_M * math.cos(mean_latitude)
    north = math.radians(float(b[1]) - float(a[1])) * EARTH_RADIUS_M
    up = float(b[2] if len(b) > 2 else 0.0) - float(a[2] if len(a) > 2 else 0.0)
    return math.sqrt(east * east + north * north + up * up)


@dataclass(frozen=True)
class PreparedRoute:
    route_id: str
    coordinates: list[list[float]]
    cumulative_m: list[float]
    length_m: float
    cycle_seconds: float


def _prepare_route(feature: dict[str, Any]) -> PreparedRoute:
    coordinates = feature.get("geometry", {}).get("coordinates", [])
    cumulative = [0.0]
    for index in range(1, len(coordinates)):
        cumulative.append(cumulative[-1] + _segment_length_m(coordinates[index - 1], coordinates[index]))
    properties = feature.get("properties", {})
    return PreparedRoute(
        route_id=str(properties.get("id") or properties.get("name") or "route"),
        coordinates=coordinates,
        cumulative_m=cumulative,
        length_m=cumulative[-1] if cumulative else 0.0,
        cycle_seconds=max(30.0, float(properties.get("cycleSeconds", 240.0))),
    )


def _sample_route(route: PreparedRoute, progress: float) -> tuple[list[float], tuple[float, float]]:
    distance = _clamp01(progress) * route.length_m
    segment = 1
    while segment < len(route.cumulative_m) - 1 and route.cumulative_m[segment] < distance:
        segment += 1
    a = route.coordinates[segment - 1]
    b = route.coordinates[segment]
    start = route.cumulative_m[segment - 1]
    segment_length = max(0.001, route.cumulative_m[segment] - start)
    ratio = _clamp01((distance - start) / segment_length)
    coordinate = [
        float(a[0]) + (float(b[0]) - float(a[0])) * ratio,
        float(a[1]) + (float(b[1]) - float(a[1])) * ratio,
        float(a[2] if len(a) > 2 else 0.0)
        + (float(b[2] if len(b) > 2 else 0.0) - float(a[2] if len(a) > 2 else 0.0)) * ratio,
    ]
    return coordinate, (float(b[0]) - float(a[0]), float(b[1]) - float(a[1]))


def geo_to_ros(origin: dict[str, float], coordinate: list[float]) -> tuple[float, float, float]:
    origin_latitude = float(origin["latitude"])
    latitude = float(coordinate[1])
    north = math.radians(latitude - origin_latitude) * EARTH_RADIUS_M
    east = (
        math.radians(float(coordinate[0]) - float(origin["longitude"]))
        * EARTH_RADIUS_M
        * math.cos(math.radians((latitude + origin_latitude) * 0.5))
    )
    return north, -east, float(coordinate[2] if len(coordinate) > 2 else 0.0)


class CoreFleetScenario:
    def __init__(
        self,
        operations_path: Path,
        *,
        fleet_size: int,
        seed: int,
        origin: dict[str, float],
    ) -> None:
        if fleet_size not in (10, 20, 30):
            raise ValueError("fleet_size must be 10, 20, or 30")
        data = json.loads(operations_path.read_text(encoding="utf-8"))
        features = data.get("features", [])
        self.routes = [
            _prepare_route(feature)
            for feature in features
            if feature.get("properties", {}).get("type") == "planned_route"
            and feature.get("geometry", {}).get("type") == "LineString"
        ]
        self.routes = [route for route in self.routes if route.length_m > 0 and len(route.coordinates) >= 2]
        if len(self.routes) < 3:
            raise ValueError("at least three planned routes are required")
        incidents = [
            feature for feature in features
            if feature.get("properties", {}).get("type") == "incident_site"
            and feature.get("geometry", {}).get("type") == "Point"
        ]
        if not incidents:
            raise ValueError("incident_site is required")
        incident = incidents[0]
        properties = incident.get("properties", {})
        self.incident_coordinate = incident["geometry"]["coordinates"]
        self.trigger_seconds = max(0.0, float(properties.get("triggerAtSeconds", 35.0)))
        self.target_index = max(0, min(fleet_size - 1, int(properties.get("targetDroneIndex", 4))))
        self.diversion_seconds = 8.0
        self.fleet_size = fleet_size
        self.seed = int(seed)
        self.origin = origin

    def sample(self, elapsed_seconds: float) -> list[dict[str, Any]]:
        elapsed = max(0.0, float(elapsed_seconds))
        states: list[dict[str, Any]] = []
        for index in range(self.fleet_size):
            route_index = index % len(self.routes)
            route = self.routes[route_index]
            members = math.ceil((self.fleet_size - route_index) / len(self.routes))
            member_index = index // len(self.routes)
            phase = member_index / max(1, members) + _hash_unit(self.seed, index) * 0.015
            progress = (elapsed / route.cycle_seconds + phase) % 1.0
            coordinate, tangent = _sample_route(route, progress)
            status = "NORMAL"
            if index == self.target_index and elapsed >= self.trigger_seconds:
                diversion = _clamp01((elapsed - self.trigger_seconds) / self.diversion_seconds)
                coordinate = [
                    coordinate[axis]
                    + (float(self.incident_coordinate[axis]) - coordinate[axis]) * diversion
                    for axis in range(3)
                ]
                status = "WARNING" if diversion < 0.35 else "HIGH"
            tangent_east = tangent[0] * math.cos(math.radians(coordinate[1]))
            tangent_north = tangent[1]
            yaw_radians = math.atan2(-tangent_east, tangent_north)
            x, y, z = geo_to_ros(self.origin, coordinate)
            states.append({
                "index": index,
                "id": f"Drone-{index + 1}",
                "route_id": route.route_id,
                "position_ros": [x, y, z],
                "rpy_radians": [0.0, 0.0, yaw_radians],
                "pwm_duty": [0.55, 0.55, 0.55, 0.55],
                "status": status,
                "scenario_elapsed_seconds": elapsed,
            })
        return states
