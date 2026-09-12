#!/usr/bin/env bash
# setup-sa-shopify-secret.sh — dá ao av-broker um caminho gateado para LER o
# token do Shopify, sem criar uma segunda cópia do segredo.
#
# O desenho (docs/arquitetura-segredos.md §3): o Shopify emite apenas chave
# estática e longeva — não há cunhagem efêmera para replicar a opção A. O que dá
# para fazer é manter UMA cópia no Secret Manager e gatear a leitura local. O que
# fica efêmero não é o token do Shopify, é o access token do GCP que o lê.
#
# Cadeia de confiança resultante:
#   chave da SA-broker (Keychain, sob diálogo do macOS)
#     → impersona av-agent@projeto-segredos  (token de ≤5 min, escopo cloud-platform)
#       → secretmanager.versions.access  APENAS neste secret
#         → token do Shopify em stdout do scripts/shopify-token.sh
#
# Roda numa sessão administrativa efêmera, como setup-sa-broker.sh: login no
# início, revoke no fim, aconteça o que acontecer.

set -euo pipefail

PROJECT="${PROJECT:-projeto-segredos}"
SECRET="${SECRET:-meu-projeto-shopify-access-token}"
TARGET_NAME="${TARGET_NAME:-av-agent}"
TARGET_SA="${TARGET_NAME}@${PROJECT}.iam.gserviceaccount.com"

die() { printf '\n❌ %s\n' "$*" >&2; exit 1; }
step() { printf '\n▸ %s\n' "$*"; }

command -v gcloud >/dev/null || die "gcloud não está instalado nem no PATH."
command -v python3 >/dev/null || die "python3 não está no PATH."

CONFIG="${AV_BROKER_CONFIG:-$HOME/.config/av-broker/config.json}"
[ -f "$CONFIG" ] || die "config do av-broker não encontrado em $CONFIG"

BROKER_SA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["gcp"]["broker_sa_email"] or "")' "$CONFIG")"
[ -n "$BROKER_SA" ] || die "gcp.broker_sa_email vazio em $CONFIG — rode setup-sa-broker.sh antes."

cat <<EOF
────────────────────────────────────────────────────────────────
  Projeto do secret : ${PROJECT}
  Secret            : ${SECRET}
  SA de projeto     : ${TARGET_SA}
  SA-broker         : ${BROKER_SA}

A SA-broker vive em OUTRO projeto. O binding abaixo é cross-project — o IAM
aceita membro de qualquer projeto, mas quem executa precisa ser admin de
${PROJECT}.
────────────────────────────────────────────────────────────────
EOF

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

step "Sessão administrativa (será revogada ao sair)"
gcloud auth login --brief

step "SA de projeto (baixo privilégio): ${TARGET_SA}"
gcloud iam service-accounts create "$TARGET_NAME" \
  --project="$PROJECT" \
  --display-name="agente: ${TARGET_NAME} (leitura gateada de segredos)" 2>/dev/null \
  || echo "  já existe, seguindo"

step "Binding: a SA-broker pode impersonar ${TARGET_NAME}"
gcloud iam service-accounts add-iam-policy-binding "$TARGET_SA" \
  --project="$PROJECT" \
  --member="serviceAccount:${BROKER_SA}" \
  --role="roles/iam.serviceAccountTokenCreator" >/dev/null

# secretAccessor NO SECRET, não no projeto. É a diferença entre "lê este token"
# e "lê todo segredo de projeto-segredos" — inclusive os das Cloud Functions.
step "Acesso: ${TARGET_NAME} lê SÓ o secret ${SECRET}"
gcloud secrets add-iam-policy-binding "$SECRET" \
  --project="$PROJECT" \
  --member="serviceAccount:${TARGET_SA}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null

step "Habilitando iamcredentials.googleapis.com em ${PROJECT}"
gcloud services enable iamcredentials.googleapis.com --project="$PROJECT" >/dev/null

cat <<EOF

────────────────────────────────────────────────────────────────
Pronto. Teste sem chamar a API:

  av-broker gcp --target-sa ${TARGET_SA} --dry-run

Depois, de ponta a ponta (vai abrir o diálogo do macOS):

  scripts/shopify-token.sh | wc -c     # imprime o tamanho, não o token

⚠️  O gate só passa a valer quando NÃO houver credencial de usuário no gcloud.
    Enquanto \`gcloud auth list\` mostrar conta ativa com acesso a ${PROJECT},
    qualquer processo seu lê o secret direto, sem diálogo nenhum.
────────────────────────────────────────────────────────────────
EOF
