#!/bin/zsh
# Builds a Release iContainer.app, signs it, optionally notarizes + staples
# it, and packages it as a zip ready to attach to a GitHub release.
#
# Signing behaviour:
#   - If a "Developer ID Application" identity is in the keychain (or one is
#     passed via SIGN_IDENTITY), the app is signed with it + hardened runtime
#     + a secure timestamp, then notarized and stapled so Gatekeeper accepts
#     it with no first-launch warning.
#   - Otherwise it falls back to ad-hoc signing (unnotarized) — the app then
#     needs the right-click -> Open / `xattr` dance on first launch.
#
# Notarization uses a stored notarytool keychain profile (default name
# "icontainer-notary"). Create it once (App Store Connect API key — preferred):
#   xcrun notarytool store-credentials icontainer-notary \
#     --key /path/AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_UUID>
# or with an Apple ID + app-specific password:
#   xcrun notarytool store-credentials icontainer-notary \
#     --apple-id <apple-id> --team-id R6A9C6AUKJ --password <app-specific-pw>
#
# Env overrides: SIGN_IDENTITY, NOTARY_PROFILE, NOTARIZE=0 (skip notarization).
set -euo pipefail

cd "$(dirname "$0")/.."

# Use the full Xcode toolchain even when xcode-select points at the
# Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Resolve the signing identity: explicit override wins; otherwise pick the
# first "Developer ID Application" cert in the keychain; otherwise ad-hoc.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIGN_IDENTITY"
else
  IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"(.*)"$/\1/')
  IDENTITY="${IDENTITY:--}" # "-" = ad-hoc
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-icontainer-notary}"
NOTARIZE="${NOTARIZE:-1}"

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' iContainer.xcodeproj/project.pbxproj | head -1)
DERIVED=$(mktemp -d /tmp/icontainer-release.XXXXXX)
DIST="dist"

echo "Building iContainer ${VERSION} (Release)..."
xcodebuild -project iContainer.xcodeproj \
  -scheme iContainer \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build | grep -E "error:|warning: [^M]|BUILD" || true

APP="$DERIVED/Build/Products/Release/iContainer.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }

if [[ "$IDENTITY" == "-" ]]; then
  echo "Signing ad-hoc (no Developer ID identity found — build will NOT be notarized)..."
  codesign --force --deep --sign "-" "$APP"
else
  echo "Signing with: $IDENTITY (hardened runtime + secure timestamp)..."
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$DIST"
ZIP="$DIST/iContainer-v${VERSION}.zip"
rm -f "$ZIP"
echo "Packaging $ZIP..."
ditto -c -k --keepParent "$APP" "$ZIP"

# Notarize + staple when signed with a real Developer ID identity.
if [[ "$IDENTITY" != "-" && "$NOTARIZE" == "1" ]]; then
  echo "Notarizing (profile: $NOTARY_PROFILE) — this can take a few minutes..."
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling the ticket to the app..."
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vvv "$APP" || true
  # Re-zip so the distributed archive contains the stapled app.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarized + stapled."
else
  echo "Skipping notarization (ad-hoc build or NOTARIZE=0)."
fi

rm -rf "$DERIVED"
echo "Done: $ZIP"
echo "Attach it to the GitHub release for tag v${VERSION}."
