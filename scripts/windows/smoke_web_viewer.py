#!/usr/bin/env python3
"""Phase W2 WebSocket protocol smoke test."""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from pathlib import Path

import websockets

from hakoniwa_pdu.impl.data_packet import DataPacket, PDU_DATA


async def run(uri: str, duration: float) -> dict:
    started = time.time()
    channels: dict[int, int] = {}
    frames = 0
    async with websockets.connect(uri, compression=None, max_size=10 * 1024 * 1024) as socket:
        while time.time() - started < duration:
            try:
                raw = await asyncio.wait_for(socket.recv(), timeout=1.0)
            except asyncio.TimeoutError:
                continue
            if isinstance(raw, str):
                continue
            packet = DataPacket.decode(bytearray(raw), "v2")
            if packet is None:
                continue
            frames += 1
            channels[packet.channel_id] = len(packet.body_data)
    return {
        "uri": uri,
        "durationSeconds": duration,
        "frameCount": frames,
        "channels": {str(key): value for key, value in sorted(channels.items())},
        "requiredChannelsPresent": all(key in channels for key in (0, 1, 2, 18)),
        "collisionChannelsPresent": all(key in channels for key in (2, 18)),
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="ws://127.0.0.1:8765")
    parser.add_argument("--duration", type=float, default=3.0)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    report = asyncio.run(run(args.uri, args.duration))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if report["requiredChannelsPresent"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
