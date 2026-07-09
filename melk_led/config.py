"""Configuration: device aliases, groups, and named scenes.

Config lives at ``~/.melk-led.toml``. Everything is optional; if the file
is absent, only the built-in default scenes are available and devices must
be addressed by MAC.

Example::

    [devices]
    office = "AA:BB:CC:DD:EE:FF"
    desk   = "11:22:33:44:55:66"

    [groups]
    all = ["office", "desk"]

    [scenes.movie]
    steps = [
        { op = "on" },
        { op = "color", r = 255, g = 90, b = 20 },
        { op = "brightness", percent = 25 },
    ]
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

CONFIG_PATH = Path(os.path.expanduser("~/.melk-led.toml"))


@dataclass
class Config:
    devices: dict[str, str] = field(default_factory=dict)  # alias -> MAC
    groups: dict[str, list[str]] = field(default_factory=dict)  # group -> aliases
    scenes: dict[str, list[dict[str, Any]]] = field(default_factory=dict)

    def resolve(self, target: str) -> list[str]:
        """Resolve an alias, group, or raw MAC into a list of MAC addresses."""
        if target in self.groups:
            macs: list[str] = []
            for member in self.groups[target]:
                macs.extend(self.resolve(member))
            return macs
        if target in self.devices:
            return [self.devices[target]]
        # Assume it is already a MAC / UUID address.
        return [target]

    def address_name(self, address: str) -> str:
        for alias, mac in self.devices.items():
            if mac.lower() == address.lower():
                return alias
        return address


def load(path: Path | None = None) -> Config:
    path = path or CONFIG_PATH
    if not path.exists():
        return Config()
    with path.open("rb") as fh:
        raw = tomllib.load(fh)
    scenes: dict[str, list[dict[str, Any]]] = {}
    for name, body in (raw.get("scenes") or {}).items():
        steps = body.get("steps") if isinstance(body, dict) else None
        if isinstance(steps, list):
            scenes[name] = steps
    return Config(
        devices=dict(raw.get("devices") or {}),
        groups={k: list(v) for k, v in (raw.get("groups") or {}).items()},
        scenes=scenes,
    )
