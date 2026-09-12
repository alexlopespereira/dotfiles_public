#!/bin/sh
# Gate da Fase 0 (docs/plano-adocao-tokens.md):
# "App criado com o teto minimo e chave no Keychain; setup-token custodiado;
#  nenhum PEM/token em disco."
#
# Cobre o que e da FASE, nao o que e do broker: a saude interna do av-broker
# (portao, sessoes, config) e `av-broker doctor`, e este script chama aquele em
# vez de reimplementar. O que existe so aqui: canaries, setup-token e a
# varredura de segredo em disco.
#
# Reporta PENDENTE (nao FALHA) para o que depende de um gesto seu — a diferenca
# importa: um item pendente nao e uma regressao.
set -eu

ok=0; pend=0; fail=0
OK()   { echo "OK       $*"; ok=$((ok+1)); }
PEND() { echo "PENDENTE $*"; pend=$((pend+1)); }
FAIL() { echo "FALHA    $*"; fail=$((fail+1)); }

echo "=== Fase 0 — fundacoes ==="
echo

# 1. PATs do GitHub. Ate 18/ago/2026 este bloco verificava o GitHub App: app_id
# numerico e plausivel, chave no Keychain, e um `--dry-run` que confirmava contra
# a API que o JWT assinava com a chave daquele App. Nada disso existe mais — o
# alvo `github` saiu do broker e o acesso passou a ser por PAT fine-grained de
# vida longa. O que da para verificar agora e presenca, e so: se o item esta no
# chaveiro. Validade e escopo do PAT so o GitHub sabe, e o unico jeito de
# descobrir e usa-lo.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/av-broker/config.json"
for alvo in host vm; do
  case "$alvo" in host) svc=github-pat ;; vm) svc=github-pat-vm ;; esac
  security find-generic-password -s "$svc" >/dev/null 2>&1 \
    && OK "PAT do GitHub presente no Keychain ('$svc')" \
    || PEND "PAT '$svc' ausente — grave com 'gh-pat set $alvo'
         (crie em https://github.com/settings/personal-access-tokens)"
done

# O config do broker segue necessario — nao para o GitHub, que saiu, mas para
# gcp e salesforce, que continuam com credencial efemera e portao.
if [ -f "$CONFIG" ]; then
  OK "config do broker presente ($CONFIG)"
else
  FAIL "config do broker ausente: $CONFIG (ver broker/README.md)"
fi

# 2. setup-token custodiado
security find-generic-password -s claude-setup-token >/dev/null 2>&1 \
  && OK "claude setup-token no Keychain" \
  || PEND "setup-token nao custodiado — ver runbook §2"

# 2b. Agente de aprovacao do Automic Vault.
#
# Este agente e registrado so no primeiro launch do app — instalar o cask nao
# basta, e o cleanup = "zap" pode derruba-lo num rebuild. Sem ele o `av save`
# trava sem imprimir um byte.
#
# O `gh` NAO esta mais nesta lista: ele saiu do Automic Vault em 02/ago/2026
# (Secret Gate cobrando 582 dialogos em 24 h, e o Claude Code inelegivel por
# assinatura), e desde 18/ago/2026 le um PAT direto do login keychain. O
# sintoma classico que este check existia para nomear — `gh auth status` dizendo
# "The token in  is invalid" e mandando re-autenticar — nao pode mais vir daqui.
# Medido em
# 29/jul/2026 — o app tinha sido instalado as 22:18 e nunca aberto; este check
# existe para que isso apareca como FALHA nomeada aqui, e nao como "token
# expirou" tres dias depois. Detalhe: docs/reinstall-checklist.md item 3.4.
#
# launchctl basta: com o agente registrado (RunAtLoad + MachServices), o launchd
# sobe o app por demanda — nao exigimos processo vivo, so o registro.
if launchctl list 2>/dev/null | grep -q "com.automicvault"; then
  OK "agente de aprovacao do Automic Vault registrado no launchd"
else
  FAIL "agente do Automic Vault ausente do launchd — rode: open -a 'Automic Vault'
         (sem ele o gh mente 'token invalid' e o av save trava mudo — item 3.4)"
fi

# 3. Canary tokens
for s in canary-host-aws canary-vm-aws; do
  security find-generic-password -s "$s" >/dev/null 2>&1 \
    && OK "canary '$s' no Keychain" \
    || FAIL "canary '$s' ausente (runbook §3)"
done
[ -f "$HOME/.aws/credentials" ] \
  && OK "isca plantada no host (~/.aws/credentials)" \
  || FAIL "isca do host ausente"

# 4. O gate propriamente dito: nada de PEM/token em disco.
# ~/Library e ~/.Trash ficam de fora: o primeiro tem PEM legitimo (trust stores,
# certificados de sistema) e o segundo nao e local de uso.
echo
echo "--- varredura: segredo em disco ---"
# `|| true` nos dois: find sai 1 ao esbarrar em diretorio protegido pelo TCC (o
# que e a protecao funcionando, checklist 6.1) e grep sai 1 quando nao acha
# nada — que aqui e justamente o resultado bom.
pems=$(find "$HOME" -maxdepth 4 -name '*.pem' \
         -not -path "$HOME/Library/*" -not -path "$HOME/.Trash/*" \
         -not -path "*/node_modules/*" 2>/dev/null || true)
[ -z "$pems" ] && OK "nenhum .pem em ~ (ate 4 niveis)" \
  || { FAIL "PEM em disco:"; printf '%s\n' "$pems" | sed 's/^/         /'; }

# O {80,} nao e frescura: sem o piso de comprimento, "sk-ant-oat01-..." escrito
# em prosa nesta propria arvore (docs, research, o gate da Fase 1) marca falha e
# o check vira ruido que se aprende a ignorar — o modo de falha do Problema 4 do
# research. Token de verdade passa dos 100 caracteres; exemplo em texto, nao.
leaks=$(grep -rlE 'sk-ant-oat[0-9]{2}-[A-Za-z0-9_-]{80,}|-----BEGIN (RSA )?PRIVATE KEY-----' \
          "$HOME/.zshrc" "$HOME/.zsh_history" "$HOME/Projects" 2>/dev/null \
        | grep -v '/vendor/' | head -5 || true)
[ -z "$leaks" ] && OK "nenhum token/chave em ~/.zshrc, historico ou ~/Projects" \
  || { FAIL "segredo em texto:"; printf '%s\n' "$leaks" | sed 's/^/         /'; }

# 5. Saude do broker — delegada, nao reimplementada.
#
# `--deep` de proposito: o doctor comum checa so a PRESENCA das chaves, porque
# ler o valor custa um dialogo de autorizacao por chave e ele roda a toda hora.
# Este gate roda raramente e por decisao sua, entao e aqui que a leitura vale a
# pena — e e aqui que fica valendo a licao de 29/jul/2026, quando o doctor jurava
# que estava tudo bem com a chave do GitHub truncada em 128 bytes no Keychain.
# Um gate que so confirma que o ponteiro existe nao teria pegado aquilo.
#
# Espere UM dialogo por chave custodiada. Responda "Permitir", nunca "Sempre
# Permitir" — "Sempre" reintroduz exatamente a ACL frouxa que este repo acabou
# de consertar (ver "Estado" em broker/README.md).
echo
echo "--- av-broker doctor --deep ---"
if command -v av-broker >/dev/null 2>&1; then
  av-broker doctor --deep 2>&1 | sed 's/^/  /' || true
else
  echo "  av-broker nao esta no PATH (ver broker/README.md, secao Instalacao)"
fi

echo
echo "=== $ok ok, $pend pendente(s), $fail falha(s) ==="
[ "$fail" -eq 0 ] || exit 1
[ "$pend" -eq 0 ] || { echo "Gate INCOMPLETO: os pendentes exigem um gesto seu."; exit 2; }
echo "Gate da Fase 0: PASSOU."
