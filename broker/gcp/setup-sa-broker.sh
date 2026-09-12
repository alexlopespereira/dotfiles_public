#!/usr/bin/env bash
# setup-sa-broker.sh — cria a raiz de confiança do GCP numa sessão administrativa
# efêmera. Fase 3 de docs/plano-adocao-tokens.md; desenho em
# docs/arquitetura-segredos.md §6.2.
#
# O que faz, e por que nesta ordem:
#   1. login  — a credencial de usuário existe só durante este script
#   2. cria a SA-broker (papel ÚNICO: tokenCreator sobre as SAs de projeto)
#   3. cria a SA de projeto, de baixo privilégio
#   4. gera a chave da SA-broker, importa no Keychain e APAGA o arquivo
#   5. revoke — a máquina volta ao estado "No credentialed accounts"
#
# A chave da SA-broker é o secret zero do GCP. Ela nunca fica em arquivo: o
# passo 4 é a única janela em que ela existe em disco, e é medida em segundos.

set -euo pipefail

KEYCHAIN_SERVICE="${KEYCHAIN_SERVICE:-av-broker-gcp}"

die() { printf '\n❌ %s\n' "$*" >&2; exit 1; }
step() { printf '\n▸ %s\n' "$*"; }

command -v gcloud >/dev/null || die "gcloud não está instalado nem no PATH."

PROJECT="${1:-}"; TARGET_NAME="${2:-av-agent}"
[ -n "$PROJECT" ] || die "uso: $0 <PROJECT_ID> [NOME_DA_SA_DE_PROJETO]
  PROJECT_ID        projeto do GCP onde as SAs vivem
  NOME_DA_SA        default: av-agent (a SA de baixo privilégio que o agente usa)"

BROKER_SA="av-broker@${PROJECT}.iam.gserviceaccount.com"
TARGET_SA="${TARGET_NAME}@${PROJECT}.iam.gserviceaccount.com"

cleanup() {
  step "Encerrando a sessão administrativa"
  gcloud auth revoke --all >/dev/null 2>&1 || true
  if gcloud auth list 2>&1 | grep -q "No credentialed accounts"; then
    echo "✅ gcloud sem conta ativa"
  else
    echo "❌ ainda há conta ativa — revogue à mão: gcloud auth revoke --all" >&2
  fi
}
trap cleanup EXIT INT TERM

step "Sessão administrativa (será revogada ao sair, aconteça o que acontecer)"
gcloud auth login --brief

step "SA-broker: ${BROKER_SA}"
gcloud iam service-accounts create av-broker \
  --project="$PROJECT" \
  --display-name="av-broker (cunha tokens efêmeros no host)" 2>/dev/null \
  || echo "  já existe, seguindo"

step "SA de projeto (baixo privilégio): ${TARGET_SA}"
gcloud iam service-accounts create "$TARGET_NAME" \
  --project="$PROJECT" \
  --display-name="agente: ${TARGET_NAME}" 2>/dev/null \
  || echo "  já existe, seguindo"

step "Binding: a SA-broker só pode impersonar a SA de projeto"
# Papel ÚNICO da SA-broker. Ela não recebe permissão de dado nenhum — só o
# direito de cunhar token para esta SA específica. É o que mantém o raio pequeno
# mesmo se a chave dela vazar.
gcloud iam service-accounts add-iam-policy-binding "$TARGET_SA" \
  --project="$PROJECT" \
  --member="serviceAccount:${BROKER_SA}" \
  --role="roles/iam.serviceAccountTokenCreator" >/dev/null

step "Habilitando iamcredentials.googleapis.com"
gcloud services enable iamcredentials.googleapis.com --project="$PROJECT" >/dev/null

step "Chave da SA-broker → Keychain (o arquivo morre em seguida)"
TMPKEY="$(mktemp -t av-broker-key)"
chmod 600 "$TMPKEY"
shred_key() { rm -f "$TMPKEY"; }
trap 'shred_key; cleanup' EXIT INT TERM

gcloud iam service-accounts keys create "$TMPKEY" \
  --project="$PROJECT" --iam-account="$BROKER_SA" >/dev/null

# O broker assina JWT com a chave PEM; o JSON do gcloud traz o PEM em
# .private_key. Guardamos só o PEM — o resto do JSON não é segredo.
PEM="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private_key"], end="")' "$TMPKEY")"
[ -n "$PEM" ] || die "não consegui extrair private_key do JSON da chave."

# A chave NAO vai em `argv`: qualquer processo rodando como voce a leria no `ps`
# enquanto o comando durasse, e o modelo de ameaca aqui e exatamente "agente
# comprometido rodando como alex".
#
# `security -i` le o comando inteiro do STDIN; o argv do processo fica so
# "security -i" (verificado com `ps -axww` durante a gravacao) e o exit code do
# comando interno e propagado, entao o `set -e` acima continua valendo.
#
# NAO troque pelo prompt do `-w` sem valor: ele trunca em 128 caracteres SEM
# erro, o que transforma a chave em lixo silenciosamente.
#
# O base64 numa linha so existe porque o `security` devolve HEX para qualquer
# valor com quebra de linha; o prefixo e o que o read_key() do av-broker le.
B64="base64:$(printf '%s' "$PEM" | base64 | tr -d '\n')"
printf 'add-generic-password -U -s %s -a %s -T "" -j %s -w %s\n' \
  "$KEYCHAIN_SERVICE" "$BROKER_SA" \
  '"secret zero do GCP — av-broker (docs/arquitetura-segredos.md 6.2)"' \
  "$B64" | security -i
unset B64 PEM

rm -f "$TMPKEY"
echo "✅ chave no Keychain (serviço: ${KEYCHAIN_SERVICE}) e arquivo removido"

cat <<EOF

────────────────────────────────────────────────────────────────
Pronto. Acrescente ao ~/.config/av-broker/config.json:

  "gcp": {
    "broker_sa_email": "${BROKER_SA}",
    "key_provider": "keychain:${KEYCHAIN_SERVICE}"
  }

Teste (o gate vai promptar — escopo cloud-platform é classe ESCRITA):
  av-broker gcp --target-sa ${TARGET_SA} --dry-run

Depois, dê à SA de projeto SÓ as permissões que o trabalho exige.
Ela nasceu sem nenhuma — de propósito.
────────────────────────────────────────────────────────────────
EOF
