#!/bin/sh
# Constroi o checkpoint "base" das microVMs shuru.
# Itens 5.2/5.7 do checklist; Fase 1 de docs/plano-adocao-tokens.md.
#
# O que entra: pnpm v10 + ignore-scripts, herdr-linux-aarch64, Claude Code,
# canary AWS da Thinkst. Detalhe em scripts/shuru/provision-base.sh.
#
# A rede AMPLA desta lista vale so para o build (passo supervisionado, feito por
# voce, uma vez). O runtime dos projetos usa a allowlist minima do shuru.json
# daquele projeto — nao esta.
#
# O canary NAO e versionado: vem do item `canary-vm-aws` do Keychain (cunhado na
# Fase 0). Ele passa por um diretorio de staging com modo 700, montado read-only,
# apagado no fim — o repo nunca ve o valor.
set -eu

# Uso: scripts/shuru-base-image.sh [--force] [checkpoint]
FORCE=0
case "${1:-}" in --force|-f) FORCE=1; shift ;; esac
CHECKPOINT="${1:-base}"
REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SHURU="${SHURU:-$HOME/.local/bin/shuru}"

[ -x "$SHURU" ] || { echo "erro: shuru nao encontrado — rode scripts/install-shuru.sh" >&2; exit 1; }

# `shuru checkpoint create` recusa sobrescrever, e a mensagem crua ("delete it
# first") nao diz que apagar a imagem-base e destrutivo. Reconstruir exige
# --force explicito.
if "$SHURU" checkpoint list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$CHECKPOINT"; then
  if [ "$FORCE" -ne 1 ]; then
    echo "erro: o checkpoint '$CHECKPOINT' ja existe." >&2
    "$SHURU" checkpoint list >&2
    echo >&2
    echo "Reconstruir APAGA a imagem atual. Se e isso que voce quer:" >&2
    echo "  scripts/shuru-base-image.sh --force $CHECKPOINT" >&2
    exit 1
  fi
  APAGAR_ANTES="$CHECKPOINT"
fi

# O cross-build do no-mistakes vem ANTES da leitura do Keychain de proposito: ele
# pode levar minutos e pode falhar, e falhar depois do dialogo desperdicaria um
# gesto humano que so existe para nao ser desperdicado. Puro e travado pelo
# flake.lock; o pin e o mesmo do host (nix/no-mistakes.nix).
echo "==> no-mistakes para o guest (linux/arm64)"
NM_GUEST=$(nix build --no-link --print-out-paths "$REPO_DIR/..#no-mistakes-guest") || {
  echo "erro: falhou o cross-build do no-mistakes para linux/arm64." >&2
  exit 1
}
[ -x "$NM_GUEST/bin/no-mistakes" ] || {
  echo "erro: $NM_GUEST/bin/no-mistakes nao existe ou nao e executavel." >&2
  exit 1
}

canary=$(security find-generic-password -s canary-vm-aws -w 2>/dev/null) || {
  echo "erro: item 'canary-vm-aws' ausente do Keychain." >&2
  echo "Cunhe o canary primeiro (Fase 0 — ver o runbook privado da Fase 0)." >&2
  exit 1
}

# O shuru so monta caminhos DENTRO do diretorio corrente, entao o build roda a
# partir de um diretorio proprio e descartavel — o que tambem evita montar por
# acidente qualquer coisa do diretorio de onde voce chamou o script.
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT INT TERM
chmod 700 "$BUILD_DIR"
cd "$BUILD_DIR"
mkdir provision

printf '%s\n' "$canary" | jq -r '
  "[default]\naws_access_key_id = \(.aws_access_key_id)\naws_secret_access_key = \(.aws_secret_access_key)\nregion = us-east-1"
' > provision/aws-canary-credentials
cp "$REPO_DIR/shuru/provision-base.sh" provision/provision-base.sh
# O shuru-pr entra na imagem-BASE, nao na camada de cada projeto: ele e generico
# (deriva repo, branch e slug do proprio git) e ter uma copia por repo criaria
# drift silencioso — a versao que roda seria a do projeto que foi construido por
# ultimo. Fonte unica: este arquivo aqui.
cp "$REPO_DIR/shuru-pr.sh" provision/shuru-pr.sh
# Do nix store (read-only, 0555) para o staging. O cp preserva o modo 555, e o
# chmod 600 abaixo so pega o dono — por isso o -f: sem ele o cp de uma segunda
# execucao esbarraria no arquivo sem permissao de escrita.
cp -f "$NM_GUEST/bin/no-mistakes" provision/no-mistakes
chmod 600 provision/*

# A ordem aqui e deliberada: o apagar vem DEPOIS da leitura do Keychain (linha
# ~40) e depois do staging do canary. Nao e detalhe — a leitura do canary
# bloqueia num dialogo de Keychain que exige gesto humano, e ja travou 31min numa
# tentativa anterior. Se o apagar viesse antes, um Ctrl-C nesse dialogo deixaria
# a maquina SEM imagem-base nenhuma, e nao ha comando de rename no shuru para
# fazer build-novo-depois-troca.
if [ -n "${APAGAR_ANTES:-}" ]; then
  echo "Apagando checkpoint '$APAGAR_ANTES' (--force)..."
  "$SHURU" checkpoint delete "$APAGAR_ANTES"
fi

# O "~15 min" e MEDIDO, nao chutado: o build de 29/jul/2026 comecou ~20:50 e a
# imagem ficou pronta 21:05:26. O valor anterior aqui era "~5 min", que
# subestimava por 3x — fazia parecer travado o que era so demora normal, e num
# passo que ja tem um dialogo de Keychain capaz de bloquear de verdade (linha
# ~41), anunciar prazo curto demais e pior que nao anunciar nada. O tempo e
# dominado pelo apt e pelo npm do provision, entao varia com a rede.
echo "Construindo checkpoint '$CHECKPOINT' (rede de build ampla, ~15 min — dominado por apt/npm, varia com a rede)..."
"$SHURU" checkpoint create "$CHECKPOINT" \
  --cpus 4 --memory 4096 --disk-size 8192 \
  --allow-net \
  --allow-host deb.debian.org \
  --allow-host security.debian.org \
  --allow-host registry.npmjs.org \
  --allow-host github.com \
  --allow-host objects.githubusercontent.com \
  --allow-host release-assets.githubusercontent.com \
  --allow-host claude.ai \
  --allow-host downloads.claude.ai \
  --mount "./provision:/provision" \
  -- sh /provision/provision-base.sh

echo
echo "Checkpoint '$CHECKPOINT' criado. Use com: shuru run --from $CHECKPOINT"
