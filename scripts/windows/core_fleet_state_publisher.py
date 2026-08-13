#!/usr/bin/env python3
"""Hakoniwa asset that publishes a deterministic fleet as DroneVisualStateArray."""

from __future__ import annotations

import argparse
import logging
import time
from pathlib import Path

import hakopy
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_conv_DroneVisualStateArray import (
    py_to_pdu_DroneVisualStateArray,
)
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_pytype_DroneVisualState import DroneVisualState
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_pytype_DroneVisualStateArray import DroneVisualStateArray

from core_fleet_scenario import CoreFleetScenario


LOG = logging.getLogger("core-fleet-publisher")
ROBOT_NAME = "DroneVisualStatePublisher"
CHANNEL_ID = 0
PDU_CAPACITY = 32768


class CoreFleetPublisher:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.delta_seconds = args.delta_time_usec / 1_000_000.0
        self.elapsed_seconds = 0.0
        self.sequence_id = 0
        self.ready_announced = False
        self.scenario = CoreFleetScenario(
            args.operations,
            fleet_size=args.fleet_size,
            seed=args.seed,
            origin={"latitude": args.origin_latitude, "longitude": args.origin_longitude},
        )

    def _is_consumer_ready(self) -> bool:
        return self.args.ready_file is None or self.args.ready_file.is_file()

    def publish(self) -> None:
        if self.sequence_id == 0:
            self.sequence_id = 1
        packet = DroneVisualStateArray()
        packet.sequence_id = self.sequence_id
        packet.chunk_index = 0
        packet.chunk_count = 1
        packet.start_index = 0
        states = self.scenario.sample(self.elapsed_seconds)
        packet.valid_count = len(states)
        packet.drones = []
        for state in states:
            visual = DroneVisualState()
            visual.x, visual.y, visual.z = state["position_ros"]
            visual.roll, visual.pitch, visual.yaw = state["rpy_radians"]
            visual.pwm_duty = state["pwm_duty"]
            packet.drones.append(visual)
        body = py_to_pdu_DroneVisualStateArray(packet)
        if len(body) > PDU_CAPACITY:
            raise RuntimeError(f"fleet PDU exceeds capacity: {len(body)} > {PDU_CAPACITY}")
        if not hakopy.pdu_write(ROBOT_NAME, CHANNEL_ID, body, len(body)):
            raise RuntimeError("hakopy.pdu_write() failed")

    def on_initialize(self, _context) -> int:
        LOG.info(
            "initialized fleet=%d seed=%d trigger=%.1fs ready_file=%s",
            self.args.fleet_size,
            self.args.seed,
            self.scenario.trigger_seconds,
            self.args.ready_file,
        )
        self.publish()
        return 0

    def on_reset(self, _context) -> int:
        self.elapsed_seconds = 0.0
        self.sequence_id = 0
        self.ready_announced = False
        self.publish()
        LOG.info("scenario reset")
        return 0

    def on_simulation_step(self, _context) -> int:
        try:
            if self._is_consumer_ready():
                if not self.ready_announced:
                    LOG.info("viewer connected; scenario clock started")
                    self.ready_announced = True
                self.elapsed_seconds += self.delta_seconds
                self.sequence_id = (self.sequence_id + 1) & 0xFFFFFFFF
                if self.sequence_id == 0:
                    self.sequence_id = 1
            self.publish()
            if not self.args.disable_real_sleep:
                time.sleep(self.delta_seconds)
            return 0
        except Exception:
            LOG.exception("simulation step failed")
            return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdu-config", type=Path, required=True)
    parser.add_argument("--operations", type=Path, required=True)
    parser.add_argument("--fleet-size", type=int, choices=(10, 20, 30), default=30)
    parser.add_argument("--seed", type=int, default=20260811)
    parser.add_argument("--asset-name", default=ROBOT_NAME)
    parser.add_argument("--delta-time-usec", type=int, default=20_000)
    parser.add_argument("--origin-latitude", type=float, default=35.6625)
    parser.add_argument("--origin-longitude", type=float, default=139.70625)
    parser.add_argument("--ready-file", type=Path)
    parser.add_argument("--disable-real-sleep", action="store_true")
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    publisher = CoreFleetPublisher(args)
    callbacks = {
        "on_initialize": publisher.on_initialize,
        "on_simulation_step": publisher.on_simulation_step,
        "on_manual_timing_control": None,
        "on_reset": publisher.on_reset,
    }
    registered = hakopy.asset_register(
        args.asset_name,
        str(args.pdu_config.resolve()),
        callbacks,
        args.delta_time_usec,
        hakopy.HAKO_ASSET_MODEL_PLANT,
    )
    if registered is False:
        LOG.error("hakopy.asset_register() failed")
        return 1
    result = hakopy.start()
    LOG.info("hakopy.start() returned %s", result)
    return 0 if result is not False else 1


if __name__ == "__main__":
    raise SystemExit(main())
