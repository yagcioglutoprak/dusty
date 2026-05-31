# Cutting a signed, notarized release

Dusty ships as a notarized `.dmg` so people can download and run it without any
Gatekeeper friction. Releases are built by the `Release` GitHub Actions workflow
when you push a `v*` tag. The workflow needs your Apple signing material as
repository secrets. You only set this up once.

## 1. Create a Developer ID Application certificate

You need a **Developer ID Application** certificate (not "Apple Development").

In Xcode: `Settings` > `Accounts` > select your team > `Manage Certificates` >
the `+` button > `Developer ID Application`.

Then export it as a `.p12`:

1. Open `Keychain Access`.
2. Find `Developer ID Application: <your name> (<TEAMID>)` under `login`.
3. Right click > `Export`, save as `dusty-cert.p12`, set a password.

Base64 encode it for the secret:

```bash
base64 -i dusty-cert.p12 | pbcopy
```

## 2. Create an app-specific password for notarization

At <https://appleid.apple.com> > `Sign-In and Security` > `App-Specific
Passwords`, generate one and label it `dusty-notary`.

## 3. Add the repository secrets

`Settings` > `Secrets and variables` > `Actions` > `New repository secret`:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | the base64 blob from step 1 |
| `MACOS_CERT_PASSWORD` | the `.p12` export password |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: <your name> (83VWMF5EQX)` |
| `APPLE_TEAM_ID` | `83VWMF5EQX` |
| `NOTARY_APPLE_ID` | your Apple ID email |
| `NOTARY_PASSWORD` | the app-specific password from step 2 |
| `TAP_TOKEN` | optional, a PAT with `repo` scope to auto-update the Homebrew tap |

## 4. Tag and push

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow builds, signs, notarizes, staples, packages a `.dmg` and `.zip`,
and creates the GitHub release. If `TAP_TOKEN` is set it also updates
`yagcioglutoprak/homebrew-tap` so `brew install --cask yagcioglutoprak/tap/dusty`
serves the new version.

## Verifying a build locally

```bash
spctl --assess --type execute -vv /Applications/Dusty.app
codesign --verify --deep --strict --verbose=2 /Applications/Dusty.app
```

A notarized, stapled app prints `accepted` and `source=Notarized Developer ID`.
