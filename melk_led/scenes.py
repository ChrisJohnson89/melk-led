"""High-level scenes / modes built from protocol primitives.

A scene is an ordered list of steps. Each step is a dict with an ``op`` key
naming a :class:`~melk_led.device.MelkDevice` action plus its arguments.
Built-in scenes cover the Hermes modes ("movie", "pet", "gaming", ...);
users can add or override scenes in ``~/.melk-led.toml``.
"""

from __future__ import annotations

from typing import Any

from . import protocol
from .device import MelkDevice

# op name -> (device method name, required arg names)
_OPS: dict[str, tuple[str, tuple[str, ...]]] = {
    "on": ("on", ()),
    "off": ("off", ()),
    "color": ("set_color", ("r", "g", "b")),
    "brightness": ("set_brightness", ("percent",)),
    "white": ("set_white", ("warm_percent",)),
    "effect": ("set_effect", ("effect_id",)),
    "effect_speed": ("set_effect_speed", ("percent",)),
}

# Built-in scenes. Order matters: power on first, then set look.
BUILTIN_SCENES: dict[str, list[dict[str, Any]]] = {
    "rainbow": [
        {"op": "on"},
        {"op": "effect", "effect_id": int(protocol.Effect.RAINBOW_CYCLE)},
        {"op": "effect_speed", "percent": 60},
    ],
    "white": [
        {"op": "on"},
        {"op": "white", "warm_percent": protocol.WHITE_NEUTRAL},
        {"op": "brightness", "percent": 100},
    ],
    "warm": [
        {"op": "on"},
        {"op": "white", "warm_percent": protocol.WHITE_WARM},
        {"op": "brightness", "percent": 80},
    ],
    "cool": [
        {"op": "on"},
        {"op": "white", "warm_percent": protocol.WHITE_COOL},
        {"op": "brightness", "percent": 100},
    ],
    # Hermes semantic modes.
    "office": [
        {"op": "on"},
        {"op": "white", "warm_percent": 35},
        {"op": "brightness", "percent": 100},
    ],
    "movie": [
        {"op": "on"},
        {"op": "color", "r": 255, "g": 80, "b": 15},
        {"op": "brightness", "percent": 20},
    ],
    "pet": [
        {"op": "on"},
        {"op": "white", "warm_percent": 70},
        {"op": "brightness", "percent": 30},
    ],
    "gaming": [
        {"op": "on"},
        {"op": "effect", "effect_id": int(protocol.Effect.COLOR_WAVE)},
        {"op": "effect_speed", "percent": 85},
    ],
}


class SceneError(Exception):
    pass


def all_scenes(user_scenes: dict[str, list[dict[str, Any]]] | None = None) -> dict[str, list[dict[str, Any]]]:
    """Merge built-in scenes with user-defined ones (user wins)."""
    merged = dict(BUILTIN_SCENES)
    if user_scenes:
        merged.update(user_scenes)
    return merged


async def apply_scene(device: MelkDevice, steps: list[dict[str, Any]]) -> None:
    """Run each step of a scene against a connected device."""
    for step in steps:
        op = step.get("op")
        if op not in _OPS:
            raise SceneError(f"unknown scene op: {op!r}")
        method_name, arg_names = _OPS[op]
        try:
            args = [step[name] for name in arg_names]
        except KeyError as err:
            raise SceneError(f"op {op!r} missing argument {err}") from err
        await getattr(device, method_name)(*args)
