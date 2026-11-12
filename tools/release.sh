#!/bin/zsh
# Clean build, then sign with Developer ID, notarize, and package VoiceStudio as a DMG.
#
#   tools/release.sh             make releases/VoiceStudio-<version>-<build>-arm64/
#   tools/release.sh --install   also replace /Applications/VoiceStudio.app with the notarized app
#
# One-time setup on a new Mac:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. xcrun notarytool store-credentials "framedl-notary" --apple-id <id> --team-id 6Y8QUTA3Z3
# Apple's scan usually takes a few minutes. It can take more than an hour.
set -euo pipefail
here=${0:A:h:h}
cd "$here"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Rob Schoen (6Y8QUTA3Z3)}"
PROFILE="${NOTARY_PROFILE:-framedl-notary}"
ENTITLEMENTS="$here/VoiceStudio.entitlements"
INSTALL=0; [[ " $* " == *" --install "* ]] && INSTALL=1

step() { printf '\n=== %s\n' "$1"; }

step "Check the certificate and the notary profile"
security find-identity -v -p codesigning | grep -qF "$IDENTITY" || { echo "Certificate not found: $IDENTITY"; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null

step "Clean release build (no test recordings)"
env -u VOICE_TEST_REFERENCE ./build.sh
SOURCE=/Applications/VoiceStudio.app
PLIST="$SOURCE/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == com.robschoen.voicestudio ]] || { echo "Unexpected app at $SOURCE"; exit 1; }
[[ ! -e "$SOURCE/Contents/Resources/demo-reference.wav" ]] || { echo "A test recording is in the app. Stop."; exit 1; }
# This signer handles the single executable. Stop if other native code appears.
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | grep -q 'Mach-O' && [[ "$file" != "$SOURCE/Contents/MacOS/VoiceStudio" ]]; then
    echo "Additional native code needs a signing step: $file"; exit 1
  fi
done < <(find "$SOURCE/Contents" -type f -print0)

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
ARCH=$(lipo -archs "$SOURCE/Contents/MacOS/VoiceStudio" | tr ' ' '-')
OUT="$here/releases/VoiceStudio-${VERSION}-${BUILD}-${ARCH}"
[[ ! -e "$OUT" ]] || { echo "Output already exists: $OUT"; exit 1; }
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$OUT/VoiceStudio.app"
DMG="$OUT/VoiceStudio-${VERSION}-${ARCH}.dmg"

notarize() {
  local file="$1" label="$2" id result
  # Submission IDs are saved, so an interrupted run can be resumed with notarytool.
  xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --output-format json > "$OUT/$label-submission.json"
  id=$(plutil -extract id raw "$OUT/$label-submission.json")
  echo "Submitted $label ($id). Waiting for Apple…"
  xcrun notarytool wait "$id" --keychain-profile "$PROFILE" --output-format json > "$OUT/$label-result.json" || true
  result=$(plutil -extract status raw "$OUT/$label-result.json")
  xcrun notarytool log "$id" --keychain-profile "$PROFILE" "$OUT/$label-log.json" || true
  [[ "$result" == Accepted ]] || { echo "Apple returned $result. See $OUT/$label-log.json"; exit 1; }
  echo "Accepted: $label ($id)"
}

step "Sign the app (hardened runtime, microphone entitlement)"
ditto "$SOURCE" "$APP"
xattr -cr "$APP"
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

step "Notarize the app"
ditto -c -k --keepParent "$APP" "$WORK/VoiceStudio.zip"
notarize "$WORK/VoiceStudio.zip" app
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

step "Build, sign, and notarize the installer"
mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/VoiceStudio.app"
ln -s /Applications "$WORK/stage/Applications"
hdiutil create -volname VoiceStudio -srcfolder "$WORK/stage" -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG" dmg
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd "$OUT" && shasum -a 256 "${DMG:t}" > SHA256SUMS.txt)

if (( INSTALL )); then
  step "Install the notarized app"
  osascript -e 'quit app "VoiceStudio"' 2>/dev/null || true
  sleep 1
  rm -rf "$SOURCE"
  ditto "$APP" "$SOURCE"
  spctl --assess --type execute --verbose=2 "$SOURCE"
fi
echo "Release ready: $DMG"
