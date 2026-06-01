#!/usr/bin/env bash
#
# Generate a signed Sparkle appcast.xml for one release.
#
# Sparkle clients fetch this file from SUFeedURL (Info.plist), verify the EdDSA
# signature against SUPublicEDKey, and update when the advertised build number is
# higher than the installed one. The private signing key never lives in the repo:
# locally it sits in the login keychain (created by Sparkle's generate_keys); in CI
# it is passed through the SPARKLE_PRIVATE_KEY secret. See docs/UPDATES.md.
#
# Usage:
#   scripts/make-appcast.sh <dmg> <short_version> <build> <download_url> [out]
#
#   <dmg>            Path to the notarized .dmg being released.
#   <short_version>  Marketing version, e.g. 1.1.0 (CFBundleShortVersionString).
#   <build>          Build number, e.g. 7 (CFBundleVersion). MUST increase each release.
#   <download_url>   Public URL the .dmg will be served from (the tagged release asset).
#   [out]            Output path. Defaults to ./appcast.xml.
#
# Environment:
#   SIGN_UPDATE             Path to Sparkle's sign_update tool (auto-detected if unset).
#   SPARKLE_PRIVATE_KEY     Base64 EdDSA private key (CI). If unset, the keychain is used.
#   MIN_SYSTEM_VERSION      Minimum macOS, default 13.0.
#   RELEASE_NOTES_URL       Optional URL shown as the update's release notes.
#
set -euo pipefail

DMG="${1:?dmg path required}"
SHORT_VERSION="${2:?short version required}"
BUILD="${3:?build number required}"
DOWNLOAD_URL="${4:?download url required}"
OUT="${5:-appcast.xml}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-13.0}"

[ -f "$DMG" ] || { echo "error: dmg not found: $DMG" >&2; exit 1; }

# Locate sign_update: explicit env, then PATH, then the SwiftPM artifact bundle.
find_sign_update() {
  if [ -n "${SIGN_UPDATE:-}" ] && [ -x "$SIGN_UPDATE" ]; then echo "$SIGN_UPDATE"; return; fi
  if command -v sign_update >/dev/null 2>&1; then command -v sign_update; return; fi
  local hit
  hit="$(find "$HOME/Library/Developer/Xcode/DerivedData" "$PWD" -path '*artifacts/sparkle/Sparkle/bin/sign_update' 2>/dev/null | head -1 || true)"
  [ -n "$hit" ] && { echo "$hit"; return; }
  echo "error: could not find Sparkle's sign_update (set SIGN_UPDATE)" >&2
  exit 1
}
SIGN_UPDATE="$(find_sign_update)"

# Sign the DMG. sign_update prints: sparkle:edSignature="..." length="..."
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  KEYFILE="$(mktemp)"
  trap 'rm -f "$KEYFILE"' EXIT
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEYFILE"
  SIG_LINE="$("$SIGN_UPDATE" "$DMG" -f "$KEYFILE")"
else
  SIG_LINE="$("$SIGN_UPDATE" "$DMG")"
fi

[ -n "$SIG_LINE" ] || { echo "error: sign_update produced no signature" >&2; exit 1; }

PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
NOTES=""
if [ -n "${RELEASE_NOTES_URL:-}" ]; then
  NOTES="            <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>"
fi

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Dusty</title>
        <link>${DOWNLOAD_URL%/*}/appcast.xml</link>
        <description>Updates for Dusty, the open macOS disk cleaner.</description>
        <language>en</language>
        <item>
            <title>Dusty ${SHORT_VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
${NOTES}
            <enclosure url="${DOWNLOAD_URL}" type="application/octet-stream" ${SIG_LINE} />
        </item>
    </channel>
</rss>
XML

echo "Wrote $OUT (build ${BUILD}, ${SHORT_VERSION})" >&2
