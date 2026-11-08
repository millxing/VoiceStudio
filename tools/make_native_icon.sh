#!/bin/zsh
set -euo pipefail
here=${0:A:h}
root=${here:h}
mkdir -p "$root/Resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swift "$here/native-icon.swift" "$work"
iconutil -c icns "$work/AppIcon.iconset" -o "$root/Resources/AppIcon.icns"
