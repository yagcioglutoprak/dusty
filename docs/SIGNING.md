# Cutting a signed, notarized release

Dusty ships as a notarized `.dmg` so people download and run it with no
Gatekeeper friction. You need a paid Apple Developer Program membership and a
**Developer ID Application** certificate (team `W4AZ5462W5`).

There are two ways to release: from CI (push a tag) or locally.

## Required pieces

- A **Developer ID Application** certificate. Create it in Xcode: `Settings` >
  `Accounts` > your team > `Manage Certificates` > `+` > `Developer ID
  Application`. The signing identity looks like
  `Developer ID Application: TOPRAK YAGCIOGLU (W4AZ5462W5)`.
- An **App Store Connect API key** for notarization. App Store Connect >
  `Users and Access` > `Integrations` > `App Store Connect API` > generate a key
  with `Developer` access, download its `.p8` (one time only), and note the
  **Key ID** and the **Issuer ID** shown on that page.

## Release from CI (recommended for repeat releases)

Add these as repository secrets (`Settings` > `Secrets and variables` >
`Actions`). When they are present, pushing a `v*` tag builds, signs, notarizes,
staples, and publishes the release. When they are absent the workflow skips and
stays green.

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | your Developer ID cert + key exported as `.p12`, then `base64 -i cert.p12` |
| `MACOS_CERT_PASSWORD` | the `.p12` export password |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: TOPRAK YAGCIOGLU (W4AZ5462W5)` |
| `APPLE_TEAM_ID` | `W4AZ5462W5` |
| `NOTARY_KEY_P8_BASE64` | the notarization `.p8`, base64 encoded |
| `NOTARY_KEY_ID` | the API key ID |
| `NOTARY_ISSUER_ID` | the issuer ID from the Integrations page |
| `TAP_TOKEN` | optional PAT with `repo` scope, to auto-update the Homebrew tap |

```bash
git tag v1.2.0
git push origin v1.2.0
```

## Release locally

```bash
cd Dusty
xcodebuild -project Dusty.xcodeproj -scheme Dusty -configuration Release \
  -derivedDataPath build/Release \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application: TOPRAK YAGCIOGLU (W4AZ5462W5)" \
  DEVELOPMENT_TEAM=W4AZ5462W5 \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" build

APP="build/Release/Build/Products/Release/Dusty.app"

# The dusty CLI ships inside the app bundle. It MUST go in Contents/Helpers,
# never Contents/MacOS: on a case-insensitive filesystem "dusty" overwrites
# the "Dusty" main executable there.
swift build -c release --product dusty --package-path ../CleanerEngine
mkdir -p "$APP/Contents/Helpers"
cp ../CleanerEngine/.build/release/dusty "$APP/Contents/Helpers/dusty"

# Sparkle ships its nested helpers (Autoupdate, Updater.app, the XPC services)
# ad-hoc signed. Re-sign them with the Developer ID inside-out, deepest first and
# the app last, or notarization rejects the build. The app's outer signature is
# then re-applied over the changed framework.
ID="Developer ID Application: TOPRAK YAGCIOGLU (W4AZ5462W5)"
SPK="$APP/Contents/Frameworks/Sparkle.framework"
for item in "$SPK"/Versions/B/XPCServices/*.xpc "$SPK"/Versions/B/Autoupdate \
            "$SPK"/Versions/B/Updater.app "$SPK" "$APP/Contents/Helpers/dusty"; do
  codesign --force --options runtime --timestamp --sign "$ID" "$item"
done
codesign --force --options runtime --timestamp \
  --entitlements Dusty/Dusty/Dusty.entitlements --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p stage && ditto "$APP" stage/Dusty.app && ln -s /Applications stage/Applications
hdiutil create -volname Dusty -srcfolder stage -ov -format UDZO Dusty.dmg

xcrun notarytool submit Dusty.dmg \
  --key /path/to/AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-id> --wait
xcrun stapler staple Dusty.dmg
```

The `Release` configuration sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` so the
build does not carry the debug `get-task-allow` entitlement, which notarization
rejects.

## Verifying

```bash
spctl --assess --type execute -vv /Applications/Dusty.app   # source=Notarized Developer ID
xcrun stapler validate Dusty.dmg                            # The validate action worked!
```
