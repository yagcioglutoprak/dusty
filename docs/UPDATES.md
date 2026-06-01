# Auto-updates (Sparkle)

Dusty updates itself with [Sparkle](https://sparkle-project.org). On first launch it
opts into automatic daily checks and silent install; both can be turned off in
**Settings -> Updates**, where there is also a **Check for Updates Now** button.

## How it fits together

| Piece | Where |
| --- | --- |
| Sparkle framework | SPM dependency in `Dusty/project.yml` |
| Updater wrapper | `Dusty/Dusty/Utilities/Updater.swift` |
| Settings UI | "Updates" section in `SettingsView` (`Views/ConfirmationSheet.swift`) |
| Feed URL + public key | `SUFeedURL`, `SUPublicEDKey` in `Dusty/Dusty/Info.plist` |
| Appcast generator | `scripts/make-appcast.sh` |
| Release wiring | `.github/workflows/release.yml` |

The update feed is `https://github.com/yagcioglutoprak/dusty/releases/latest/download/appcast.xml`,
so the newest published release always advertises itself. Each release uploads a freshly
signed `appcast.xml` as an asset.

Auto-update works from the first Sparkle-enabled release onward. Anyone still on a
pre-Sparkle build (v1.0.0) updates once by hand; after that it is automatic.

## The signing key

Updates are pinned with an EdDSA key, separate from the Apple Developer ID signature:

- The **public** key is in `Info.plist` (`SUPublicEDKey`). It is not secret and ships in the app.
- The **private** key lives only in the release machine's **login keychain** (created by
  Sparkle's `generate_keys`). It is never committed and never exported into the repo.

If you ever need to print the public key again:

```bash
# generate_keys is in the resolved Sparkle package:
GK=$(find ~/Library/Developer/Xcode/DerivedData -path '*sparkle/Sparkle/bin/generate_keys' | head -1)
"$GK" -p
```

## Cutting a release with an appcast

The release workflow (`release.yml`) signs the notarized DMG and publishes `appcast.xml`
automatically when a `SPARKLE_PRIVATE_KEY` secret is present. The build number is derived
from the tag (`v1.2.3` -> build `10203`) and injected as `CURRENT_PROJECT_VERSION`, so the
installed app's `CFBundleVersion` matches what the appcast advertises.

### One-time setup: add the private key as a CI secret

So CI can sign the appcast, export the private key from your keychain and store it as a
GitHub Actions secret. Do this on the machine that holds the key:

```bash
GK=$(find ~/Library/Developer/Xcode/DerivedData -path '*sparkle/Sparkle/bin/generate_keys' | head -1)
"$GK" -x /tmp/dusty_sparkle_private.key      # writes the private key to a file
gh secret set SPARKLE_PRIVATE_KEY < /tmp/dusty_sparkle_private.key
rm -f /tmp/dusty_sparkle_private.key         # do not keep it lying around
```

Without that secret the release still ships (DMG + zip), it just skips the appcast, so
auto-update will not advertise the new version until a signed appcast is published.

### Signing an appcast locally

On the machine with the key in its keychain (no secret needed):

```bash
scripts/make-appcast.sh \
  /path/to/Dusty-1.2.3.dmg \
  1.2.3 \
  10203 \
  https://github.com/yagcioglutoprak/dusty/releases/download/v1.2.3/Dusty-1.2.3.dmg \
  appcast.xml
```

Then attach `appcast.xml` to the matching GitHub release.

## Testing the update flow

1. Build and install a low-version Dusty (e.g. `MARKETING_VERSION=1.0.0 CURRENT_PROJECT_VERSION=10000`).
2. Publish a higher release (or host a local appcast pointing at a higher-build DMG).
3. Launch Dusty and use **Settings -> Check for Updates Now**. Sparkle should offer the update,
   verify its EdDSA signature against `SUPublicEDKey`, then download and install.

If Sparkle reports a signature mismatch, the DMG was signed with a different key than the
one in `Info.plist`; re-sign with `make-appcast.sh` using the matching keychain key.
