"""Manage multiple MELK controllers and dispatch commands to groups."""

from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable

from .config import Config
from .device import MelkDevice
from . import scenes

_LOGGER = logging.getLogger(__name__)


class MelkManager:
    """Owns a pool of :class:`MelkDevice` instances keyed by address.

    Devices are created lazily and reused, so connections persist across
    commands (important: reconnecting for every command is slow and flaky).
    """

    def __init__(self, config: Config | None = None) -> None:
        self.config = config or Config()
        self._devices: dict[str, MelkDevice] = {}

    def device(self, address: str) -> MelkDevice:
        dev = self._devices.get(address)
        if dev is None:
            dev = MelkDevice(address, name=self.config.address_name(address))
            self._devices[address] = dev
        return dev

    def resolve_devices(self, target: str) -> list[MelkDevice]:
        return [self.device(mac) for mac in self.config.resolve(target)]

    async def _fan_out(
        self, target: str, action: Callable[[MelkDevice], Awaitable[None]]
    ) -> None:
        devices = self.resolve_devices(target)
        if not devices:
            raise ValueError(f"no devices resolved for target {target!r}")
        results = await asyncio.gather(
            *(action(d) for d in devices), return_exceptions=True
        )
        errors = [(d.name, r) for d, r in zip(devices, results) if isinstance(r, Exception)]
        for name, err in errors:
            _LOGGER.error("%s: %s", name, err)
        if errors and len(errors) == len(devices):
            raise errors[0][1]

    # -- command surface (mirrors MelkDevice) -----------------------------

    async def on(self, target: str) -> None:
        await self._fan_out(target, lambda d: d.on())

    async def off(self, target: str) -> None:
        await self._fan_out(target, lambda d: d.off())

    async def set_color(self, target: str, r: int, g: int, b: int) -> None:
        await self._fan_out(target, lambda d: d.set_color(r, g, b))

    async def set_brightness(self, target: str, percent: int) -> None:
        await self._fan_out(target, lambda d: d.set_brightness(percent))

    async def set_white(self, target: str, warm_percent: int) -> None:
        await self._fan_out(target, lambda d: d.set_white(warm_percent))

    async def set_effect(self, target: str, effect_id: int) -> None:
        await self._fan_out(target, lambda d: d.set_effect(effect_id))

    async def scene(self, target: str, name: str) -> None:
        catalog = scenes.all_scenes(self.config.scenes)
        if name not in catalog:
            raise ValueError(f"unknown scene {name!r}; known: {sorted(catalog)}")
        steps = catalog[name]
        await self._fan_out(target, lambda d: scenes.apply_scene(d, steps))

    async def close(self) -> None:
        await asyncio.gather(
            *(d.disconnect() for d in self._devices.values()),
            return_exceptions=True,
        )
