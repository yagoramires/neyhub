#!/bin/bash
# Gera Resources/AppIcon.icns a partir de Resources/icon-src/icon.html (Chrome headless + sips + iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 --window-size=1024,1024 --screenshot="$T/icon.png" \
  "file://$PWD/Resources/icon-src/icon.html" 2>/dev/null
mkdir "$T/AppIcon.iconset"
for n in 16 32 128 256 512; do
  sips -z $n $n "$T/icon.png" --out "$T/AppIcon.iconset/icon_${n}x${n}.png" >/dev/null
  sips -z $((n*2)) $((n*2)) "$T/icon.png" --out "$T/AppIcon.iconset/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$T/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$T/icon.png" Resources/icon-src/icon.png
echo "Resources/AppIcon.icns gerado"
