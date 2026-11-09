#!/bin/zsh
# Builds VoiceStudio and installs it to /Applications/VoiceStudio.app.
# Build products live in ~/Library/Developer/VoiceStudio, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="VoiceStudio"
scratch="$HOME/Library/Developer/$name/build"
source "$here/tools/swift-env.sh"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

build_log=$(mktemp)
build_ok=1
swift build --sdk "$VOICE_SWIFT_SDK" -c "$config" --package-path "$here" --scratch-path "$scratch" > "$build_log" 2>&1 || build_ok=0
grep -E "error|warning|Build complete" "$build_log" | grep -v "^\[" || true
rm -f "$build_log"
[[ "$build_ok" == 1 ]] || { echo "build failed"; exit 1; }
bin=$(swift build --sdk "$VOICE_SWIFT_SDK" -c "$config" --package-path "$here" --scratch-path "$scratch" --show-bin-path)/$name
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# SwiftPM may reuse an identical optimized binary after comment-only edits.
# Its successful exit and the executable check above establish build success.

app="/Applications/$name.app"
mkdir -p /Applications
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# Portable installer and worker resources, independent of launch cwd.
cp "$here/Engine/install_engine.py" "$here/Engine/audio_decode.py" "$here/Engine/voice_cache.py" "$here/Engine/worker.py" "$here/Engine/requirements.lock.txt" "$here/Engine/XTTS-MODEL-LICENSE.txt" "$app/Contents/Resources/"
# Development fixtures are opt-in; never silently package local recordings.
if [[ -n "${VOICE_TEST_REFERENCE:-}" ]]; then
  cp "$VOICE_TEST_REFERENCE" "$app/Contents/Resources/demo-reference.wav"
fi
cp "$here/LICENSE" "$here/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
# Icon Composer requires Xcode's actool. Use a native SF Symbol icon on CLT-only Macs.
"$here/tools/make_native_icon.sh"
cp "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
