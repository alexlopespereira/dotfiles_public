#!/bin/sh
# Instala o shuru (CLI + imagem de SO) com VERSAO PINADA e hash conferido.
# FASE 5.1 do checklist; Fase 1 de docs/plano-adocao-tokens.md.
#
# Por que nao o tap superhq-ai/tap: `onActivation.upgrade = true` no
# configuration.nix faz toda formula do brew seguir o latest — e o plano exige
# pin (projeto jovem, research-preview; ADR arquitetura-segredos.md §6.3).
# Por que nao o install.sh deles: baixa o "latest" e NAO confere hash nenhum.
#
# O pin e duplo: versao fixa + SHA-256 conferido antes de extrair, nos dois
# artefatos. A copia baixada fica em ~/Projects/vendor/shuru-releases/ (fora
# deste repo — a imagem tem 186 MB), junto do source vendorizado em
# ~/Projects/vendor/shuru (tag v0.6.5).
#
# NUNCA rode `shuru upgrade`: ele troca binario e imagem pelo latest do GitHub,
# sem hash, e queima o pin. Bump de versao = editar VERSION e os dois hashes
# abaixo, ler o CHANGELOG e RE-RODAR o gate adversarial da Fase 2
# (research/egress.md §4.4) — a garantia de egress nao transfere entre versoes.
set -eu

VERSION="0.6.5"
CLI_SHA256="fee960cb3c158549fd23465e5f3dea39d80383d4bd722c9e0141916a98b36dcf"
OS_SHA256="dde4f1d9ee2c25ef4560ab8fcdc424b6f9479091e483e14f2a3fa46575f43e4b"

REPO="superhq-ai/shuru"
INSTALL_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/shuru"   # shuru_vm::default_data_dir()
VENDOR_DIR="$HOME/Projects/vendor/shuru-releases/v${VERSION}"

[ "$(uname -s)/$(uname -m)" = "Darwin/arm64" ] || {
  echo "erro: este instalador cobre so macOS Apple Silicon" >&2; exit 1;
}

mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$VENDOR_DIR"

# Baixa (se preciso) e confere o hash. Sem hash bom, nada e extraido.
fetch() {
  name="$1"; want="$2"
  if [ ! -f "$VENDOR_DIR/$name" ]; then
    echo "Baixando $name..."
    curl -fSL --progress-bar \
      "https://github.com/${REPO}/releases/download/v${VERSION}/${name}" \
      -o "$VENDOR_DIR/$name"
  fi
  echo "${want}  ${VENDOR_DIR}/${name}" | shasum -a 256 -c - >/dev/null || {
    echo "ABORTADO: SHA-256 de ${name} nao confere." >&2
    echo "Release trocada sob o mesmo tag, download corrompido ou adulteracao." >&2
    echo "Nao instale. Investigue antes de mexer no hash deste script." >&2
    exit 1
  }
  echo "  sha256 OK: $name"
}

fetch "shuru-v${VERSION}-darwin-aarch64.tar.gz" "$CLI_SHA256"
fetch "shuru-os-v${VERSION}-aarch64.tar.gz"     "$OS_SHA256"

tar -xzf "$VENDOR_DIR/shuru-v${VERSION}-darwin-aarch64.tar.gz" -C "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/shuru"
xattr -d com.apple.quarantine "$INSTALL_DIR/shuru" 2>/dev/null || true

# Imagem de SO instalada daqui, e nao por `shuru init`: o init baixa direto do
# GitHub sem verificar hash (crates/shuru-cli/src/assets.rs). O arquivo VERSION
# e o que faz o shuru considerar os assets prontos e nao re-baixar.
tar -xzf "$VENDOR_DIR/shuru-os-v${VERSION}-aarch64.tar.gz" -C "$DATA_DIR"
printf '%s\n' "$VERSION" > "$DATA_DIR/VERSION"

echo
"$INSTALL_DIR/shuru" --version
echo "imagem de SO v${VERSION} em ${DATA_DIR}"
