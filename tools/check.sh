#!/bin/zsh
set -euo pipefail
here=${0:A:h}
cd "${here:h}"
source tools/swift-env.sh
swift run --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --scratch-path "$HOME/Library/Developer/VoiceStudio/check-build" VoiceStudioChecks
python3 -m unittest discover -s Engine -p test_worker.py
