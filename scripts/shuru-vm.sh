#!/bin/sh
# Sobe a VM DO PROJETO em que você está, com o setup-token real, sem que ele
# passe pelo seu shell. Genérico: funciona em qualquer repo, não só no dotfiles.
#
# Existe porque `shuru-dev.sh` derivava o repo de `dirname $0/..` e portanto só
# servia ao dotfiles — o que travava a regra de ouro 5.3 ("uma VM por projeto,
# montando só aquele repo") no primeiro projeto novo.
#
# Uso (a partir da raiz do projeto):
#   shuru-vm                        # com rede, allowlist do shuru.json do projeto
#   shuru-vm --offline              # sem rede
#   shuru-vm --from meu-projeto   # checkpoint próprio do projeto
#   shuru-vm -- pytest -q           # roda um comando em vez do shell
set -eu

SHURU="${SHURU:-$HOME/.local/bin/shuru}"
[ -x "$SHURU" ] || { echo "erro: shuru ausente — rode scripts/install-shuru.sh" >&2; exit 1; }

REDE="--allow-net"
CHECKPOINT="base"
while [ $# -gt 0 ]; do
  case "$1" in
    --offline) REDE=""; shift ;;
    --from)    CHECKPOINT="${2:?--from exige um nome de checkpoint}"; shift 2 ;;
    --)        shift; break ;;
    *)         break ;;
  esac
done

# A raiz do projeto é a raiz do repo git, não o cwd: montar um subdiretório
# esconderia metade do projeto do agente e daria a impressão de que ele "não
# achou o arquivo" quando o problema é o mount.
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "erro: não estou num repositório git. A VM monta um repo, não um diretório solto." >&2
  exit 1
}

# RECUSA se o projeto não declarar sua própria allowlist. Não é burocracia: sem
# shuru.json o `shuru run --allow-net` sobe com rede IRRESTRITA, que é o oposto
# do item 5.6 (offline por default) e o oposto de "config de segurança mora em
# git" (7.2). Falhar aqui é mais seguro que subir uma VM aberta.
[ -f "$REPO/shuru.json" ] || {
  cat >&2 <<FIM
erro: $REPO/shuru.json não existe.

Cada projeto declara a própria allowlist de rede, versionada em git (itens 5.3 e
7.2). Sem esse arquivo, --allow-net daria rede irrestrita à VM.

Comece copiando o do dotfiles como referência e CORTE o que este projeto não
usa — a allowlist certa é a menor que faz o trabalho:
  cp <dotfiles>/shuru.json "$REPO/shuru.json"
FIM
  exit 1
}

# Existência ANTES do valor, e não por elegância: desde 02/ago/2026 o token vive
# num chaveiro dedicado com ACL vazia, então ler o VALOR abre um diálogo de
# autorização (~3s, medido). Sem esta separação, cancelar o diálogo cairia na
# mensagem de "não custodiado" — um diagnóstico falso que manda você regravar um
# token que está ali, íntegro. A busca por metadado nunca prompta.
if ! security find-generic-password -s claude-setup-token >/dev/null 2>&1; then
  cat >&2 <<'FIM'
erro: setup-token não custodiado.

  claude setup-token                    # interativo; NAO use pipe, ele trava
  stty -echo; printf 'token: '; read -r T; stty echo; echo
  printf '%s' "$T" | av-broker rotate --target anthropic; unset T

Se você TEM certeza de que gravou: o chaveiro dedicado pode ter caído da search
list (ela não está no nix e se perde num wipe). Confira com `av-broker doctor`.

Ver o runbook privado da Fase 0 §2.
FIM
  exit 1
fi

TOKEN=$(security find-generic-password -s claude-setup-token -w 2>/dev/null || true)
if [ -z "$TOKEN" ]; then
  cat >&2 <<'FIM'
erro: o token está no Keychain, mas a leitura não foi autorizada.

O item tem ACL vazia e mora no chaveiro dedicado: ler o valor exige o diálogo do
macOS. Ou ele foi cancelado, ou não há sessão gráfica para mostrá-lo (ssh, cron,
launchd sem Aqua). Rode de uma sessão com tela e autorize.
FIM
  exit 1
fi

case "$TOKEN" in
  sk-ant-*) ;;
  *) echo "aviso: o valor no Keychain não parece um setup-token (não começa com sk-ant-)." >&2 ;;
esac

cd "$REPO"

# GITHUB_TOKEN entra na VM por MOUNT, e não por variável (18/ago/2026).
#
# Antes: o host derivava o blob `Basic` aqui e passava os dois como `secrets` do
# shuru.json; o guest via só placeholders, trocados pelo proxy no egress. Um
# base64 feito DENTRO do guest esconderia o placeholder e o GitHub recusaria com
# "Password authentication is not supported for Git operations" (medido em
# 31/jul/2026). Toda essa coreografia existia para o guest NÃO ver o segredo.
#
# Agora o segredo é um PAT fine-grained de vida longa (`github-pat-vm`) e a
# decisão foi deixá-lo disponível dentro do container. Como o `shuru run` não
# tem `--env`, o canal é um mount read-only de um diretório temporário 0700.
# O guest lê /ghcred/token e codifica o Basic sozinho (ver shuru-pr.sh).
#
# Sem GITHUB_TOKEN no ambiente não há mount nenhum — ausência é ausência, e o
# shuru-pr falha claro em vez de tentar autenticar com lixo.
GHCRED=""
cleanup_ghcred() { [ -z "$GHCRED" ] || rm -rf "$GHCRED"; GHCRED=""; }
if [ -n "${GITHUB_TOKEN:-}" ]; then
  GHCRED=$(mktemp -d "${TMPDIR:-/tmp}/shuru-vm-ghcred.XXXXXX")
  chmod 700 "$GHCRED"
  ( umask 077; printf '%s\n' "$GITHUB_TOKEN" > "$GHCRED/token" )
  trap 'cleanup_ghcred' EXIT HUP INT TERM
  set -- --mount "${GHCRED}:/ghcred:ro" "$@"
fi

# O token entra só no ambiente DESTE processo — nunca `export` num shell
# interativo, que o deixaria vivo para todo processo filho seu.
#
# `exec` só quando não há nada a limpar: processo substituído não roda trap EXIT,
# e o diretório do PAT ficaria no /tmp do host para sempre.
if [ -z "$GHCRED" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
    exec "$SHURU" run --from "$CHECKPOINT" $REDE "$@"
fi
RC=0
CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" \
  "$SHURU" run --from "$CHECKPOINT" $REDE "$@" || RC=$?
cleanup_ghcred
exit "$RC"
