#!/bin/zsh
# Imprime o corpo da seção "## [<v>]" do CHANGELOG. Uso: changelog-section.sh <versão> <CHANGELOG.md>
set -euo pipefail
(( $# == 2 )) || { echo "uso: $0 <versão> <CHANGELOG.md>" >&2; exit 2; }
OUT=$(awk -v h="## [$1]" 'index($0,h)==1{f=1;next} /^## \[/{f=0} f' "$2" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/./,$!d')
[[ -n "$OUT" ]] || { echo "✗ seção [$1] não existe (ou está vazia) em $2" >&2; exit 1; }
print -r -- "$OUT"
