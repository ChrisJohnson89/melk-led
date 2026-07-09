"""MELK-OA10 (ELK-BLEDOM / Triones family) BLE wire protocol.

This module is pure and has no BLE dependency, so it can be unit tested
offline. Every function returns a ``bytes`` payload ready to be written to
the write characteristic.

Wire facts (reverse engineered / community validated):

* Write characteristic: ``0000fff3-0000-1000-8000-00805f9b34fb`` (write
  WITHOUT response).
* Read/notify characteristic: ``0000fff4-0000-1000-8000-00805f9b34fb``
  (present, but MELK devices behave as write-only in practice).
* Frame: 9 bytes, prefix ``0x7E``, suffix ``0xEF``. There is NO checksum.
* Login: MELK controllers disconnect unless a login handshake is written
  immediately after connecting (see :data:`LOGIN_SEQUENCE`).

Sources cross-checked:
* https://github.com/dave-code-ruiz/elkbledom (models.json -> MELK-OA10)
* https://github.com/dougppaz/python-bt-led-strip (MELKController)
"""

from __future__ import annotations

from enum import IntEnum

# BLE GATT characteristics.
WRITE_CHARACTERISTIC = "0000fff3-0000-1000-8000-00805f9b34fb"
READ_CHARACTERISTIC = "0000fff4-0000-1000-8000-00805f9b34fb"

# Advertised name prefix used for scan matching.
NAME_PREFIXES = ("MELK", "ELK-BLEDOM", "ELK-BLEDOB", "LEDBLE", "MODELX")

FRAME_PREFIX = 0x7E
FRAME_SUFFIX = 0xEF

# MELK controllers reject all real commands until this handshake is sent
# right after connecting. Each entry is written in order; a short delay
# between them is applied by the caller (see device.py).
LOGIN_SEQUENCE: tuple[bytes, ...] = (
    bytes([0x7E, 0x07, 0x83]),
    bytes([0x7E, 0x04, 0x04]),
)


class Effect(IntEnum):
    """Built-in effect / scene ids for the MELK-Ox effect class.

    Values come from elkbledom ``definitions.json`` -> ``EFFECTS_MELK_Ox``.
    """

    AUTO_PLAY = 0
    MAGIC_BACK = 1
    EFFECT_02 = 2
    EFFECT_03 = 3
    EFFECT_04 = 4
    EFFECT_05 = 5
    RAINBOW_CYCLE = 16
    COLOR_WAVE = 32
    BREATHING = 48
    STROBE = 64
    JUMP_RGB = 128
    FADE_RGB = 144
    BLUE_SCROLL = 207


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, int(value)))


def _frame(*payload: int) -> bytes:
    """Wrap a 9-byte frame and validate every byte is 0-255."""
    frame = bytes(payload)
    if len(frame) != 9:
        raise ValueError(f"frame must be 9 bytes, got {len(frame)}: {frame!r}")
    if frame[0] != FRAME_PREFIX or frame[-1] != FRAME_SUFFIX:
        raise ValueError(f"frame must be 0x7E..0xEF, got {frame.hex()}")
    return frame


def power(on: bool) -> bytes:
    """Turn the controller on or off."""
    if on:
        return _frame(0x7E, 0x04, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF)
    return _frame(0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF)


def color(r: int, g: int, b: int) -> bytes:
    """Set static RGB colour. Each channel is 0-255."""
    r, g, b = (_clamp(c, 0, 255) for c in (r, g, b))
    return _frame(0x7E, 0x00, 0x05, 0x03, r, g, b, 0x00, 0xEF)


def brightness(percent: int) -> bytes:
    """Set brightness as a percentage, 0-100."""
    p = _clamp(percent, 0, 100)
    return _frame(0x7E, 0x04, 0x01, p, 0x01, 0xFF, 0xFF, 0x00, 0xEF)


def color_temperature(warm_percent: int) -> bytes:
    """Set white colour temperature.

    ``warm_percent`` 0-100: 0 = fully cool white, 100 = fully warm white.
    The controller takes complementary warm/cold channel levels.
    """
    warm = _clamp(warm_percent, 0, 100)
    cold = 100 - warm
    return _frame(0x7E, 0x06, 0x05, 0x02, warm, cold, 0xFF, 0x08, 0xEF)


def effect(effect_id: int) -> bytes:
    """Select a built-in effect / scene by id (see :class:`Effect`)."""
    e = _clamp(effect_id, 0, 255)
    return _frame(0x7E, 0x05, 0x03, e, 0x06, 0xFF, 0xFF, 0x00, 0xEF)


def effect_speed(percent: int) -> bytes:
    """Set effect animation speed as a percentage, 0-100."""
    v = _clamp(percent, 0, 100)
    return _frame(0x7E, 0x04, 0x02, v, 0xFF, 0xFF, 0xFF, 0x00, 0xEF)


def query_state() -> bytes:
    """Request a status frame (notify-capable models only)."""
    return _frame(0x7E, 0x00, 0x01, 0xFA, 0x00, 0x00, 0x00, 0x00, 0xEF)


# Convenience named white points expressed as warm_percent.
WHITE_WARM = 100
WHITE_NEUTRAL = 50
WHITE_COOL = 0
