#!/usr/bin/env bash
# Fix the macOS "TCC crash: attempted to access privacy-sensitive data
# without a usage description" (SIGABRT) that happens when a Homebrew /
# framework Python touches CoreBluetooth.
#
# macOS refuses to let any process near Bluetooth unless its Info.plist
# declares NSBluetoothAlwaysUsageDescription. Homebrew's Python.app ships
# without it, so the interpreter is killed the moment Bleak starts scanning.
# We add the key to Python.app/Contents/Info.plist and re-sign ad-hoc.
#
# Re-run this after `brew upgrade python@3.14` (upgrades reset the plist).
#
# Usage:  scripts/fix_macos_bluetooth.sh [path-to-python]
set -euo pipefail

PYBIN="${1:-$(command -v python3)}"
DESC="melk-led controls your Bluetooth LED light controllers."

BASE_PREFIX="$("$PYBIN" -c 'import sys; print(sys.base_prefix)')"
APP="$BASE_PREFIX/Resources/Python.app"
PLIST="$APP/Contents/Info.plist"

if [[ ! -f "$PLIST" ]]; then
    echo "error: $PLIST not found." >&2
    echo "This Python has no Python.app bundle; use a framework build" >&2
    echo "(python.org installer or 'brew install python') for BLE on macOS." >&2
    exit 1
fi

echo "Patching: $PLIST"
cp -n "$PLIST" "$PLIST.melkbak" 2>/dev/null || true

set_key() {
    local key="$1" val="$2"
    if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :$key $val" "$PLIST"
    else
        /usr/libexec/PlistBuddy -c "Add :$key string $val" "$PLIST"
    fi
}

set_key "NSBluetoothAlwaysUsageDescription" "$DESC"
set_key "NSBluetoothPeripheralUsageDescription" "$DESC"

echo "Re-signing ad-hoc (deep): $APP"
# --deep re-signs all nested executables/frameworks first so the outer bundle
# seal is consistent with the modified Info.plist.  Without --deep the inner
# binary retains its original Homebrew signature whose resource hash still
# covers the old plist; macOS TCC then rejects the bundle with -67030
# (errSecCSSignatureFailed) and never shows the Bluetooth permission dialog.
codesign --force --deep --sign - "$APP"

echo
echo "Verifying:"
/usr/libexec/PlistBuddy -c "Print :NSBluetoothAlwaysUsageDescription" "$PLIST"
codesign --verify --verbose=1 "$APP" 2>&1 && echo "signature: OK" || echo "WARNING: signature still invalid"
codesign -dv "$APP" 2>&1 | grep -E 'Signature|Identifier' || true

echo
echo "Done. The FIRST BLE command will now show a Bluetooth permission"
echo "prompt instead of crashing. Approve it (and, if asked, enable your"
echo "terminal under System Settings > Privacy & Security > Bluetooth)."
