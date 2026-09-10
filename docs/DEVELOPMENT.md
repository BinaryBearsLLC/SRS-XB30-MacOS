# Development and releases

## Build and test

Xcode 26 with the macOS 26 SDK is required to preserve the reviewed native control appearance. GitHub native builds explicitly select Xcode 26.6 on macos-26; the deployment target remains macOS 13. Older SDKs silently opt the app into legacy controls even on Tahoe, so build.sh rejects them. `./build.sh` produces a universal app in `build/XB30-Control.app`, targeting macOS 13. `./test.sh --ui` runs protocol/controller/log regressions and renders native UI previews. `./hardware-test.sh --exercise` and `./hardware-test.sh --controller` require the paired speaker and change its settings; do not run them as ordinary CI.

The app uses a native SwiftUI/AppKit menu bar popover. Its hosting controller follows content size: about 440×443 pt closed and 440×575 pt with EQ. Left-click opens the panel; right-click exposes Quit. No appearance selector or internal scrolling.

The web demo lives in `website/`: `npm ci`, `npm run dev`, `npm run build`; `node app/lighting.test.mjs` checks the 13 lighting modes. `python3 scripts/sync-web-controls.py` refreshes shared native labels/help. GitHub Pages publishes the static Vite build from `main`; `PAGES_BASE_PATH` comes from configure-pages, so model, music and artwork work under the repository subpath. No server or ChatGPT hosting is required.

## Device behavior and protocol

[protocol.json](protocol.json) records verified commands. Scope is Sony SRS-XB30, observed firmware 1.00 and Music Center 7.6.1. macOS publishes the `com.sony.songpal.tandem` RFCOMM service; the speaker connects to the Mac. Do not guess an Android channel or treat an ACK as proof a setting changed. Writes are queued/coalesced, followed by matching readback. Unsolicited notifications update the UI immediately.

- Volume capability declares 51 levels, 0–50. Andrea confirmed 100% at full charge both on AC and battery. Earlier readbacks stopped at 46/50; this is not a universal maximum. The app displays a device-imposed adjustment in orange with help. The battery threshold remains unknown.
- Extra Bass and ClearAudio+ are linked. Enabling either enables both; direct ClearAudio+ OFF is ignored while locked. Flat disables both and enables manual EQ. Only the preset is exposed in the UI.
- Battery uses approximate text, including “Fully charged”. No reliable charging flag or negotiated-codec query has been verified. Auto/SBC is a preference. Bluetooth standby and physical Play/Pause were confirmed by the user; manual Auto standby verification is deferred.
- Additional read-only queries expose A2DP peer address, group membership and channel assignment. Channel writes and identification tones are not integrated; meaningful group validation needs another compatible speaker. No call-button remapping was added.
- A stale macOS SDP service can require Bluetooth recovery after replacing the running app. Recovery briefly disconnects Bluetooth accessories; never run it automatically on ordinary launch.

Export log saves the complete current session as `SRS-XB-data.log`. The internal spool is unlinked immediately and reclaimed on process exit, including a crash. Closing the popover does not end the app/session. Only user-requested exports persist. Diagnostic command-line logs are an explicit local test facility.

Previous hardware validation passed 44 setting operations and 14 controller checks, including coalescing 22 slider edits into one write and preserving external updates. A short M5/macOS 26.6.2 profile measured approximately 0–0.1% CPU idle, 10.5% during repeated lighting edits, and 67–80 MiB resident memory; this is not a long-duration leak test. User confirmed native alignment, fluidity and physical-button updates. Execution on macOS 13/Intel remains unverified; universal compilation alone does not prove runtime compatibility.

## Web behavior and assets

Volume and EQ affect actual playback and the analysed bass that moves the cones/membrane. Extra Bass is an audio preview, not Sony DSP emulation. Bluetooth, battery and standby controls are simulated, as explained in their help/About. Positive Dance is the initial track; both tracks loop. Default volume is 50%. The site attempts audible autoplay; browsers may require a gesture, in which case Play gently bounces until playback starts. Reduced motion disables the bounce and ambient brand flash.

Desktop uses a viewport-sized stage; mobile scrolls naturally. The supplied BinaryBears PNG briefly illuminates the background at random 20–50 second intervals, skipping hidden tabs. Original artwork is not altered. Lighting follows Andrea’s descriptions: nervous bass-reactive Rave; warm uniform fading Chill with both white LEDs fading together; No flash pulses only the colored strip; warm Hot and cold Cool with blinking LEDs; neutral-white Strobe; single-color Calm fades. These are visual interpretations, not sampled firmware timing.

The final GLB is an approved Meshy V2 model with local refinements. Source photographs, intermediate models, raw captures and historical notes remain in ignored local archives; they are not release payloads. The app icon derives from the supplied `assets/xb30.svg`. The DMG assets and renderer come from the user-supplied BinaryBears DMG Template v1.0; layout and branding are preserved, while `.DS_Store` is generated headlessly with dmgbuild for CI.

Music credits and license links remain next to the player and in [ATTRIBUTION.txt](../website/public/audio/ATTRIBUTION.txt). Positive Dance includes non-commercial attribution requirements; preserve those restrictions, and do not represent the audio or third-party artwork as covered by the software license.

## GitHub signing and distribution

`.github/workflows/check.yml` runs without release secrets. `.github/workflows/release.yml` signs only a trusted `v*` tag or a manual dispatch. Tags must match `Info.plist`. Manual runs create downloadable workflow artifacts; matching tags publish a GitHub release. No workflow is dispatched during local preparation.

Required repository secret names:

`APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`.

With explicit authorization, `python3 scripts/ci/configure-secrets.py /authorized/credential-directory --repo BinaryBearsLLC/SRS-XB30-MacOS` loads only the supplied files and sends values directly through stdin to GitHub secrets. Add `--check` to validate without uploading. Never print, commit or upload raw/encoded credentials as artifacts.

The hosted runner creates an ephemeral keychain, imports Developer ID Application, builds with hardened runtime and timestamp, notarizes/staples the app, packages the branded DMG, then signs/notarizes/staples and assesses that DMG. Checksums are generated after stapling. Cleanup runs even after failures. The stable asset is `XB30-Controller.dmg`, matching the website download button. Actions are pinned to reviewed commit IDs. See [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [dmgbuild settings](https://dmgbuild.readthedocs.io/en/latest/settings.html).

For a local **ad-hoc preview**: create a virtual environment, install `packaging/requirements.txt`, build the app, then run `DMG_PYTHON=/path/to/venv/bin/python scripts/package-dmg.sh`. No Apple credentials are required. Inspect the mounted image and verify `hdiutil verify` before reviewing it.

Release gates still separate: local tests/package → reviewed push/tag → successful GitHub job → Apple acceptance and stapling → verified public download/site. Do not claim a local preview is notarized. No push, release dispatch or site deployment is authorized merely by preparing these files.

Local preparation (0.2.3): universal build, offline protocol/controller/log tests, native size/render checks, and actual right-click Quit passed. Website build, TypeScript/lint and lighting tests passed; desktop 1440×900, 1366×768, 1024×650 and 1024×520 fit with EQ closed/open, and mobile 390/320 layouts were checked. Autoplay rejection was injected for testing: Play bounces, a click starts playback, pause persists, and reduced-motion suppresses animation. DMG contents, Applications/website links and Finder layout were inspected. Release YAML passed actionlint; shell scripts passed shellcheck. The first public release is 0.2.3. GitHub signing and notarization passed; the downloaded DMG and app passed stapler validation and Gatekeeper with matching SHA-256. GitHub Pages is the public website host.

The web model uses a byte-identical gzip transport (11,065,396 → 2,583,734 bytes), decompressed with DecompressionStream and parsed by GLTFLoader. Browsers without that API retain the original GLB fallback. Three.js is loaded separately from the initial control UI.

Public validation — 2026-09-10: GitHub Pages is at https://binarybearsllc.github.io/SRS-XB30-MacOS/. Lighthouse scored desktop 100/100/100/100 and mobile 92/100/100/100 (performance/accessibility/best practices/SEO); mobile LCP 2.0 s, total blocking time 290 ms, CLS 0. These are laboratory runs with simulated mobile throttling, not measurements on a physical phone. Public browser checks covered both music tracks, volume, Extra Bass/EQ locking, simulated connection, all 12 palette tiles plus Off, help/About/credits, and 320/390 px mobile and 1024/1366/1440 px desktop layouts. The compressed model was the only model downloaded. The release DMG SHA-256 is `31c1f0e920e2ae55336a97c8f759836791a7932ad3bfd6c6f4042f18eb6bf4fb`.

Recloning restores app/site sources, tests, final runtime assets, icons and DMG tooling. It does not restore ignored `3D_Model/` originals/intermediates/Blender sources, `.local-archive/` research and model scripts, diagnostic outputs, `old_research_docs.zip`, or local-only branches. Preserve those outside the checkout before deleting it. npm dependencies and build outputs are reproducible. Apple credentials remain outside the checkout and GitHub Secrets are stored with the repository, not in a clone.
