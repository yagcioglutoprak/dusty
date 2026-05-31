#!/usr/bin/env bash
#
# Dusty installer. Builds the app from source on your machine and drops it in
# /Applications. Because the build happens locally, macOS trusts it: no
# Gatekeeper warnings, no "unidentified developer", no right-click dance.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yagcioglutoprak/dusty/main/scripts/install.sh | bash
#
# Environment overrides:
#   DUSTY_PREFIX   install location (default: /Applications)
#   DUSTY_REF      git ref to build (default: main)
#
set -euo pipefail

REPO_URL="https://github.com/yagcioglutoprak/dusty.git"
REF="${DUSTY_REF:-main}"
PREFIX="${DUSTY_PREFIX:-/Applications}"
APP_NAME="Dusty.app"

bold=$(tput bold 2>/dev/null || true)
dim=$(tput dim 2>/dev/null || true)
red=$(tput setaf 1 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

say()  { printf "%s\n" "${dim}dusty${reset} $*"; }
ok()   { printf "%s\n" "${green}ok${reset}    $*"; }
die()  { printf "%s\n" "${red}error${reset} $*" >&2; exit 1; }

printf "\n%s\n%s\n\n" "${bold}Dusty${reset}" "${dim}Free up disk space on your Mac, safely.${reset}"

# Preflight ------------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "Dusty is macOS only."

if ! command -v git >/dev/null 2>&1; then
  die "git not found. Install the Xcode Command Line Tools with: xcode-select --install"
fi

# Building a SwiftUI app needs the full Xcode, not just the command line tools.
if ! command -v xcodebuild >/dev/null 2>&1; then
  die "xcodebuild not found. Install Xcode from the App Store, then run:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
case "$DEV_DIR" in
  *CommandLineTools*)
    die "Xcode is required to build Dusty, but the active toolchain is the Command Line Tools.
       Install Xcode, then point the toolchain at it:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
esac

# Build ----------------------------------------------------------------------

WORK="$(mktemp -d -t dusty)"
trap 'rm -rf "$WORK"' EXIT

say "fetching source (${REF})"
git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORK/dusty" >/dev/null 2>&1 \
  || git clone --depth 1 "$REPO_URL" "$WORK/dusty" >/dev/null 2>&1 \
  || die "could not clone $REPO_URL"

cd "$WORK/dusty/Dusty"

# The committed Xcode project is the happy path. Regenerate only if it is gone.
if [ ! -d "Dusty.xcodeproj" ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      say "installing xcodegen (needed to generate the project)"
      brew install xcodegen >/dev/null
    else
      die "Dusty.xcodeproj is missing and neither xcodegen nor Homebrew is installed."
    fi
  fi
  xcodegen generate >/dev/null
fi

say "building (this takes a minute on first run)"
DERIVED="$WORK/DerivedData"
xcodebuild \
  -project Dusty.xcodeproj \
  -scheme Dusty \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build >/dev/null 2>"$WORK/build.log" \
  || { tail -30 "$WORK/build.log" >&2; die "build failed (log above)"; }

BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
[ -d "$BUILT" ] || die "build finished but $APP_NAME was not found"

# Install --------------------------------------------------------------------

DEST="$PREFIX/$APP_NAME"
if [ -d "$DEST" ]; then
  say "replacing existing install at $DEST"
  rm -rf "$DEST"
fi

say "installing to $PREFIX"
if ! ditto "$BUILT" "$DEST" 2>/dev/null; then
  say "writing to $PREFIX needs admin rights"
  sudo ditto "$BUILT" "$DEST"
fi

# Locally built apps are not quarantined, but strip the flag just in case.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

ok "installed $DEST"
printf "\n"
say "launching Dusty. Look for the disk icon in your menu bar."
say "for the deepest scan, grant Full Disk Access in System Settings > Privacy & Security."
open "$DEST" || true
printf "\n"
