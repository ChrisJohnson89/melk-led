# melk-led

Native, local, app-free control of **MELK-OA10** BLE LED controllers from macOS
(or any Bleak-supported OS). No cloud, no official app, no REST-key requirement.
Built for direct use, a REST API, and Hermes voice/agent control.

The MELK-OA10 belongs to the **ELK-BLEDOM / Triones** controller family. Its
BLE protocol is fully documented in [AGENTS.md](AGENTS.md).

## Native macOS app

The polished, standalone desktop app lives in [`macos-app/`](macos-app/) — a
SwiftUI + CoreBluetooth application that declares its own Bluetooth usage
string, so it sidesteps all the Homebrew-Python / py2app / TCC friction the CLI
needs on macOS. It is the **single BLE owner** and exposes a local HTTP
endpoint on `127.0.0.1:8765` that this Python CLI and Hermes call. See
[macos-app/README.md](macos-app/README.md). The Python package below remains
the reference protocol implementation, CLI, and automation surface.

## Install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[api,dev]"
```

## Quick start

```bash
# 1. Find your controllers (grab the address column):
lights scan

# 2. Save aliases so you can say "office" instead of a MAC:
cp melk-led.example.toml ~/.melk-led.toml && $EDITOR ~/.melk-led.toml

# 3. Control them:
lights --target office on
lights --target office color 255 0 0
lights --target office brightness 40
lights --target all scene movie
lights white          # warm / cool also work
lights scene rainbow
```

### Confirm the protocol on your hardware

```bash
python scripts/selftest.py        # cycles through every command visibly
```

## REST API (Phase 5)

```bash
melk-led-api          # serves http://127.0.0.1:8765
# or: uvicorn melk_led.api:app --port 8765
```

| Method | Path | Body |
|---|---|---|
| POST | `/lights/on` | `{"target":"office"}` |
| POST | `/lights/off` | `{"target":"office"}` |
| POST | `/lights/color` | `{"target":"office","r":255,"g":0,"b":0}` |
| POST | `/lights/brightness` | `{"target":"all","percent":40}` |
| POST | `/lights/scene` | `{"target":"office","name":"movie"}` |
| POST | `/lights/effect` | `{"target":"office","effect":"RAINBOW_CYCLE"}` |
| POST | `/hermes` | `{"command":"office lights on"}` |
| GET | `/scenes`, `/devices`, `/health` | — |

`target` defaults to `all` if omitted.

## Hermes integration (Phase 6)

Point Hermes at the single natural-language endpoint. It understands device
aliases, groups, colours, brightness, white temperature, and named modes:

```bash
curl -sX POST localhost:8765/hermes -H 'content-type: application/json' \
     -d '{"command":"office lights on"}'
curl -sX POST localhost:8765/hermes -d '{"command":"movie mode"}'
curl -sX POST localhost:8765/hermes -d '{"command":"gaming mode"}'
curl -sX POST localhost:8765/hermes -d '{"command":"all lights brightness 30"}'
curl -sX POST localhost:8765/hermes -d '{"command":"make the desk lights blue"}'
```

Add or rename modes in `~/.melk-led.toml` under `[scenes.*]` — they are exposed
to Hermes automatically. Built-in modes: `office`, `movie`, `pet`, `gaming`,
`rainbow`, `white`, `warm`, `cool`.

## Python library

```python
import asyncio
from melk_led import MelkDevice

async def main():
    async with MelkDevice("AA:BB:CC:DD:EE:FF") as dev:
        await dev.on()
        await dev.set_color(255, 0, 0)

asyncio.run(main())
```

## Testing

```bash
pytest          # offline; no hardware needed
```

## macOS: how to run BLE commands

Modern macOS (14+/26) **hard-crashes** any process that touches Bluetooth
unless the running binary declares a Bluetooth usage string. Homebrew's
Python does not, and a direct `python script.py` reads the usage string
from the Mach-O `__info_plist` section (which Homebrew omits) — so it
aborts with a TCC "privacy violation" before doing anything.

The fix is two steps, done once:

```bash
# 1. Add the usage string to Python.app's Info.plist and re-sign it.
bash scripts/fix_macos_bluetooth.sh "$(command -v python)"
```

Then run BLE commands through the **bundle launcher**, which starts the
interpreter via LaunchServices so macOS reads that Info.plist:

```bash
./scripts/lights-bundle scan
./scripts/lights-bundle scripts/selftest.py
./scripts/lights-bundle --target office on
```

The **first** BLE command shows a one-time Bluetooth permission prompt
(our usage string). Click Allow. After that everything works; re-run
`fix_macos_bluetooth.sh` only after a `brew upgrade python@3.14`.

Directly-run `lights ...` / `pytest` still work for everything that does
not open Bluetooth (scenes listing, config, the whole test suite).

On macOS, Bleak reports a CoreBluetooth **UUID** rather than a MAC address.
Use whatever `scan` prints as the device address in `~/.melk-led.toml`.

> The durable production alternative (survives brew upgrades) is to ship
> this as a signed `.app` via py2app with the Bluetooth key baked into its
> own Info.plist — planned Phase 6 hardening.
