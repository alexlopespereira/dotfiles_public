#!/bin/sh
# Constroi a camada de imagem de UM projeto por cima do checkpoint "base".
#
# Uso, de dentro do repo do projeto:
#   scripts/shuru-project-image.sh              # checkpoint = nome do repo
#   scripts/shuru-project-image.sh --force
#   scripts/shuru-project-image.sh outro-nome
#
# O projeto precisa ter `vm/provision.sh` (o que instalar) e pode ter
# `vm/stage/` (arquivos que o provision quer ver montados em /provision).
# O requirements.txt da raiz, se existir, e staged automaticamente — e o caso
# comum e nao vale exigir boilerplate para ele.
#
# Por que a camada existe: o runtime dos projetos e OFFLINE por default
# (allow_net: false no shuru.json). Toda instalacao que precisa de rede tem de
# acontecer aqui, num passo supervisionado, uma vez — e nao a cada boot.
set -eu

FORCE=0
case "${1:-}" in --force|-f) FORCE=1; shift ;; esac

DOTFILES="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SHURU="${SHURU:-$HOME/.local/bin/shuru}"
BASE="${BASE:-base}"

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "erro: rode de dentro de um repo git (o projeto)." >&2; exit 1; }
CHECKPOINT="${1:-$(basename "$REPO")}"

[ -x "$SHURU" ] || { echo "erro: shuru nao encontrado — scripts/install-shuru.sh" >&2; exit 1; }
[ -f "$REPO/vm/provision.sh" ] || {
  echo "erro: $REPO/vm/provision.sh nao existe." >&2
  echo "A camada do projeto precisa dizer o que instalar. Veja o do meu-projeto." >&2
  exit 1; }
# Sem shuru.json o `shuru-vm` recusa subir, entao construir a imagem seria
# trabalho jogado fora — e o erro apareceria bem depois, na hora de usar.
[ -f "$REPO/shuru.json" ] || {
  echo "erro: $REPO/shuru.json nao existe — a allowlist de rede e obrigatoria." >&2
  exit 1; }

"$SHURU" checkpoint list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$BASE" || {
  echo "erro: checkpoint '$BASE' nao existe. Construa a imagem-base primeiro:" >&2
  echo "  $DOTFILES/scripts/shuru-base-image.sh" >&2
  exit 1; }

if "$SHURU" checkpoint list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$CHECKPOINT"; then
  if [ "$FORCE" -ne 1 ]; then
    echo "erro: o checkpoint '$CHECKPOINT' ja existe." >&2
    "$SHURU" checkpoint list >&2
    echo >&2
    echo "Reconstruir APAGA a imagem atual. Se e isso que voce quer:" >&2
    echo "  scripts/shuru-project-image.sh --force $CHECKPOINT" >&2
    exit 1
  fi
  APAGAR="$CHECKPOINT"
fi

# Diretorio de build proprio e descartavel: o shuru so monta caminhos DENTRO do
# diretorio corrente, e assim nao ha risco de montar por acidente algo de onde o
# script foi chamado.
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT INT TERM
chmod 700 "$BUILD"
mkdir "$BUILD/provision"
cp "$REPO/vm/provision.sh" "$BUILD/provision/provision.sh"
[ -f "$REPO/requirements.txt" ] && cp "$REPO/requirements.txt" "$BUILD/provision/"
# Um requirements por subprojeto e comum; achatamos o nome para que o provision
# possa referenciar sem saber a arvore. `services/requirements.txt` vira
# `services-requirements.txt` em /provision.
for req in $(cd "$REPO" && git ls-files '*/requirements.txt' 2>/dev/null); do
  cp "$REPO/$req" "$BUILD/provision/$(printf '%s' "$req" | tr '/' '-')"
done
[ -d "$REPO/vm/stage" ] && cp -R "$REPO/vm/stage/." "$BUILD/provision/"
chmod -R go-rwx "$BUILD/provision"

# O apagar vem DEPOIS do staging, pelo mesmo motivo do shuru-base-image.sh: se
# viesse antes, um erro no meio deixaria a maquina sem a imagem do projeto e sem
# comando de rename para fazer build-novo-depois-troca.
if [ -n "${APAGAR:-}" ]; then
  echo "Apagando checkpoint '$APAGAR' (--force)..."
  "$SHURU" checkpoint delete "$APAGAR"
fi

cd "$BUILD"
echo "Construindo '$CHECKPOINT' a partir de '$BASE' (rede de build ampla)..."
echo "O tempo e dominado por apt e pip; num stack com pandas espere alguns minutos."

# A rede AMPLA desta lista vale SO para o build. O runtime usa a allowlist do
# shuru.json do projeto, que e minima e offline por default.
# files.pythonhosted.org nao e redundante com pypi.org: o indice responde num
# host e os artefatos baixam do outro.
"$SHURU" checkpoint create "$CHECKPOINT" \
  --from "$BASE" \
  --cpus 4 --memory 8192 --disk-size 12288 \
  --allow-net \
  --allow-host deb.debian.org \
  --allow-host security.debian.org \
  --allow-host pypi.org \
  --allow-host files.pythonhosted.org \
  --allow-host registry.npmjs.org \
  --mount "./provision:/provision" \
  -- sh /provision/provision.sh

echo
echo "Checkpoint '$CHECKPOINT' criado."
echo "Suba com:  shuru-vm --from $CHECKPOINT     (de dentro de $REPO)"
