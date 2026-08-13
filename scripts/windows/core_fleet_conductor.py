#!/usr/bin/env python3
"""Run a lightweight Hakoniwa master/conductor for the core fleet demo."""

from __future__ import annotations

import argparse
import logging
import time

import hakopy


LOG = logging.getLogger("core-fleet-conductor")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--delta-time-usec", type=int, default=20_000)
    parser.add_argument("--max-delay-usec", type=int, default=200_000)
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    LOG.info(
        "starting Hakoniwa conductor delta=%dus max_delay=%dus",
        args.delta_time_usec,
        args.max_delay_usec,
    )
    result = hakopy.conductor_start(args.delta_time_usec, args.max_delay_usec)
    LOG.info("hakopy.conductor_start() returned %s", result)
    if result is False:
        return 1
    try:
        while True:
            time.sleep(1.0)
    except KeyboardInterrupt:
        LOG.info("stopping Hakoniwa conductor")
    finally:
        hakopy.conductor_stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
