"""Command line interface: ``lights ...``.

Examples::

    lights scan
    lights --target office on
    lights --target office color 255 0 0
    lights --target all brightness 40
    lights --target office scene movie
    lights white
    lights warm
    lights cool
    lights scene rainbow
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys

from . import __version__, load_config, protocol, scan, setup_logging
from .manager import MelkManager
from .scenes import all_scenes

DEFAULT_TARGET = "all"


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="lights", description="Control MELK LED controllers.")
    p.add_argument("--version", action="version", version=f"melk_led {__version__}")
    p.add_argument("--target", "-t", default=DEFAULT_TARGET,
                   help="device alias, group, or MAC (default: %(default)s)")
    p.add_argument("--verbose", "-v", action="store_true", help="debug logging")

    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("scan", help="scan for nearby MELK controllers")
    sub.add_parser("on", help="turn lights on")
    sub.add_parser("off", help="turn lights off")

    c = sub.add_parser("color", help="set RGB colour")
    c.add_argument("r", type=int)
    c.add_argument("g", type=int)
    c.add_argument("b", type=int)

    b = sub.add_parser("brightness", help="set brightness 0-100")
    b.add_argument("percent", type=int)

    sub.add_parser("white", help="neutral white")
    sub.add_parser("warm", help="warm white")
    sub.add_parser("cool", help="cool white")

    e = sub.add_parser("effect", help="set built-in effect by id or name")
    e.add_argument("effect", help="effect id (int) or name, e.g. RAINBOW_CYCLE")

    s = sub.add_parser("scene", help="apply a named scene / mode")
    s.add_argument("name", help="scene name (movie, pet, gaming, rainbow, ...)")

    sub.add_parser("scenes", help="list available scenes")

    return p


def _resolve_effect(value: str) -> int:
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return int(protocol.Effect[value.upper()])
    except KeyError:
        raise SystemExit(
            f"unknown effect {value!r}; known: {[e.name for e in protocol.Effect]}"
        )


async def _run(args: argparse.Namespace) -> int:
    config = load_config()

    if args.command == "scenes":
        for name in sorted(all_scenes(config.scenes)):
            print(name)
        return 0

    if args.command == "scan":
        found = await scan()
        if not found:
            print("no MELK devices found")
        for d in found:
            print(f"{d.address}  {d.name}")
        return 0

    mgr = MelkManager(config)
    try:
        cmd = args.command
        if cmd == "on":
            await mgr.on(args.target)
        elif cmd == "off":
            await mgr.off(args.target)
        elif cmd == "color":
            await mgr.set_color(args.target, args.r, args.g, args.b)
        elif cmd == "brightness":
            await mgr.set_brightness(args.target, args.percent)
        elif cmd == "white":
            await mgr.set_white(args.target, protocol.WHITE_NEUTRAL)
        elif cmd == "warm":
            await mgr.set_white(args.target, protocol.WHITE_WARM)
        elif cmd == "cool":
            await mgr.set_white(args.target, protocol.WHITE_COOL)
        elif cmd == "effect":
            await mgr.set_effect(args.target, _resolve_effect(args.effect))
        elif cmd == "scene":
            await mgr.scene(args.target, args.name)
        else:  # pragma: no cover - argparse guards this
            print(f"unknown command {cmd}", file=sys.stderr)
            return 2
        print(f"ok: {cmd} -> {args.target}")
        return 0
    finally:
        await mgr.close()


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    setup_logging(logging.DEBUG if args.verbose else logging.INFO)
    try:
        return asyncio.run(_run(args))
    except KeyboardInterrupt:
        return 130
    except Exception as err:  # surface a clean message, not a traceback
        logging.getLogger(__name__).debug("command failed", exc_info=True)
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
