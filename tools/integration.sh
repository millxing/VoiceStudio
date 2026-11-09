#!/bin/zsh
set -euo pipefail
app="/Applications/VoiceStudio.app/Contents/MacOS/VoiceStudio"
# All integration artifacts remain outside the personal library.
rm -f /tmp/VoiceStudio-integration.store
rm -rf /tmp/VoiceStudio-integration.data
VOICE_PYTHON="${VOICE_PYTHON:-${0:A:h:h:h}/.venv/bin/python}" APP_STORE=/tmp/VoiceStudio-integration.store "$app" --selftest --integration
