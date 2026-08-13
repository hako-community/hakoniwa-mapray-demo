#!/usr/bin/env python3
"""Windows-native Hakoniwa SHM -> browser WebSocket bridge.

This is intentionally small and legacy-viewer focused. It forwards Drone
channels 0 (motor), 1 (pos), 2 (ImpulseCollision), 4 (battery), and 18
(DroneStatus) as endpoint-v2 binary frames to every connected client. Channel 2 is
forwarded read-only:
the installed hakoSim uses it as an external collision input, while native
MuJoCo contact is reported by DroneStatus.collided_counts on channel 18.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import time
from pathlib import Path

import websockets

from hakoniwa_pdu._optional_hakopy import hakopy
from hakoniwa_pdu.impl.data_packet import (
    DECLARE_PDU_FOR_READ,
    DECLARE_PDU_FOR_WRITE,
    PDU_DATA,
    REQUEST_PDU_READ,
    DataPacket,
)

LOG = logging.getLogger("phase-w2-bridge")
LEGACY_FORWARDED = {
    0: ("motor", 112),
    1: ("pos", 72),
    2: ("impulse_collision", 216),
    4: ("battery", 56),
    18: ("status", 64),
}
LEGACY_WRITABLE = {0, 1, 4, 18}
FLEET_FORWARDED = {0: ("drone_visual_state_array_0", 32768)}


def make_frame(robot: str, channel_id: int, body: bytearray) -> bytes:
    return bytes(DataPacket(robot, channel_id, body).encode("v2", PDU_DATA))


def decode_frame(raw: bytes):
    try:
        return DataPacket.decode(bytearray(raw), "v2")
    except Exception:
        LOG.exception("failed to decode browser frame")
        return None


async def run_bridge(
    host: str,
    port: int,
    robot: str,
    interval: float,
    stop_event: asyncio.Event,
    forwarded: dict[int, tuple[str, int]],
    writable: set[int],
    ready_file: Path | None = None,
) -> None:
    if not hakopy.init_for_external():
        raise RuntimeError("hakopy.init_for_external() failed")
    # A browser viewer and one or more test/monitor processes may observe the
    # same simulation concurrently.  Each socket gets a lock because a direct
    # REQUEST_PDU_READ reply can overlap the periodic publisher.
    clients: dict[object, asyncio.Lock] = {}
    last_sent: dict[int, bytes] = {}

    async def send_frame(websocket, frame: bytes) -> None:
        send_lock = clients.get(websocket)
        if send_lock is None:
            return
        async with send_lock:
            await websocket.send(frame)

    async def send_latest(websocket, channel_id: int) -> None:
        _pdu_name, pdu_size = forwarded[channel_id]
        body = hakopy.pdu_read(robot, channel_id, pdu_size)
        if body:
            frame = make_frame(robot, channel_id, body)
            last_sent[channel_id] = frame
            await send_frame(websocket, frame)

    async def client_handler(websocket) -> None:
        clients[websocket] = asyncio.Lock()
        if ready_file is not None:
            ready_file.parent.mkdir(parents=True, exist_ok=True)
            ready_file.touch(exist_ok=True)
        LOG.info("WebSocket client connected count=%d", len(clients))
        try:
            async for raw in websocket:
                if isinstance(raw, str):
                    continue
                packet = decode_frame(raw)
                if packet is None or packet.robot_name != robot:
                    continue
                req = packet.meta_pdu.meta_request_type
                if req == REQUEST_PDU_READ and packet.channel_id in forwarded:
                    await send_latest(websocket, packet.channel_id)
                elif req == PDU_DATA and packet.channel_id in writable:
                    body = packet.body_data
                    if hakopy.pdu_write(robot, packet.channel_id, body, len(body)):
                        LOG.debug("browser write robot=%s channel=%s", robot, packet.channel_id)
                elif req in (DECLARE_PDU_FOR_READ, DECLARE_PDU_FOR_WRITE):
                    LOG.debug("browser declaration robot=%s channel=%s req=%s", robot, packet.channel_id, req)
        except websockets.ConnectionClosed:
            pass
        finally:
            clients.pop(websocket, None)
            LOG.info("WebSocket client disconnected count=%d", len(clients))

    async def publish_loop() -> None:
        while not stop_event.is_set():
            if clients:
                for channel_id, (_pdu_name, pdu_size) in forwarded.items():
                    try:
                        body = hakopy.pdu_read(robot, channel_id, pdu_size)
                        if body:
                            frame = make_frame(robot, channel_id, body)
                            last_sent[channel_id] = frame
                            for websocket in tuple(clients):
                                try:
                                    await send_frame(websocket, frame)
                                except websockets.ConnectionClosed:
                                    clients.pop(websocket, None)
                    except Exception:
                        LOG.exception("PDU read failed channel=%s", channel_id)
            await asyncio.sleep(max(0.005, interval))

    async with websockets.serve(
        client_handler,
        host,
        port,
        compression=None,
        max_size=10 * 1024 * 1024,
        ping_interval=30,
    ):
        LOG.info("WebSocket bridge listening at ws://%s:%d", host, port)
        publisher = asyncio.create_task(publish_loop())
        await stop_event.wait()
        publisher.cancel()
        await asyncio.gather(publisher, return_exceptions=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--profile", choices=("legacy", "fleets"), default="legacy")
    parser.add_argument("--robot")
    parser.add_argument("--interval", type=float, default=0.02)
    parser.add_argument("--ready-file", type=Path)
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args()
    if args.profile == "fleets":
        robot = args.robot or "DroneVisualStatePublisher"
        forwarded = FLEET_FORWARDED
        writable: set[int] = set()
    else:
        robot = args.robot or "Drone"
        forwarded = LEGACY_FORWARDED
        writable = LEGACY_WRITABLE

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    stop_event = asyncio.Event()

    def request_stop(*_args) -> None:
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, request_stop)
        except (OSError, ValueError):
            pass

    try:
        asyncio.run(run_bridge(
            args.host,
            args.port,
            robot,
            args.interval,
            stop_event,
            forwarded,
            writable,
            args.ready_file,
        ))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
