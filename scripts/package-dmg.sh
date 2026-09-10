#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$(pwd)/build/XB30-Control.app"
output="$(pwd)/build/XB30-Controller.dmg"
python_bin="${DMG_PYTHON:-python3}"
[[ -d "$app" ]] || { echo 'Build the app first.' >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
xcrun swift packaging/dmg/render-background.swift "$work/background.png" packaging/dmg/watermark.png packaging/dmg/arrow.jpeg packaging/dmg/layout.json
"$python_bin" - "$work" <<'PY'
import plistlib, sys
from pathlib import Path
(Path(sys.argv[1]) / '\u2063.webloc').write_bytes(plistlib.dumps({'URL':'https://binarybears.com/'}))
PY
xcrun swift packaging/dmg/set-file-icon.swift "$work/⁣.webloc" packaging/dmg/website-icon.png 70 104
"$python_bin" -m dmgbuild -s packaging/dmg/settings.py -D "layout=$(pwd)/packaging/dmg/layout.json" -D "app=$app" -D "background=$work/background.png" -D "website=$work/⁣.webloc" 'XB30 Controller Installer' "$output"
if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$MACOS_SIGN_IDENTITY" "$output"
  codesign --verify --strict "$output"
fi
hdiutil verify "$output" >/dev/null
(cd build && shasum -a 256 XB30-Controller.dmg > XB30-Controller.dmg.sha256)
echo "DMG ready: $output"
