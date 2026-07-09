"""Offline tests for the wire protocol. No BLE hardware required.

Expected byte sequences are pinned against the community-validated
MELK-OA10 command table (elkbledom models.json + python-bt-led-strip).
"""

from melk_led import protocol


def hx(b: bytes) -> str:
    return b.hex(" ")


def test_frame_shape():
    for fn in (protocol.power(True), protocol.color(1, 2, 3), protocol.brightness(50)):
        assert len(fn) == 9
        assert fn[0] == 0x7E
        assert fn[-1] == 0xEF


def test_power():
    assert hx(protocol.power(True)) == "7e 04 04 f0 00 01 ff 00 ef"
    assert hx(protocol.power(False)) == "7e 04 04 00 00 00 ff 00 ef"


def test_color():
    assert hx(protocol.color(255, 0, 0)) == "7e 00 05 03 ff 00 00 00 ef"
    assert hx(protocol.color(0, 128, 255)) == "7e 00 05 03 00 80 ff 00 ef"


def test_color_clamps():
    assert hx(protocol.color(999, -5, 300)) == "7e 00 05 03 ff 00 ff 00 ef"


def test_brightness():
    assert hx(protocol.brightness(100)) == "7e 04 01 64 01 ff ff 00 ef"
    assert hx(protocol.brightness(0)) == "7e 04 01 00 01 ff ff 00 ef"
    # out of range clamps to 0-100
    assert protocol.brightness(150)[3] == 100
    assert protocol.brightness(-1)[3] == 0


def test_color_temperature():
    # warm=100 -> warm channel 100, cold 0
    assert hx(protocol.color_temperature(100)) == "7e 06 05 02 64 00 ff 08 ef"
    # cool
    assert hx(protocol.color_temperature(0)) == "7e 06 05 02 00 64 ff 08 ef"
    # neutral
    assert hx(protocol.color_temperature(50)) == "7e 06 05 02 32 32 ff 08 ef"


def test_effect():
    assert hx(protocol.effect(int(protocol.Effect.RAINBOW_CYCLE))) == "7e 05 03 10 06 ff ff 00 ef"


def test_effect_speed():
    assert hx(protocol.effect_speed(60)) == "7e 04 02 3c ff ff ff 00 ef"


def test_login_sequence():
    assert [f.hex(" ") for f in protocol.LOGIN_SEQUENCE] == ["7e 07 83", "7e 04 04"]


def test_effect_enum_values():
    # Guard the ids we surface as scenes.
    assert protocol.Effect.RAINBOW_CYCLE == 16
    assert protocol.Effect.COLOR_WAVE == 32
    assert protocol.Effect.BREATHING == 48
