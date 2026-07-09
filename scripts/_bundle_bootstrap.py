"""In-bundle bootstrap.

Launched *inside* the framework's Python.app via LaunchServices (`open`) so
macOS reads the Bluetooth usage string from the bundle Info.plist and does
not TCC-crash. The app's Python is the same interpreter our venv is built
on, so we just splice the venv's site-packages onto sys.path and hand off.

argv: _bundle_bootstrap.py <venv_site_packages> <target> [args...]
  target ending in .py  -> run that script as __main__
  otherwise             -> run melk_led.cli.main([target, *args])
"""

import runpy
import site
import sys

venv_site = sys.argv[1]
site.addsitedir(venv_site)  # processes .pth files (editable install, bleak)

# Activate as a regular GUI app so macOS can present BLE permission dialogs.
# Without this, macOS 15+ silently denies CBCentralManager initialisation
# when launched via `open -W` without a foreground UI session.
try:
    from AppKit import NSApplication, NSApplicationActivationPolicyRegular  # type: ignore
    _ns_app = NSApplication.sharedApplication()
    _ns_app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    _ns_app.activateIgnoringOtherApps_(True)
except Exception:
    pass

rest = sys.argv[2:]
if rest and rest[0].endswith(".py"):
    script = rest[0]
    sys.argv = [script, *rest[1:]]
    runpy.run_path(script, run_name="__main__")
else:
    from melk_led.cli import main
    raise SystemExit(main(rest))
