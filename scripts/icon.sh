#!/bin/bash
# Gera os ícones a partir de Resources/icon-src (Chrome headless + sips + iconutil):
# - Resources/AppIcon.icns do NeyHub (icon.html);
# - Resources/icons/<app>.png, que a Loja mostra (apps.html#<app>);
# - Resources/AppIcon.icns de cada app, nos repos vizinhos (../<app>) que existirem.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

shot() { # shot <url> <png>
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$2" "$1" 2>/dev/null
}

icns() { # icns <png 1024> <saída .icns>
  rm -rf "$T/AppIcon.iconset"; mkdir "$T/AppIcon.iconset"
  for n in 16 32 128 256 512; do
    sips -z $n $n "$1" --out "$T/AppIcon.iconset/icon_${n}x${n}.png" >/dev/null
    sips -z $((n*2)) $((n*2)) "$1" --out "$T/AppIcon.iconset/icon_${n}x${n}@2x.png" >/dev/null
  done
  iconutil -c icns "$T/AppIcon.iconset" -o "$2"
}

SRC="file://$PWD/Resources/icon-src"
shot "$SRC/icon.html" Resources/icon-src/icon.png
icns Resources/icon-src/icon.png Resources/AppIcon.icns
echo "✓ NeyHub"

mkdir -p Resources/icons
for app in aero dose capture deck pauta hub; do
  shot "$SRC/apps.html#$app" "$T/$app.png"
  sips -c 824 824 "$T/$app.png" --out "$T/$app-q.png" >/dev/null # só o quadrado, sem a margem da grade do macOS
  sips -z 256 256 "$T/$app-q.png" --out "Resources/icons/$app.png" >/dev/null
  if [[ -d ../$app/Resources ]]; then
    icns "$T/$app.png" "../$app/Resources/AppIcon.icns"
    [[ -f ../$app/docs/icon.png ]] && sips -z 512 512 "$T/$app.png" --out "../$app/docs/icon.png" >/dev/null
    echo "✓ $app (Loja e ../$app)"
  else
    echo "✓ $app (só na Loja; ../$app não existe)"
  fi
done
