#!/bin/zsh
# Builds VoiceStudio and installs it to ~/Applications/VoiceStudio.app.
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
swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -c "$config" --package-path "$here" --scratch-path "$scratch" > "$build_log" 2>&1 || build_ok=0
grep -E "error|warning|Build complete" "$build_log" | grep -v "^\[" || true
rm -f "$build_log"
[[ "$build_ok" == 1 ]] || { echo "build failed"; exit 1; }
bin=$(swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -c "$config" --package-path "$here" --scratch-path "$scratch" --show-bin-path)/$name
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# Local resources: Python worker and benchmark environment, independent of launch cwd.
cp "$here/Engine/worker.py" "$here/Engine/requirements.lock.txt" "$here/Engine/XTTS-MODEL-LICENSE.txt" "$app/Contents/Resources/"
python3 - "$here" "$app/Contents/Resources/runtime-default.json" <<'PYCONFIG'
import json, sys
from pathlib import Path
Path(sys.argv[2]).write_text(json.dumps({"python": str(Path(sys.argv[1]).parent / ".venv/bin/python")}))
PYCONFIG
if [[ -f "$here/../results/cpu-1.wav" ]]; then
  cp "$here/../results/cpu-1.wav" "$app/Contents/Resources/demo-reference.wav"
fi
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
