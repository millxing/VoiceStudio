#!/bin/zsh
set -euo pipefail
app="/Applications/VoiceStudio.app/Contents/MacOS/VoiceStudio"
# All integration artifacts remain outside the personal library.
rm -f /tmp/VoiceStudio-integration.store
rm -rf /tmp/VoiceStudio-integration.data
APP_STORE=/tmp/VoiceStudio-integration.store "$app" --selftest --integration
