#!/bin/zsh
# Roda o --selftest de dentro do .app (bundle id local.neyhub) e falha se houver
# classe duplicada entre módulos ("is implemented in both").
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh debug

ERR=$(mktemp)
cleanup() {
  rm -f "$ERR"
  rm -f ~/Library/Preferences/neyhub.selftest.*(N)
  rm -rf "${TMPDIR:-/tmp}"/nh-*(N)
}
trap cleanup EXIT

# Plugin de teste em 4 versões: good (assinado), adhoc, tampered (1 byte trocado depois de assinar), future (contract 2).
swift build --package-path Fixtures/HelloPlugin --product HelloPlugin
DYLIB="$(swift build --package-path Fixtures/HelloPlugin --show-bin-path)/libHelloPlugin.dylib"
FIX="${TMPDIR:-/tmp}/nh-fixture"
rm -rf "$FIX"
for kind in good adhoc tampered future; do
  mkdir -p "$FIX/$kind/Hello.neyplugin"
  cp Fixtures/HelloPlugin/manifest.json "$DYLIB" "$FIX/$kind/Hello.neyplugin/"
done
for kind in good tampered future; do
  codesign --force --sign "Aero Local Signing" --timestamp=none "$FIX/$kind/Hello.neyplugin/libHelloPlugin.dylib"
done
codesign --force --sign - "$FIX/adhoc/Hello.neyplugin/libHelloPlugin.dylib"
T="$FIX/tampered/Hello.neyplugin/libHelloPlugin.dylib"
OFF=16384  # início da 2ª página: dentro do __TEXT, coberto pelos hashes da assinatura
BYTE=$(xxd -s $OFF -l 1 -p "$T")
printf "\\x$(printf %02x $(( 0x$BYTE ^ 0xff )))" | dd of="$T" bs=1 seek=$OFF conv=notrunc 2>/dev/null
sed -i '' 's/"contract": 1/"contract": 2/' "$FIX/future/Hello.neyplugin/manifest.json"
grep -q '"contract": 2' "$FIX/future/Hello.neyplugin/manifest.json"

rc=0
build/NeyHub.app/Contents/MacOS/NeyHub --selftest --fixture "$FIX" "$@" 2>"$ERR" || rc=$?
if grep -q "is implemented in both" "$ERR"; then
  echo "✗ classe duplicada entre módulos:" >&2
  cat "$ERR" >&2
  exit 1
fi
if (( rc != 0 )); then
  echo "✗ selftest falhou (exit $rc):" >&2
  cat "$ERR" >&2
  exit $rc
fi
