"""Offline tests for the Hermes NLU parser and scene engine."""

import pytest

from melk_led.config import Config
from melk_led.nlu import parse_command
from melk_led.scenes import all_scenes, apply_scene, BUILTIN_SCENES


@pytest.fixture
def config():
    return Config(
        devices={"office": "AA:BB:CC:DD:EE:FF", "desk": "11:22:33:44:55:66"},
        groups={"all": ["office", "desk"]},
    )


@pytest.fixture
def catalog(config):
    return all_scenes(config.scenes)


def parse(text, config, catalog):
    return parse_command(text, config, catalog)


def test_target_detection(config, catalog):
    i = parse("office lights on", config, catalog)
    assert i.action == "on" and i.target == "office"


def test_default_target_is_all(config, catalog):
    i = parse("lights on", config, catalog)
    assert i.target == "all"


def test_off(config, catalog):
    assert parse("turn the desk lights off", config, catalog).action == "off"
    assert parse("desk lights off", config, catalog).target == "desk"


def test_scene_modes(config, catalog):
    for phrase, scene in [
        ("movie mode", "movie"),
        ("gaming mode please", "gaming"),
        ("set pet mode", "pet"),
        ("rainbow", "rainbow"),
    ]:
        i = parse(phrase, config, catalog)
        assert i.action == "scene" and i.params["scene"] == scene


def test_color_numeric(config, catalog):
    i = parse("office lights color 255 0 0", config, catalog)
    assert i.action == "color" and (i.params["r"], i.params["g"], i.params["b"]) == (255, 0, 0)


def test_color_named(config, catalog):
    i = parse("make the office lights red", config, catalog)
    assert i.action == "color" and i.params["color"] == "red"


def test_brightness(config, catalog):
    assert parse("brightness 40", config, catalog).params["percent"] == 40
    assert parse("dim to 20", config, catalog).params["percent"] == 20
    assert parse("set office to 75%", config, catalog).params["percent"] == 75


def test_white_temperatures(config, catalog):
    assert parse("warm white", config, catalog).params["warm"] == 100
    assert parse("cool white", config, catalog).params["warm"] == 0
    assert parse("just white", config, catalog).params["warm"] == 50


def test_unparseable(config, catalog):
    assert parse("do a barrel roll", config, catalog) is None


def test_builtin_scenes_have_required_modes():
    for mode in ("office", "movie", "pet", "gaming", "rainbow", "white", "warm", "cool"):
        assert mode in BUILTIN_SCENES


class _FakeDevice:
    def __init__(self):
        self.calls = []

    async def on(self):
        self.calls.append(("on",))

    async def off(self):
        self.calls.append(("off",))

    async def set_color(self, r, g, b):
        self.calls.append(("color", r, g, b))

    async def set_brightness(self, p):
        self.calls.append(("brightness", p))

    async def set_white(self, w):
        self.calls.append(("white", w))

    async def set_effect(self, e):
        self.calls.append(("effect", e))

    async def set_effect_speed(self, p):
        self.calls.append(("effect_speed", p))


async def test_apply_scene_movie():
    dev = _FakeDevice()
    await apply_scene(dev, BUILTIN_SCENES["movie"])
    assert dev.calls[0] == ("on",)
    assert ("color", 255, 80, 15) in dev.calls
    assert ("brightness", 20) in dev.calls
