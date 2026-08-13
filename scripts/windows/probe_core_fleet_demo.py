#!/usr/bin/env python3
"""Validate one aggregate fleet frame from the local Hakoniwa WebSocket bridge."""

from __future__ import annotations

import argparse
import json
import math

from websockets.sync.client import connect

from hakoniwa_pdu.impl.data_packet import DataPacket, PDU_DATA
from hakoniwa_pdu.pdu_msgs.hako_msgs.pdu_conv_DroneVisualStateArray import (
    pdu_to_py_DroneVisualStateArray,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="ws://127.0.0.1:8765")
    parser.add_argument("--expected-count", type=int, default=30)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    with connect(args.uri, compression=None, max_size=10 * 1024 * 1024) as websocket:
        raw = websocket.recv(timeout=args.timeout)
    if not isinstance(raw, bytes):
        raise RuntimeError("bridge returned a non-binary frame")
    packet = DataPacket.decode(bytearray(raw), "v2")
    if packet.meta_pdu.meta_request_type != PDU_DATA:
        raise RuntimeError("bridge frame is not PDU_DATA")
    if packet.robot_name != "DroneVisualStatePublisher" or packet.channel_id != 0:
        raise RuntimeError(
            f"unexpected endpoint: {packet.robot_name}/{packet.channel_id}"
        )
    fleet = pdu_to_py_DroneVisualStateArray(packet.body_data)
    if fleet.valid_count != args.expected_count:
        raise RuntimeError(
            f"valid_count={fleet.valid_count}, expected={args.expected_count}"
        )
    if fleet.sequence_id <= 0 or fleet.chunk_count != 1 or fleet.chunk_index != 0:
        raise RuntimeError("invalid aggregate sequence/chunk metadata")
    values = []
    for drone in fleet.drones[: fleet.valid_count]:
        values.extend((drone.x, drone.y, drone.z, drone.roll, drone.pitch, drone.yaw))
    if not all(math.isfinite(value) for value in values):
        raise RuntimeError("fleet contains a non-finite pose")
    print(
        json.dumps(
            {
                "status": "pass",
                "robot": packet.robot_name,
                "channel": packet.channel_id,
                "sequenceId": fleet.sequence_id,
                "validCount": fleet.valid_count,
                "chunkCount": fleet.chunk_count,
                "firstDronePositionRos": [
                    fleet.drones[0].x,
                    fleet.drones[0].y,
                    fleet.drones[0].z,
                ],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
