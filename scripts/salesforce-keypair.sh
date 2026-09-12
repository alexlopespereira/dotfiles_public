#!/bin/sh
# Gera o par de chaves do JWT Bearer do Salesforce (ADR §6.2; runbook privado de Salesforce).
#
# A chave PRIVADA nunca toca o disco: vive numa variável de shell, vai ao Keychain
# por stdin, e o processo morre com ela. Só o CERTIFICADO — material público — é
# gravado em arquivo, porque a UI do Salesforce exige upload.
#
# Uso: scripts/salesforce-keypair.sh <nome-do-projeto> [servico-do-keychain]
#
# O serviço é parametrizável porque há UMA ORG POR ALVO (salesforce.targets no
# config): sandbox e produção precisam de chaves distintas, e o serviço fixo
# fazia a segunda gravar por cima da primeira.
set -eu

PROJETO="${1:?uso: scripts/salesforce-keypair.sh <nome-do-projeto> [servico]}"
SERVICO="${2:-av-broker-salesforce}"
CRT="$HOME/Downloads/salesforce-${PROJETO}.crt"

command -v openssl >/dev/null || { echo "erro: openssl ausente." >&2; exit 1; }

if security find-generic-password -s "$SERVICO" >/dev/null 2>&1; then
  echo "aviso: o item '$SERVICO' já existe no Keychain." >&2
  echo "Isto SUBSTITUI a chave em uso. Se é rotação, o caminho é:" >&2
  echo "  av-broker rotate --target salesforce   (verifica antes de trocar)" >&2
  printf 'Continuar e sobrescrever? digite exatamente SOBRESCREVER: ' >&2
  read -r resp
  [ "$resp" = "SOBRESCREVER" ] || { echo "abortado." >&2; exit 1; }
fi

# 2048 e não 4096: o Salesforce aceita ambos, e 2048 mantém o JWT pequeno. A
# validade longa não é preguiça — a rotação é trimestral por política (Fase 4) e
# governada pelo log do broker, não pela expiração do certificado. Um cert curto
# aqui só adicionaria um segundo relógio para o mesmo evento.
KEY=$(openssl genrsa 2048 2>/dev/null) || { echo "erro: genrsa falhou." >&2; exit 1; }
CERT=$(printf '%s' "$KEY" | openssl req -new -x509 -days 730 -key /dev/stdin \
        -subj "/CN=av-broker-${PROJETO}" 2>/dev/null) \
  || { echo "erro: geração do certificado falhou." >&2; exit 1; }

# `security -i` lê o comando por STDIN. Duas razões, as duas já custaram algo
# nesta máquina:
#   - `-w "$(cat ...)"` poria a chave no argv, legível no `ps` por qualquer
#     processo seu — e o modelo de ameaça é exatamente esse.
#   - o prompt do `-w` sem valor trunca em 128 caracteres SEM erro e com status
#     0, o que destruiu a chave do GitHub App em 29/jul/2026.
# O base64 numa linha só existe porque `security -w` devolve HEX na leitura de
# qualquer valor com quebra de linha; o prefixo é o que o read_key() do broker lê.
B64="base64:$(printf '%s' "$KEY" | base64 | tr -d '\n')"
# Apagar-e-criar em vez de `-U`: sobre um item que JÁ existe, `-U -T ""` retorna
# 0 e mantém a ACL antiga em silêncio (medido em 29/jul/2026). Como `-T ""` só
# vale na criação, `-U` produziria uma chave sem diálogo achando que endureceu.
# O guard de sobrescrita acima é o que torna este delete seguro.
# Chaveiro EXPLICITO: sem ele o item cai no `login`, onde o `-T ""` acima nao e
# cobrado (partition_id aberto + chaveiro sempre destrancado, medido em
# 02/ago/2026). O mesmo bloco vivia em finish-github-app.sh, removido em
# 18/ago/2026 com o GitHub App; este arquivo passou a ser a referencia.
KC="${AV_KEYCHAIN:-$HOME/Library/Keychains/av-broker.keychain-db}"
[ -f "$KC" ] || {
  echo "erro: chaveiro $KC nao existe. Crie-o e ponha na search list:" >&2
  echo "  security create-keychain $KC   # pede uma senha (use a da sua conta)" >&2
  echo "  security list-keychains -d user -s ~/Library/Keychains/login.keychain-db $KC" >&2
  exit 1
}
security delete-generic-password -s "$SERVICO" "$KC" >/dev/null 2>&1 || true
printf 'add-generic-password -s %s -a %s -T "" -j %s -w %s "%s"\n' \
  "$SERVICO" "$PROJETO" \
  '"chave do JWT Bearer do Salesforce — av-broker (o runbook privado de Salesforce)"' \
  "$B64" "$KC" | security -i
unset B64 KEY

umask 077
printf '%s\n' "$CERT" > "$CRT"

echo "✅ chave privada no Keychain (serviço: $SERVICO, conta: $PROJETO)"
echo "✅ certificado em: $CRT"
echo
echo "Próximo passo — suba SÓ o certificado na UI:"
echo "  Setup → External Client Apps → seu app → Digital signature → $CRT"
echo
echo "Depois de subir, apague o arquivo (é público, mas não há motivo para ficar):"
echo "  rm -P $CRT"
echo
echo "Confira que a privada está legível pelo broker antes de configurar o app:"
echo "  av-broker doctor"
