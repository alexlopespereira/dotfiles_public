#!/bin/sh
# VM do PROJETO DOTFILES. A lógica toda vive em shuru-vm.sh, que é genérico e
# funciona em qualquer repo — este arquivo existe só para fixar o repo e para
# não invalidar os docs e o hábito que já apontam para cá.
#
# Para qualquer outro projeto, use `shuru-vm` a partir da raiz dele (está no
# PATH via home.sessionPath).
#
# Uso:
#   scripts/shuru-dev.sh                 # com rede, allowlist do shuru.json
#   scripts/shuru-dev.sh --offline       # sem rede
#   scripts/shuru-dev.sh -- claude ...   # roda um comando em vez do shell
set -eu

REPO="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPO"
exec "$REPO/scripts/shuru-vm.sh" "$@"
