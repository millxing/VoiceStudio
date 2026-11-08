#!/bin/zsh
# The installed CLT has stale 2024 private PackageDescription interfaces beside
# current public interfaces. Use a local copy of the support libraries without
# the stale private interfaces; never modify the system toolchain.
voice_support="$HOME/Library/Developer/VoiceStudio/toolchain"
if [[ ! -f "$voice_support/ManifestAPI/libPackageDescription.dylib" ]]; then
  mkdir -p "$voice_support"
  rsync -a --exclude '*.private.swiftinterface' /Library/Developer/CommandLineTools/usr/lib/swift/pm/ "$voice_support/"
fi
export SWIFTPM_CUSTOM_LIBS_DIR="$voice_support"
