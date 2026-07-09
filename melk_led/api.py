"""REST API for controlling MELK controllers (Phase 5) plus a natural
language endpoint for Hermes (Phase 6).

Run with::

    uvicorn melk_led.api:app --host 127.0.0.1 --port 8765

Or ``python -m melk_led.api``.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import load_config, protocol, setup_logging
from .manager import MelkManager
from .nlu import parse_command
from .scenes import all_scenes

_LOGGER = logging.getLogger(__name__)

_manager: MelkManager | None = None


def manager() -> MelkManager:
    assert _manager is not None, "manager not initialised"
    return _manager


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _manager
    setup_logging()
    _manager = MelkManager(load_config())
    _LOGGER.info("melk_led API ready")
    try:
        yield
    finally:
        await _manager.close()
        _manager = None


app = FastAPI(title="melk-led", version="0.1.0", lifespan=lifespan)


# -- request models --------------------------------------------------------

class TargetBody(BaseModel):
    target: str = Field(default="all", description="alias, group, or MAC")


class ColorBody(TargetBody):
    r: int = Field(ge=0, le=255)
    g: int = Field(ge=0, le=255)
    b: int = Field(ge=0, le=255)


class BrightnessBody(TargetBody):
    percent: int = Field(ge=0, le=100)


class SceneBody(TargetBody):
    name: str


class EffectBody(TargetBody):
    effect: str = Field(description="effect id or name, e.g. RAINBOW_CYCLE")


class HermesBody(BaseModel):
    command: str = Field(description='natural language, e.g. "office lights on"')


def _ok(action: str, target: str) -> dict:
    return {"status": "ok", "action": action, "target": target}


async def _guard(coro):
    try:
        return await coro
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err))
    except Exception as err:  # BLE / connection failures
        raise HTTPException(status_code=502, detail=str(err))


# -- endpoints -------------------------------------------------------------

@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/scenes")
async def list_scenes() -> dict:
    return {"scenes": sorted(all_scenes(manager().config.scenes))}


@app.get("/devices")
async def list_devices() -> dict:
    cfg = manager().config
    return {"devices": cfg.devices, "groups": cfg.groups}


@app.post("/lights/on")
async def lights_on(body: TargetBody) -> dict:
    await _guard(manager().on(body.target))
    return _ok("on", body.target)


@app.post("/lights/off")
async def lights_off(body: TargetBody) -> dict:
    await _guard(manager().off(body.target))
    return _ok("off", body.target)


@app.post("/lights/color")
async def lights_color(body: ColorBody) -> dict:
    await _guard(manager().set_color(body.target, body.r, body.g, body.b))
    return _ok(f"color({body.r},{body.g},{body.b})", body.target)


@app.post("/lights/brightness")
async def lights_brightness(body: BrightnessBody) -> dict:
    await _guard(manager().set_brightness(body.target, body.percent))
    return _ok(f"brightness({body.percent})", body.target)


@app.post("/lights/scene")
async def lights_scene(body: SceneBody) -> dict:
    await _guard(manager().scene(body.target, body.name))
    return _ok(f"scene({body.name})", body.target)


@app.post("/lights/effect")
async def lights_effect(body: EffectBody) -> dict:
    try:
        effect_id = int(body.effect)
    except ValueError:
        try:
            effect_id = int(protocol.Effect[body.effect.upper()])
        except KeyError:
            raise HTTPException(status_code=400, detail=f"unknown effect {body.effect!r}")
    await _guard(manager().set_effect(body.target, effect_id))
    return _ok(f"effect({body.effect})", body.target)


@app.post("/hermes")
async def hermes(body: HermesBody) -> dict:
    """Natural-language entry point for Hermes.

    Accepts phrases like "office lights on", "movie mode", "gaming mode",
    "kitchen lights color 255 0 0", "all lights brightness 40".
    """
    intent = parse_command(body.command, manager().config, all_scenes(manager().config.scenes))
    if intent is None:
        raise HTTPException(status_code=422, detail=f"could not understand: {body.command!r}")
    await _guard(intent.execute(manager()))
    return {"status": "ok", "understood": intent.describe(), "command": body.command}


def main() -> None:  # pragma: no cover
    import uvicorn
    setup_logging()
    uvicorn.run(app, host="127.0.0.1", port=8765)


if __name__ == "__main__":  # pragma: no cover
    main()
