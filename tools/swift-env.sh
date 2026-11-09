#!/bin/zsh
# Prefer the compatible local SDK; other Macs use their selected Xcode/CLT SDK.
if [[ -z "${VOICE_SWIFT_SDK:-}" ]]; then
  if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    VOICE_SWIFT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  else
    VOICE_SWIFT_SDK=$(xcrun --sdk macosx --show-sdk-path)
  fi
fi
export VOICE_SWIFT_SDK

# This Mac's CLT has stale private PackageDescription interfaces. Apply the
# workaround only for that selected toolchain, never to a full Xcode install.
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
  voice_support="$HOME/Library/Developer/VoiceStudio/toolchain"
  if [[ ! -f "$voice_support/ManifestAPI/libPackageDescription.dylib" ]]; then
    mkdir -p "$voice_support"
    rsync -a --exclude '*.private.swiftinterface' /Library/Developer/CommandLineTools/usr/lib/swift/pm/ "$voice_support/"
  fi
  export SWIFTPM_CUSTOM_LIBS_DIR="$voice_support"
fi
