#!/usr/bin/env python3
"""Verify that the Phase W2 bridge broadcasts to concurrent clients."""

from __future__ import annotations

import argparse
import asyncio
import json

import websockets


async def probe(uri: str, client_count: int, timeout: float) -> dict:
    sockets = []
    try:
        for _ in range(client_count):
            sockets.append(
                await asyncio.wait_for(
                    websockets.connect(uri, compression=None), timeout=timeout
                )
            )
        frames = await asyncio.gather(
            *(asyncio.wait_for(socket.recv(), timeout=timeout) for socket in sockets)
        )
        binary_lengths = [
            len(frame) if isinstance(frame, (bytes, bytearray)) else 0
            for frame in frames
        ]
        if any(length == 0 for length in binary_lengths):
            raise RuntimeError(f"non-binary or empty frame received: {binary_lengths}")
        return {
            "uri": uri,
            "requestedClients": client_count,
            "connectedClients": len(sockets),
            "firstFrameBytes": binary_lengths,
            "status": "passed",
        }
    finally:
        await asyncio.gather(
            *(socket.close() for socket in sockets), return_exceptions=True
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="ws://127.0.0.1:8765")
    parser.add_argument("--clients", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()
    if args.clients < 2:
        parser.error("--clients must be at least 2")
    report = asyncio.run(probe(args.uri, args.clients, args.timeout))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
