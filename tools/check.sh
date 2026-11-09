#!/bin/zsh
set -euo pipefail
here=${0:A:h}
cd "${here:h}"
source tools/swift-env.sh
swift run --sdk "$VOICE_SWIFT_SDK" --scratch-path "$HOME/Library/Developer/VoiceStudio/check-build" VoiceStudioChecks
voice_python="${VOICE_PYTHON:-${here:h:h}/.venv/bin/python}"
"$voice_python" -m unittest discover -s Engine -p 'test_*.py'
