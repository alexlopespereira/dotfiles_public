#!/usr/bin/env bash
# checkout-slot-identity.sh — hook SessionStart: diz ao agente EM QUAL checkout ele esta.
#
# Pre-requisito operacional do claude-yolo. Com --dangerously-skip-permissions
# ligado por default, o modo de falha caro nao e um comando errado: e o comando
# CERTO no diretorio errado. `cd` ja e a maior familia de erro do corpus (2.210
# chamadas no Mac, 3.294 no Windows em 31 dias), e um pool de N slots do MESMO
# repo multiplica a chance de escrever no slot que nao era.
#
# Emite o envelope estruturado hookSpecificOutput/additionalContext. As duas
# chaves existem no binario instalado (2.1.236: 46 ocorrencias de
# "additionalContext", "hookSpecificOutput" e "SessionStart" presentes, via
# `strings`, verificado em 27/ago/2026).
#
# Falha em silencio de proposito: fora de um repo git, ou sem python3, o hook
# nao deve derrubar a abertura de sessao. Sem contexto e pior que com contexto,
# mas e MUITO melhor que sessao que nao abre.
set -u

cwd="$(pwd -P)"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
name="$(basename "$root")"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '(sem git)')"

# Convencao do pool: ~/Projects/checkouts/<repo>-<N>. Se o diretorio nao termina
# em -<numero>, nao e um slot — provavelmente e o clone primario, e isso e
# justamente o que precisa aparecer.
slot="${name##*-}"
case "$slot" in
  ''|*[!0-9]*) slot="-"; repo="$name" ;;
  *)           repo="${name%-*}" ;;
esac

if [ "$slot" = "-" ]; then
  warn="Este NAO e um slot do pool (~/Projects/checkouts/<repo>-<N>)."
else
  warn="Trabalhe somente dentro deste caminho. Nao use 'cd' para outro slot do mesmo repo."
fi

ctx="CHECKOUT ATUAL: ${root}
  repo: ${repo}   slot: ${slot}   branch: ${branch}
${warn}"

command -v python3 >/dev/null 2>&1 || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$(printf '%s' "$ctx" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
