#!/bin/zsh
# Roda o --selftest de dentro do .app (bundle id local.neyhub) e falha se houver
# classe duplicada entre módulos ("is implemented in both").
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh debug
cmp -s catalog.json Resources/catalog.json || { echo "✗ catalog.json e Resources/catalog.json diferentes" >&2; exit 1; }

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

# --- release: changelog-section.sh e --validate-manifest ---
CL="$FIX/CHANGELOG.md"
printf '# Changelog\n\n## [0.2.0] - 2026-11-01\n### Corrigido\n- b\n\n## [0.1.0] - 2026-10-25\n### Adicionado\n- a\n' > "$CL"
[[ "$(scripts/changelog-section.sh 0.2.0 "$CL")" == $'### Corrigido\n- b' ]] || { echo "✗ changelog-section 0.2.0" >&2; exit 1; }
[[ "$(scripts/changelog-section.sh 0.1.0 "$CL")" == $'### Adicionado\n- a' ]] || { echo "✗ changelog-section 0.1.0" >&2; exit 1; }
if scripts/changelog-section.sh 9.9.9 "$CL" >/dev/null 2>&1; then echo "✗ versão inexistente deveria falhar" >&2; exit 1; fi
NH=build/NeyHub.app/Contents/MacOS/NeyHub
$NH --validate-manifest Fixtures/HelloPlugin/manifest.json >/dev/null || { echo "✗ manifest bom recusado" >&2; exit 1; }
sed 's#libHelloPlugin.dylib#../x#' Fixtures/HelloPlugin/manifest.json > "$FIX/bad.json"
if $NH --validate-manifest "$FIX/bad.json" >/dev/null 2>&1; then echo "✗ binary ../x aceito" >&2; exit 1; fi
sed 's/"contract": 1/"contract": 2/' Fixtures/HelloPlugin/manifest.json > "$FIX/c2.json"
if $NH --validate-manifest "$FIX/c2.json" >/dev/null 2>&1; then echo "✗ contract 2 aceito" >&2; exit 1; fi
echo "selftest release ok"
