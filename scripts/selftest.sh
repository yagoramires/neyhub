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

# Fixtures (Task 3) entram aqui: --fixture <pasta>
rc=0
build/NeyHub.app/Contents/MacOS/NeyHub --selftest "$@" 2>"$ERR" || rc=$?
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
