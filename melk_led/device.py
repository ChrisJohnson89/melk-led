"""Async BLE control of a single MELK-OA10 controller via Bleak."""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from bleak import BleakClient, BleakScanner
from bleak.backends.device import BLEDevice
from bleak.exc import BleakError

from . import protocol

_LOGGER = logging.getLogger(__name__)

# Delay between the two login frames. MELK firmware is picky; ~1s is what
# the reference implementations use and what works reliably in practice.
LOGIN_STEP_DELAY = 1.0

DEFAULT_CONNECT_TIMEOUT = 20.0
DEFAULT_RETRIES = 3
RETRY_BACKOFF = 0.5


class MelkError(Exception):
    """Base error for MELK device operations."""


class NotConnectedError(MelkError):
    """Raised when an operation needs a connection that is not established."""


class MelkDevice:
    """A single MELK LED controller.

    Manages connection lifecycle, the mandatory login handshake, and
    resilient writes with automatic reconnect + retry.

    Usage::

        dev = MelkDevice("AA:BB:CC:DD:EE:FF", name="office")
        async with dev:
            await dev.on()
            await dev.set_color(255, 0, 0)
    """

    def __init__(
        self,
        address: str,
        name: Optional[str] = None,
        *,
        connect_timeout: float = DEFAULT_CONNECT_TIMEOUT,
        retries: int = DEFAULT_RETRIES,
        ble_device: Optional[BLEDevice] = None,
    ) -> None:
        self.address = address
        self.name = name or address
        self._connect_timeout = connect_timeout
        self._retries = max(1, retries)
        self._ble_device = ble_device
        self._client: Optional[BleakClient] = None
        self._lock = asyncio.Lock()

    # -- lifecycle ---------------------------------------------------------

    @property
    def is_connected(self) -> bool:
        return self._client is not None and self._client.is_connected

    async def __aenter__(self) -> "MelkDevice":
        await self.connect()
        return self

    async def __aexit__(self, *exc) -> None:
        await self.disconnect()

    async def connect(self) -> None:
        """Connect and perform the MELK login handshake."""
        async with self._lock:
            await self._connect_locked()

    async def _connect_locked(self) -> None:
        if self.is_connected:
            return
        target: BLEDevice | str = self._ble_device or self.address
        _LOGGER.info("%s: connecting to %s", self.name, self.address)

        def _on_disconnect(_client: BleakClient) -> None:
            _LOGGER.warning("%s: disconnected", self.name)

        client = BleakClient(
            target,
            timeout=self._connect_timeout,
            disconnected_callback=_on_disconnect,
        )
        await client.connect()
        self._client = client
        try:
            await self._login()
        except Exception:
            # A device that won't accept login is useless; drop the link.
            await self._safe_disconnect()
            raise
        _LOGGER.info("%s: connected and logged in", self.name)

    async def _login(self) -> None:
        """Send the handshake MELK requires right after connecting."""
        _LOGGER.debug("%s: running login sequence", self.name)
        for i, frame in enumerate(protocol.LOGIN_SEQUENCE):
            await self._raw_write(frame)
            if i < len(protocol.LOGIN_SEQUENCE) - 1:
                await asyncio.sleep(LOGIN_STEP_DELAY)
        await asyncio.sleep(LOGIN_STEP_DELAY)

    async def disconnect(self) -> None:
        async with self._lock:
            await self._safe_disconnect()

    async def _safe_disconnect(self) -> None:
        client, self._client = self._client, None
        if client is None:
            return
        try:
            if client.is_connected:
                await client.disconnect()
        except BleakError as err:
            _LOGGER.debug("%s: error during disconnect: %s", self.name, err)

    # -- writes ------------------------------------------------------------

    async def _raw_write(self, data: bytes) -> None:
        if self._client is None:
            raise NotConnectedError(f"{self.name}: not connected")
        await self._client.write_gatt_char(
            protocol.WRITE_CHARACTERISTIC, data, response=False
        )
        _LOGGER.debug("%s: wrote %s", self.name, data.hex(" "))

    async def _send(self, data: bytes) -> None:
        """Write a command, reconnecting and retrying on failure."""
        last_err: Optional[Exception] = None
        for attempt in range(1, self._retries + 1):
            async with self._lock:
                try:
                    if not self.is_connected:
                        await self._connect_locked()
                    await self._raw_write(data)
                    return
                except (BleakError, NotConnectedError, asyncio.TimeoutError) as err:
                    last_err = err
                    _LOGGER.warning(
                        "%s: write failed (attempt %d/%d): %s",
                        self.name, attempt, self._retries, err,
                    )
                    await self._safe_disconnect()
            if attempt < self._retries:
                await asyncio.sleep(RETRY_BACKOFF * attempt)
        raise MelkError(f"{self.name}: command failed after {self._retries} attempts: {last_err}")

    # -- high level commands ----------------------------------------------

    async def on(self) -> None:
        await self._send(protocol.power(True))

    async def off(self) -> None:
        await self._send(protocol.power(False))

    async def set_color(self, r: int, g: int, b: int) -> None:
        await self._send(protocol.color(r, g, b))

    async def set_brightness(self, percent: int) -> None:
        await self._send(protocol.brightness(percent))

    async def set_white(self, warm_percent: int = protocol.WHITE_NEUTRAL) -> None:
        await self._send(protocol.color_temperature(warm_percent))

    async def set_effect(self, effect_id: int) -> None:
        await self._send(protocol.effect(effect_id))

    async def set_effect_speed(self, percent: int) -> None:
        await self._send(protocol.effect_speed(percent))


async def scan(timeout: float = 6.0) -> list[BLEDevice]:
    """Scan for nearby MELK-family controllers.

    Returns the matching ``BLEDevice`` objects (by advertised name prefix).
    """
    _LOGGER.info("scanning for MELK devices (%.0fs)...", timeout)
    devices = await BleakScanner.discover(timeout=timeout)
    matches = [
        d for d in devices
        if d.name and d.name.upper().startswith(protocol.NAME_PREFIXES)
    ]
    for d in matches:
        _LOGGER.info("found %s (%s)", d.name, d.address)
    return matches
