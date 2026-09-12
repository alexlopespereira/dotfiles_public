#!/bin/sh
# Gate da Fase 1 (docs/plano-adocao-tokens.md): "o Claude Code funciona dentro da
# VM SEM NENHUM SEGREDO REAL dentro dela — inspecionar env, disco e ~/.claude do
# guest". As verificacoes que rodam no guest estao em scripts/shuru/gate-fase1.sh.
#
# Roda com um segredo SENTINELA, nao com o setup-token de verdade: se o desenho
# vazasse o valor, quem vaza e um valor descartavel. O caminho exercitado e
# identico — o proxy nao distingue um do outro.
#
# Uso: scripts/shuru-verify-gate.sh [checkpoint]   (default: base)
set -eu

CHECKPOINT="${1:-base}"
REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SHURU="${SHURU:-$HOME/.local/bin/shuru}"
[ -x "$SHURU" ] || { echo "erro: shuru ausente — rode scripts/install-shuru.sh" >&2; exit 1; }

# O shuru so monta caminhos dentro do diretorio corrente.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT INT TERM; cd "$WORK"
mkdir gate && cp "$REPO_DIR/shuru/gate-fase1.sh" gate/

SENTINELA="sk-ant-oat01-SENTINELA-$(date +%s)-NAO-E-SEGREDO-REAL"
export SENTINELA

echo "Sentinela deste teste: $SENTINELA"
echo "Rodando o gate no checkpoint '$CHECKPOINT'..."
echo

# postman-echo.com e httpbingo.org devolvem os headers que receberam — e o unico
# jeito de VER o que saiu da VM. api.anthropic.com nao serve: nao ecoa nada, e um
# 401 nao distingue "placeholder foi trocado" de "token invalido".
# Os dois estao na allowlist de REDE, mas so o primeiro esta na lista de hosts do
# SECRET — e essa diferenca e o que o teste 6 mede.
"$SHURU" run --from "$CHECKPOINT" --disk-size 8192 --allow-net \
  --allow-host postman-echo.com \
  --allow-host httpbingo.org \
  --secret CLAUDE_CODE_OAUTH_TOKEN=SENTINELA@postman-echo.com \
  --mount ./gate:/gate \
  -- sh /gate/gate-fase1.sh
