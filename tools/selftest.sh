#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.robschoen.voicestudio.savedState
store=/tmp/VoiceStudio-self.store
rm -f $store $store-shm $store-wal
rm -rf /tmp/VoiceStudio-self.data
APP_STORE=$store ~/Applications/VoiceStudio.app/Contents/MacOS/VoiceStudio --selftest
