#!/bin/zsh
# Uses this account's explicit prior CPML agreement. Never run for a new user.
set -euo pipefail
if [[ "${APP_TEST_CPML_ACCEPTED:-}" != 1 ]]; then
  echo 'Set APP_TEST_CPML_ACCEPTED=1 only after explicitly accepting the bundled model terms.'
  exit 1
fi
APP_STORE=/tmp/VoiceStudio-install.store /Applications/VoiceStudio.app/Contents/MacOS/VoiceStudio --selftest --install-engine "$@"
