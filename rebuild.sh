#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles

# `sudo` reseta o PATH e o do root nao inclui /run/current-system/sw/bin, entao
# `sudo darwin-rebuild` falha com "command not found" mesmo com o binario no PATH
# do usuario. Resolve o caminho absoluto aqui, do lado de ca do sudo.
DARWIN_REBUILD="$(command -v darwin-rebuild || true)"
: "${DARWIN_REBUILD:=/run/current-system/sw/bin/darwin-rebuild}"
if [ ! -x "$DARWIN_REBUILD" ]; then
  echo "darwin-rebuild nao encontrado. Na primeira instalacao use o bootstrap.sh." >&2
  exit 1
fi

exec sudo "$DARWIN_REBUILD" switch --flake ~/.dotfiles#mac
