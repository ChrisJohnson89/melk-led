#!/usr/bin/env python3
"""Hardware self-test: verify the reverse-engineered protocol on a real
MELK-OA10 controller.

Usage:
    python scripts/selftest.py                # scan + test first device found
    python scripts/selftest.py <MAC-or-UUID>  # test a specific device

Watch the lights: you should see power on, red -> green -> blue, a brightness
sweep, warm/cool white, a rainbow effect, then power off. If every step is
visible, the protocol is confirmed on your hardware.
"""

import asyncio
import logging
import sys

from melk_led import MelkDevice, protocol, scan, setup_logging


async def run(address: str | None) -> int:
    if address is None:
        found = await scan()
        if not found:
            print("No MELK devices found. Make sure the strip is powered and "
                  "not connected in the official app.")
            return 1
        address = found[0].address
        print(f"Using {found[0].name} @ {address}")

    dev = MelkDevice(address, name="selftest")
    async with dev:
        steps = [
            ("power on", dev.on()),
            ("red", dev.set_color(255, 0, 0)),
            ("green", dev.set_color(0, 255, 0)),
            ("blue", dev.set_color(0, 0, 255)),
            ("brightness 20%", dev.set_brightness(20)),
            ("brightness 100%", dev.set_brightness(100)),
            ("warm white", dev.set_white(protocol.WHITE_WARM)),
            ("cool white", dev.set_white(protocol.WHITE_COOL)),
            ("rainbow effect", dev.set_effect(int(protocol.Effect.RAINBOW_CYCLE))),
            ("effect speed 80%", dev.set_effect_speed(80)),
        ]
        for label, coro in steps:
            print(f"  -> {label}")
            await coro
            await asyncio.sleep(1.5)
        print("  -> power off")
        await dev.off()
    print("Self-test complete.")
    return 0


if __name__ == "__main__":
    setup_logging(logging.INFO)
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    raise SystemExit(asyncio.run(run(arg)))
