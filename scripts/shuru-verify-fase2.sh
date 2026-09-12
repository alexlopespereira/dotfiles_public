#!/bin/sh
# Driver do GATE DA FASE 2 (docs/plano-adocao-tokens.md): validacao adversarial
# de egress. Roda os testes de dentro do guest e faz, do lado do host, a unica
# verificacao que de dentro seria impossivel.
#
# Este e o gate que decide se o shuru fica ou se cai o plano B (Apple container
# + Squid + pf). Ele bloqueia: sair com falha significa parar.
#
# Uso: scripts/shuru-verify-fase2.sh [checkpoint]   (default: base)
set -eu

CHECKPOINT="${1:-base}"
REPO_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SHURU="${SHURU:-$HOME/.local/bin/shuru}"
[ -x "$SHURU" ] || { echo "erro: shuru ausente — rode scripts/install-shuru.sh" >&2; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT INT TERM; cd "$WORK"
mkdir gate
cp "$REPO_DIR/shuru/gate-fase2.sh" "$REPO_DIR/shuru/probe.js" gate/

# Os IPs sao resolvidos AQUI, no host, e entregues prontos ao guest. Nao e
# conveniencia: o teste de "IP literal sem DNS" exige que o guest conheca um
# endereco que ele proprio nao conseguiria resolver. Resolver la dentro
# contaminaria o teste com o resultado do teste 3.
resolver() { dig +short "$1" A 2>/dev/null | grep -E '^[0-9]+\.' | head -1; }
{
  echo "IP_EXAMPLE=$(resolver example.com)"
  echo "IP_DOH=$(resolver cloudflare-dns.com)"
  echo "IP_GITHUB=$(resolver github.com)"
  echo "IP_ANTHROPIC=$(resolver api.anthropic.com)"
} > gate/ips.env
grep -q '=$' gate/ips.env && { echo "erro: falhou resolver um dos alvos no host" >&2; cat gate/ips.env >&2; exit 1; }
echo "Alvos resolvidos no host:"; sed 's/^/  /' gate/ips.env; echo

# ---------------------------------------------------------------------------
# Item 6 do research §4.4 adaptado. A pergunta original ("canal por processo do
# sistema no host") nao e testavel de dentro do guest; a pergunta equivalente e
# util e: o trafego do guest chega a aparecer numa interface do HOST? Se o shuru
# usasse vmnet, apareceria uma bridge100/vmenet aqui enquanto a VM roda — e ai o
# `pf` teria o que filtrar (item 7.3, segundo ramo). Se nao aparece, os pacotes
# do guest terminam dentro do processo do shuru e nunca transitam como trafego
# do guest no kernel do host: o `pf` nao teria onde agir.
echo "== host: interfaces antes de subir a VM"
ANTES=$(ifconfig -l)
echo "  $ANTES"

(
  # Segura a rede aberta por tempo suficiente para a medicao do host.
  "$SHURU" run --from "$CHECKPOINT" --disk-size 8192 --allow-net \
    --allow-host api.anthropic.com --mount ./gate:/gate \
    -- sh -c 'sleep 40' >/dev/null 2>&1 || true
) &
VMPID=$!
# Espera a interface do guest existir, sem cravar um sleep fixo: o boot varia.
i=0; while [ $i -lt 30 ] && ! ifconfig -l | grep -qvF "$ANTES"; do i=$((i+1)); sleep 1; done
DEPOIS=$(ifconfig -l)
echo "== host: interfaces com a VM no ar"
echo "  $DEPOIS"
# Diferenca em laco simples: substituicao de processo nao funciona no /bin/sh
# do macOS, e um arquivo temporario so para isto nao se justifica.
NOVAS=""
for i in $DEPOIS; do
  case " $ANTES " in *" $i "*) ;; *) NOVAS="$NOVAS $i" ;; esac
done
if printf '%s\n' $DEPOIS | grep -qE '^(bridge1[0-9]{2}|vmenet)'; then
  echo "  ⚠️  bridge NAT detectada — item 7.3 cai no SEGUNDO ramo (anchor de pf)."
  BRIDGE=sim
else
  echo "  ✅ nenhuma bridge/vmenet: rede em modo usuario, sem rota de kernel."
  echo "     Item 7.3 cai no PRIMEIRO ramo — pf nao tem onde agir."
  BRIDGE=nao
fi
[ -n "$NOVAS" ] && { echo "  interfaces novas: $NOVAS"; }
wait "$VMPID" 2>/dev/null || true

# ---------------------------------------------------------------------------
echo
echo "== guest: os testes adversariais"
# `allow-host` minimo de proposito: so api.anthropic.com. Toda a superficie que
# o gate tenta alcancar esta, portanto, fora da lista — inclusive github.com.
set +e
"$SHURU" run --from "$CHECKPOINT" --disk-size 8192 --allow-net \
  --allow-host api.anthropic.com \
  --mount ./gate:/gate \
  -- sh /gate/gate-fase2.sh
RC=$?
set -e

echo
echo "=========================================================="
case "$RC" in
  0) echo "GATE DA FASE 2: PASSOU (bridge NAT no host: $BRIDGE)" ;;
  3) echo "GATE DA FASE 2: INCONCLUSIVO — o controle positivo falhou."
     echo "A VM estava sem rede; nenhum 'bloqueado' acima vale como prova." ;;
  *) echo "GATE DA FASE 2: FALHOU — $RC caminho(s) de egress passou(aram)." ;;
esac
exit "$RC"
