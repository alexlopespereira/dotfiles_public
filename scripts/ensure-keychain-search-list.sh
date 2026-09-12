#!/bin/sh
# Garante que o chaveiro dedicado do broker esta na search list do Keychain.
#
# Chamado pela ativacao do home-manager (home.activation.avKeychainSearchList) e
# util a mao depois de um wipe. Idempotente: no caso comum nao faz nada.
#
# Por que isto existe. Desde 02/ago/2026 as cinco credenciais do broker vivem em
# ~/Library/Keychains/av-broker.keychain-db, e nao no login. O `security` acha um
# item varrendo a SEARCH LIST — que e preferencia de usuario, mora no plist e se
# perde num wipe. Sem ela o sintoma e cruel: nenhuma credencial e encontrada, com
# o arquivo do chaveiro intacto no disco. Era o unico estado manual que sobrava.
#
# NAO cria o chaveiro: `create-keychain` pede senha e ativacao nao e lugar de
# dialogo. Se ele nao existir, avisa e sai com 0 — falhar o rebuild inteiro por
# causa disto seria pior que o problema.
#
# `security` por caminho ABSOLUTO, e nada de grep/sed: o PATH da ativacao do
# home-manager nao tem /usr/bin, e chamar pelo nome fazia as tres invocacoes
# morrerem com "command not found" enquanto o script saia 0 — a garantia nunca
# rodava, em silencio, e so se notaria depois de um wipe. Testes ao lado.
set -eu

SECURITY="${AV_SECURITY:-/usr/bin/security}"
KC="${AV_KEYCHAIN:-$HOME/Library/Keychains/av-broker.keychain-db}"
BASE=${KC##*/}
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY=1

if [ ! -x "$SECURITY" ]; then
  echo "search-list: $SECURITY ausente ou nao executavel; PULADO."
  echo "  Rode a mao quando ele voltar: sh scripts/ensure-keychain-search-list.sh"
  exit 0
fi

if [ ! -f "$KC" ]; then
  echo "search-list: $KC nao existe; PULADO."
  echo "  Sem ele o broker nao acha credencial nenhuma. Para criar:"
  echo "    security create-keychain $KC"
  echo "  Ver docs/reinstall-checklist.md, item 3.2."
  exit 0
fi

# `-s` SUBSTITUI a lista inteira, entao a atual precisa ser lida e repassada.
# Perder o login.keychain aqui quebraria Wi-Fi, Safari e um punhado de outras
# coisas — dai ler antes de escrever, e nunca passar uma lista literal.
if ! LISTA=$("$SECURITY" list-keychains -d user); then
  echo "search-list: ERRO: '$SECURITY list-keychains -d user' falhou." >&2
  echo "  Nada foi escrito: um -s sem a lista atual apagaria o login.keychain." >&2
  exit 1
fi

# IFS=newline: caminho com espaco continua sendo UM argumento. A limpeza das
# aspas e do recuo e feita so com expansao de shell, sem sed.
set --
IFS='
'
for linha in $LISTA; do
  limpa=$linha
  while :; do
    case $limpa in
      [\ \	]*) limpa=${limpa#?} ;;
      *) break ;;
    esac
  done
  limpa=${limpa#\"}
  limpa=${limpa%\"}
  [ -n "$limpa" ] && set -- "$@" "$limpa"
done
unset IFS

# Lista lida vazia nunca pode virar escrita: seria trocar a search list inteira
# pelo chaveiro do broker sozinho. Falha alto, e falha fechado.
if [ "$#" -eq 0 ]; then
  echo "search-list: ERRO: '$SECURITY list-keychains -d user' nao devolveu chaveiro nenhum." >&2
  echo "  Nada foi escrito: escrever agora deixaria SO $BASE na lista, sem o login.keychain." >&2
  exit 1
fi

for atual in "$@"; do
  if [ "${atual##*/}" = "$BASE" ]; then
    echo "search-list: $BASE ja esta na lista."
    exit 0
  fi
done

if [ -n "$DRY" ]; then
  echo "search-list: rodaria -> $SECURITY list-keychains -d user -s $* $KC"
  exit 0
fi

# `|| ...` em vez de deixar o `set -e` agir: uma search list nao ajustada e um
# problema do broker, nao do sistema, e nao justifica abortar a ativacao com o
# home-manager no meio do trabalho. Fala alto e segue.
if "$SECURITY" list-keychains -d user -s "$@" "$KC"; then
  echo "search-list: $BASE acrescentado (a lista anterior foi preservada)."
else
  echo "search-list: FALHOU ao acrescentar $BASE — o broker nao vai achar"
  echo "  credencial nenhuma ate isto ser corrigido a mao. Ver"
  echo "  docs/reinstall-checklist.md, item 3.2. Seguindo mesmo assim."
fi
