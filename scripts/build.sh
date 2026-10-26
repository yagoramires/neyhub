#!/bin/zsh
# Compila e empacota o NeyHub.app em build/ (sem precisar do Xcode).
# Uso: scripts/build.sh [release|debug] [--run] [--dist]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
RUN=0
DIST=0
for arg in "$@"; do
  case $arg in
    debug|release) CONFIG=$arg ;;
    --run) RUN=1 ;;
    --dist) DIST=1 ;;
  esac
done

# Sem fallback ad-hoc: plugins e updates dependem da assinatura fixa.
IDENTITY="Aero Local Signing"
IDENTS=$(security find-identity -p codesigning)
if ! grep -q "$IDENTITY" <<<"$IDENTS"; then
  echo "✗ sem a identidade \"$IDENTITY\": rode scripts/setup-signing.sh" >&2
  exit 1
fi

ARCHS=()
(( DIST )) && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/NeyHub"

APP=build/NeyHub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NeyHub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[[ -f Resources/catalog.json ]] && cp Resources/catalog.json "$APP/Contents/Resources/"
[[ -d Resources/icons ]] && ditto Resources/icons "$APP/Contents/Resources/icons"

codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "✓ $APP"

if (( DIST )); then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  mkdir -p dist
  rm -f "dist/NeyHub-$VERSION.zip"
  ditto -c -k --norsrc --keepParent "$APP" "dist/NeyHub-$VERSION.zip"
  echo "✓ dist/NeyHub-$VERSION.zip"
fi

if (( RUN )); then
  pkill -x NeyHub 2>/dev/null || true
  while pgrep -x NeyHub >/dev/null; do sleep 0.2; done
  open -n "$APP"
fi
