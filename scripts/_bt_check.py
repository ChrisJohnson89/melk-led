"""No-BLE sanity check run inside the bundle.

Confirms: (1) LaunchServices bundle launch works, (2) venv packages import,
(3) CoreBluetooth is reachable WITHOUT a TCC crash. Reading CBManager
authorization does not start scanning and does not show a prompt.
"""

import sys

from importlib.metadata import version  # noqa: E402

print("python:", sys.version.split()[0], sys.executable)

import bleak  # noqa: E402,F401
print("bleak:", version("bleak"))

import melk_led  # noqa: E402
print("melk_led:", melk_led.__version__)

try:
    from CoreBluetooth import CBManager  # type: ignore  # noqa: E402
    # 0 notDetermined, 1 restricted, 2 denied, 3 allowedAlways
    status = CBManager.authorization()
    names = {0: "notDetermined", 1: "restricted", 2: "denied", 3: "allowedAlways"}
    print("bluetooth_authorization:", status, names.get(status, "?"))
    print("RESULT: OK (no crash) — CoreBluetooth reachable through the bundle")
except Exception as e:  # pragma: no cover
    print("RESULT: import/auth error:", type(e).__name__, e)
