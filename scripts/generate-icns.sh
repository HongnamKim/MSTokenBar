#!/bin/bash
# Render the workshop nippers with nearest-neighbor scaling, including the optical 16px master.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

gen() { swift scripts/generate-icon.swift "$ICONSET/$1" "$2" >/dev/null; }
gen icon_16x16.png        16
gen icon_16x16@2x.png     32
gen icon_32x32.png        32
gen icon_32x32@2x.png     64
gen icon_128x128.png     128
gen icon_128x128@2x.png  256
gen icon_256x256.png     256
gen icon_256x256@2x.png  512
gen icon_512x512.png     512
gen icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
swift scripts/generate-icon.swift assets/icon_1024.png 1024 >/dev/null
swift scripts/generate-icon.swift assets/icon.png 512 >/dev/null
rm -rf "$ICONSET"
echo "done: assets/AppIcon.icns + assets/icon_1024.png"
