#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${NOTARY_PROFILE:?Missing notarization profile}"
: "${SIGNING_KEYCHAIN:?Missing ephemeral signing keychain}"
: "${MACOS_SIGN_IDENTITY:?Missing Developer ID identity}"
app=build/XB30-Control.app
dmg=build/XB30-Controller.dmg
notarize() {
  local artifact="$1" result="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --keychain "$SIGNING_KEYCHAIN" --wait --timeout 25m --output-format json > "$result"
  python3 - "$result" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization did not accept this artifact; release stopped.')
print('Apple notarization: Accepted')
PY
}
ditto -c -k --keepParent "$app" build/notary-app.zip
notarize build/notary-app.zip build/notary-app-result.json
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
scripts/package-dmg.sh
notarize "$dmg" build/notary-dmg-result.json
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
(cd build && shasum -a 256 XB30-Controller.dmg > XB30-Controller.dmg.sha256)
