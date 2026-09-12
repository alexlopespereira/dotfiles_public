#!/usr/bin/env bash
# shopify-token.sh — imprime o Admin API token do Shopify em stdout, atrás do
# gate do av-broker. Setup da cadeia IAM: broker/gcp/setup-sa-shopify-secret.sh
#
# Por que existe: o Shopify não cunha credencial efêmera (arquitetura-segredos.md
# §3, "a cauda longa de APIs de terceiros"). O token é estático e vive no Secret
# Manager, que é a fonte única — as Cloud Functions leem o MESMO segredo em
# runtime. Este script não copia nada; ele apenas troca o acesso local por uma
# aprovação explícita.
#
# Uso:
#   SHOPIFY_TOKEN="$(scripts/shopify-token.sh)" node scripts/upload-to-shopify-files.js ...
#
# O token vai para o AMBIENTE do comando, nunca para o argv: qualquer processo
# rodando como você leria o argv no `ps`, e o modelo de ameaça aqui é exatamente
# "agente comprometido rodando como alex".

set -euo pipefail

PROJECT="${SHOPIFY_SECRET_PROJECT:-projeto-segredos}"
SECRET="${SHOPIFY_SECRET_NAME:-meu-projeto-shopify-access-token}"
TARGET_SA="${AV_TARGET_SA:-av-agent@${PROJECT}.iam.gserviceaccount.com}"
LIFETIME="${AV_LIFETIME:-300}"

die() { printf '❌ %s\n' "$*" >&2; exit 1; }

command -v av-broker >/dev/null || die "av-broker não está no PATH."
command -v curl >/dev/null || die "curl não está no PATH."

# Escopo: cloud-platform (o default). NÃO use cloud-platform.read-only achando
# que rebaixa a classificação — o classify_gcp() do broker só reconhece sufixo
# `.readonly`/`.read_only`, e o escopo do Google termina em `.read-only`, com
# hífen. Ele cairia em classe ESCRITA do mesmo jeito, com um escopo a menos
# testado. Classe escrita aqui é o comportamento desejado: prompta sempre, nunca
# abre sessão silenciosa. Ler um token de produção não deveria ser silencioso.
ACCESS_TOKEN="$(av-broker gcp \
  --target-sa "$TARGET_SA" \
  --lifetime "$LIFETIME" \
  --emit token)" || die "av-broker recusou ou falhou a cunhagem."
[ -n "$ACCESS_TOKEN" ] || die "av-broker devolveu token vazio."

URL="https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/${SECRET}/versions/latest:access"

# -K - lê a config do stdin: o Bearer não aparece no argv do curl.
RESPONSE="$(printf 'header = "Authorization: Bearer %s"\nurl = "%s"\nsilent\nshow-error\nfail\n' \
  "$ACCESS_TOKEN" "$URL" | curl -K -)" || die "Secret Manager recusou a leitura."
unset ACCESS_TOKEN

printf '%s' "$RESPONSE" | python3 -c '
import base64, json, sys
try:
    payload = json.load(sys.stdin)["payload"]["data"]
except (KeyError, ValueError):
    sys.exit("resposta do Secret Manager sem payload.data")
sys.stdout.write(base64.b64decode(payload).decode("utf-8").strip())
'
