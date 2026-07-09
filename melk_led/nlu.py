"""Tiny deterministic natural-language parser for Hermes commands.

Turns phrases like "office lights on", "movie mode", or "kitchen lights
color 255 0 0" into an :class:`Intent` that the manager can execute. It is
intentionally rule-based (no network, no LLM) so Hermes gets fast, stable,
offline behaviour.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

from . import protocol
from .config import Config
from .manager import MelkManager

# Named colours -> RGB.
_COLORS: dict[str, tuple[int, int, int]] = {
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "white": (255, 255, 255),
    "yellow": (255, 255, 0),
    "orange": (255, 100, 0),
    "purple": (160, 0, 255),
    "pink": (255, 50, 150),
    "cyan": (0, 255, 255),
    "magenta": (255, 0, 255),
}


@dataclass
class Intent:
    action: str
    target: str
    params: dict[str, Any]
    _run: Callable[[MelkManager], Awaitable[None]]

    def execute(self, mgr: MelkManager) -> Awaitable[None]:
        return self._run(mgr)

    def describe(self) -> str:
        if self.params:
            detail = " ".join(f"{k}={v}" for k, v in self.params.items())
            return f"{self.action} {self.target} ({detail})"
        return f"{self.action} {self.target}"


def _find_target(text: str, config: Config) -> str:
    """Pick the best-matching device alias or group mentioned in text."""
    candidates = list(config.devices) + list(config.groups)
    # Longest names first so "living room" wins over "room".
    for name in sorted(candidates, key=len, reverse=True):
        if re.search(rf"\b{re.escape(name.lower())}\b", text):
            return name
    return "all"


def parse_command(
    command: str,
    config: Config,
    scene_catalog: dict[str, list[dict[str, Any]]],
) -> Intent | None:
    text = command.strip().lower()
    if not text:
        return None
    target = _find_target(text, config)

    def intent(action: str, run: Callable[[MelkManager], Awaitable[None]], **params: Any) -> Intent:
        return Intent(action=action, target=target, params=params, _run=run)

    # Scenes / modes: "movie mode", "gaming", "pet mode", "rainbow".
    # Reserved words are handled by the primitive branches below, and scene
    # names that collide with a device/group alias are treated as targets
    # unless the user says "<name> mode" explicitly.
    reserved = {"warm", "cool", "cold", "white", "on", "off", "up", "out", "shut"}
    for name in sorted(scene_catalog, key=len, reverse=True):
        if re.search(rf"\b{re.escape(name)}\s+mode\b", text):
            return intent("scene", lambda m, n=name: m.scene(target, n), scene=name)
        if name in reserved or name in config.devices or name in config.groups:
            continue
        if re.search(rf"\b{re.escape(name)}\b", text):
            return intent("scene", lambda m, n=name: m.scene(target, n), scene=name)

    # Explicit color: "color 255 0 0".
    m = re.search(r"colou?r\s+(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})", text)
    if m:
        r, g, b = (int(x) for x in m.groups())
        return intent("color", lambda mgr: mgr.set_color(target, r, g, b), r=r, g=g, b=b)

    # Named color: "make it red". ('white' is a temperature, handled below.)
    for cname, (r, g, b) in _COLORS.items():
        if cname == "white":
            continue
        if re.search(rf"\b{cname}\b", text):
            return intent("color", lambda mgr, r=r, g=g, b=b: mgr.set_color(target, r, g, b), color=cname)

    # Brightness: "brightness 40", "40%", "dim to 20".
    m = re.search(r"(?:brightness|dim(?:\s+to)?|set\s+to)\s+(\d{1,3})", text) or re.search(r"\b(\d{1,3})\s*%", text)
    if m:
        pct = max(0, min(100, int(m.group(1))))
        return intent("brightness", lambda mgr: mgr.set_brightness(target, pct), percent=pct)

    # White temperatures.
    if "warm" in text:
        return intent("white", lambda mgr: mgr.set_white(target, protocol.WHITE_WARM), warm=100)
    if "cool" in text or "cold" in text:
        return intent("white", lambda mgr: mgr.set_white(target, protocol.WHITE_COOL), warm=0)
    if "white" in text:
        return intent("white", lambda mgr: mgr.set_white(target, protocol.WHITE_NEUTRAL), warm=50)

    # Power. Check off before on ("turn off" contains no "on" token issue).
    if re.search(r"\b(off|out|shut)\b", text):
        return intent("off", lambda mgr: mgr.off(target))
    if re.search(r"\b(on|up)\b", text):
        return intent("on", lambda mgr: mgr.on(target))

    return None
