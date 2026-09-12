#!/bin/sh
# Provisionamento da imagem-base das microVMs shuru (guest Debian 13 trixie,
# aarch64, roda como root). Executado DENTRO da VM por scripts/shuru-base-image.sh
# — nao rode isto no host.
#
# Itens 5.2 e 5.7 do checklist; Fase 1 de docs/plano-adocao-tokens.md.
# Higiene de supply chain (pnpm v10 + ignore-scripts) e canary plantado sao o
# conteudo desta imagem; a rede daqui pra frente e a minima do projeto piloto.
set -eu

HERDR_VERSION="0.7.5"
HERDR_SHA256="32e763a1499a6b694b1d708e4f062b743be1da9f34fcfa4d212d6db6fe09a8b9"
PNPM_VERSION="10"
# gh 2.97.0 saiu em 31/jul/2026 02:04Z e cai DENTRO do cooldown de 3 dias
# declarado logo abaixo — por isso o pin fica em 2.96.0 (02/jul/2026). O sha256 e
# o da linha gh_2.96.0_linux_arm64.tar.gz do checksums.txt oficial, copiado para
# ca: conferir contra um arquivo baixado na mesma hora nao prova nada.
GH_VERSION="2.96.0"
GH_SHA256="06f86ec7103d41993b76cd78072f43595c34aaa56506d971d9860e67140bf909"

echo "==> apt: ferramentas base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# python3 e explicito desde 30/jul/2026. O vm/provision.sh do meu-projeto ja
# afirmava "a base traz ... python3 (SEM pip)", mas a base NAO o instalava — a
# afirmacao era verdadeira por acidente, porque a camada daquele projeto puxa
# python3 como dependencia do python3-pip. Um projeto sem stack de Python teria
# herdado uma base sem python3, e o shuru-pr.sh (que usa urllib para falar com a
# API do GitHub) so falharia no primeiro uso, dentro da VM.
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl git jq nodejs npm ripgrep less python3

echo "==> npm: ignore-scripts global (vetor Shai-Hulud pre/postinstall)"
# /etc/npmrc vale para todo usuario do guest, inclusive o agente. E o item 5.2:
# a defesa nº1 depois do Shai-Hulud (research/seguranca_containers.md, Problema 5).
cat > /etc/npmrc <<'EOF'
ignore-scripts=true
audit=false
fund=false
EOF

echo "==> pnpm v${PNPM_VERSION}"
# --ignore-scripts explicito: o /etc/npmrc acima ja cobre, mas este install e o
# unico que roda antes de qualquer verificacao, entao nao dependa dele.
npm install -g --ignore-scripts "pnpm@${PNPM_VERSION}"

# Cooldown de versoes: nao instalar release publicada ha menos de 3 dias. As duas
# janelas do Shai-Hulud (2,5 h e ~12 h ate a remocao) caem dentro disso.
# pnpm v10 ja NAO roda lifecycle script de dependencia por default — a allowlist
# e explicita via onlyBuiltDependencies no projeto, e deve ficar vazia.
cat > /etc/pnpmrc <<'EOF'
minimum-release-age=4320
EOF
printf 'minimum-release-age=4320\n' >> /etc/npmrc

echo "==> herdr ${HERDR_VERSION} (backend de terminal dentro da VM)"
curl -fsSL -o /usr/local/bin/herdr \
  "https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-aarch64"
echo "${HERDR_SHA256}  /usr/local/bin/herdr" | sha256sum -c -
chmod +x /usr/local/bin/herdr

echo "==> gh ${GH_VERSION} (CLI oficial do GitHub)"
# Release oficial do cli/cli, nao o apt do Debian (que atrasa versoes) nem um
# repositorio de terceiro. Mesmo padrao do herdr acima: baixa, confere sha256
# pinnado, instala. O gh existe aqui para o no-mistakes: o pipeline abre PR e le
# checks por ele. As credenciais NAO moram na imagem — entram por GH_TOKEN vindo
# do proxy de segredos do shuru, em tempo de boot.
curl -fsSL -o /tmp/gh.tar.gz \
  "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_arm64.tar.gz"
echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c -
tar -xzf /tmp/gh.tar.gz -C /tmp
install -m 0755 "/tmp/gh_${GH_VERSION}_linux_arm64/bin/gh" /usr/local/bin/gh
rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_arm64"

echo "==> no-mistakes (compilado do source para linux/arm64 no host)"
# Nao ha release binario upstream para este alvo, entao o binario e
# cross-compilado pelo Nix no host (nix/no-mistakes.nix, MESMO pin que o host
# usa) e chega aqui pelo staging read-only. Ver scripts/shuru-base-image.sh.
install -m 0755 /provision/no-mistakes /usr/local/bin/no-mistakes
# Executa AQUI, e nao so no resumo do fim: este e o primeiro momento em que o
# binario cross-compilado roda de verdade num aarch64 Linux. Se o alvo estivesse
# errado, falhar neste ponto custa segundos; falhar no resumo custaria o
# provisionamento inteiro (apt + Claude Code + canary) que vem depois.
# O `timeout` nao e paranoia: a rede AINDA esta aberta neste ponto do build, e
# um `--version` que resolva disparar checagem de atualizacao penduraria o
# provisionamento sem imprimir nada. Stall mudo e o pior modo de falha deste
# script — ja custou 8 h nesta maquina num bloqueio de Keychain mascarado.
timeout 30 no-mistakes --version >/dev/null || {
  echo "erro: o no-mistakes cross-compilado nao executa (ou pendurou) neste guest." >&2
  exit 1; }

echo "==> Claude Code (instalador nativo da Anthropic)"
# O agente roda DENTRO da VM (item 5.4). Instalador nativo em vez do pacote npm:
# com ignore-scripts=true o postinstall do pacote npm nao baixaria o binario.
curl -fsSL https://claude.ai/install.sh | bash
install -m 0755 /root/.local/bin/claude /usr/local/bin/claude 2>/dev/null \
  || install -m 0755 "$HOME/.local/bin/claude" /usr/local/bin/claude

echo "==> onboarding marcado como concluido (ADR §6.4)"
# SEM isto a TUI e inutilizavel na VM, e o modo de falha e perigoso: a VM nasce
# limpa a cada boot, entao o Claude Code nao acha estado de first-run e roda o
# onboarding — cujo segundo passo e "Select login method", ou seja, EXATAMENTE o
# /login que o ADR §6.4 proibe. O usuario e apresentado a uma tela que pede para
# ele violar o desenho, e completa-la gravaria access + refresh reais em
# ~/.claude/.credentials.json dentro do guest.
#
# Medido em 29/jul/2026 antes de escrever isto, para nao consertar a causa
# errada: com CLAUDE_CODE_OAUTH_TOKEN bem-formado (sk-ant-oat01-...) em vez do
# placeholder do shuru, a MESMA tela aparece. Nao e o formato do placeholder nem
# a allowlist — e a ausencia de estado de onboarding, e so.
#
# Arquivo escrito do zero, minimo. NAO se copia o ~/.claude.json do host: ele
# carrega userID (identificador estavel da instalacao), historico e config de
# MCP, e nada disso tem por que atravessar a fronteira host->VM.
#
# A versao sai do binario que acabou de ser instalado, nao fixa no fonte: o
# Claude Code re-dispara o onboarding quando `lastOnboardingVersion` fica para
# tras, entao um valor fixo aqui viraria a mesma tela de login de volta no dia
# em que a imagem for reconstruida com um claude mais novo.
CLAUDE_VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -n "$CLAUDE_VER" ] || { echo "erro: nao consegui ler a versao do claude" >&2; exit 1; }
#
# `autoUpdates: false` junto: medido, o `shuru run` deixa o guest com HOME=/ e
# o Claude Code tentava se atualizar a cada boot ("Auto-update failed"). Falhava
# fechado, porque o host de download nao esta na allowlist — mas o desenho certo
# nao e depender disso. Binario que se troca sozinho pela rede a cada sessao e
# superficie de supply chain dentro da VM, e a imagem-base deixa de ser
# reproduzivel. A versao sobe quando ESTA imagem for reconstruida, e so.
# Mesmo racional do DISABLE_AUTOUPDATER no host (configuration.nix, cask).
#
# Escrito nos DOIS caminhos de proposito: em tempo de build o HOME e /root, mas
# `shuru run` entrega o guest com HOME=/ — e o Claude Code le $HOME/.claude.json.
# Semear so um dos dois foi exatamente o erro cometido na primeira tentativa
# desta correcao, e o sintoma (tela de login de volta) nao aponta para a causa.
for h in / /root; do
  cat > "$h/.claude.json" <<JSON
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "$CLAUDE_VER",
  "theme": "dark",
  "autoUpdates": false
}
JSON
  chmod 600 "$h/.claude.json"
done
echo "    onboarding marcado para claude $CLAUDE_VER (HOME=/ e /root)"

echo "==> shuru-pr (commit -> PR -> squash-merge, de dentro da VM)"
# Fonte unica em dotfiles/scripts/shuru-pr.sh; aqui so o transporte. Sem
# extensao no destino porque o agente digita `shuru-pr`, nao `shuru-pr.sh`.
install -m 0755 /provision/shuru-pr.sh /usr/local/bin/shuru-pr
sh -n /usr/local/bin/shuru-pr || { echo "erro: shuru-pr nao passa no sh -n" >&2; exit 1; }

echo "==> canary tokens (item 5.7)"
# Chave AWS da Thinkst, valida-mas-neutralizada. Nao ha conta AWS real neste
# desenho, entao QUALQUER uso desta chave e exfiltracao — zero falso-positivo.
# O valor vem do Keychain do host em tempo de build (nunca versionado aqui).
for d in /root/.aws /.aws; do
  mkdir -p "$d"
  cp /provision/aws-canary-credentials "$d/credentials"
  chmod 600 "$d/credentials"
done
# Arquivo-isca com nome que varredura automatica procura.
cp /provision/aws-canary-credentials /root/.aws/credentials.backup
chmod 600 /root/.aws/credentials.backup

echo "==> limpeza"
apt-get clean
rm -rf /var/lib/apt/lists/* /root/.claude/downloads

echo
echo "=== imagem-base pronta ==="
node --version   | sed 's/^/node    /'
npm --version    | sed 's/^/npm     /'
pnpm --version   | sed 's/^/pnpm    /'
herdr --version  | sed 's/^/herdr   /'
claude --version | sed 's/^/claude  /'
gh --version | head -1 | sed 's/^/gh      /'
no-mistakes --version | sed 's/^/no-mist /'
echo "npm ignore-scripts: $(npm config get ignore-scripts)"
