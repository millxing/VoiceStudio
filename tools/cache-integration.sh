#!/bin/zsh
set -euo pipefail
here=${0:A:h}
cd "${here:h}"
voice_python="${VOICE_PYTHON:-${here:h:h}/.venv/bin/python}"
"$voice_python" tools/cache-fixtures.py
rm -f /tmp/VoiceStudio-cache-integration.store
rm -rf /tmp/VoiceStudio-cache-integration.data
APP_STORE=/tmp/VoiceStudio-cache-integration.store \
APP_CACHE_FIXTURE=/tmp/VoiceStudio-cache-fixture.pth \
APP_CACHE_BANK=/tmp/VoiceStudio-cache-bank.pth \
/Applications/VoiceStudio.app/Contents/MacOS/VoiceStudio --selftest --integration
