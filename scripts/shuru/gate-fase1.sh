#!/bin/sh
# Verificacoes do gate da Fase 1 executadas DENTRO do guest.
# Chamado por scripts/shuru-verify-gate.sh — nao rode isto no host.
#
# Fica em arquivo proprio, montado na VM, e nao num heredoc para `sh -s`: o
# shuru nao encaminha o stdin do host para o comando do guest, entao `sh -s`
# fica esperando um script que nunca chega e a VM trava sem dizer por que.
set -u
fail=0

echo "== 1. env do guest: o valor tem que ser placeholder"
case "${CLAUDE_CODE_OAUTH_TOKEN:-}" in
  shuru_tok_*) echo "OK    CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN (placeholder)" ;;
  *)           echo "FALHA valor inesperado na env: ${CLAUDE_CODE_OAUTH_TOKEN:-<vazio>}"; fail=1 ;;
esac

echo
echo "== 2. env inteira: nenhum valor real"
if env | grep -q 'SENTINELA'; then
  echo "FALHA o valor real aparece na env do guest:"; env | grep SENTINELA; fail=1
else
  echo "OK    nenhuma variavel carrega o valor real"
fi

echo
echo "== 3. disco do guest: nenhum arquivo com o valor real"
# Direcionado, e nao `grep -r /`: varrer o rootfs de 8 GB passa de 20 min, e um
# gate que ninguem espera terminar nao e rodado. Estes sao os lugares onde uma
# credencial de fato aterrissa — home do agente, config, temporarios, logs e o
# mount do projeto. /usr e /lib sao a imagem-base, construida por voce.
hits=$(grep -rl 'SENTINELA' /root /home /etc /tmp /var/tmp /var/log /workspace 2>/dev/null | head -5)
if [ -n "$hits" ]; then echo "FALHA gravado em disco:"; echo "$hits"; fail=1
else echo "OK    varredura dos caminhos de credencial nao acha o valor real"; fi

echo
echo "== 4. ~/.claude do guest: sem credencial persistida"
# /login dentro da VM gravaria access+refresh aqui — proibido (ADR §6.4).
if [ -f "$HOME/.claude/.credentials.json" ] || [ -f /root/.claude/.credentials.json ]; then
  echo "FALHA existe .claude/.credentials.json — alguem rodou /login na VM"; fail=1
else
  echo "OK    sem .claude/.credentials.json"
fi

echo
echo "== 5. o DESTINO recebe o valor real no header Authorization"
got=$(curl -s -m 30 -H "Authorization: Bearer $CLAUDE_CODE_OAUTH_TOKEN" \
        https://postman-echo.com/get | tr ',' '\n' | grep -i '"authorization"')
case "$got" in
  *SENTINELA*)  echo "OK    proxy substituiu no header:$got" ;;
  *shuru_tok_*) echo "FALHA o placeholder saiu CRU para o destino"; fail=1 ;;
  *)            echo "FALHA resposta inesperada: ${got:-<vazio>}"; fail=1 ;;
esac

echo
echo "== 6. escopo: host FORA da lista de secrets so pode ver o placeholder"
# Sem isto, a lista de hosts do secret seria decorativa: bastaria um destino
# estar na allowlist de REDE para receber o valor real.
# Procura no corpo inteiro, sem assumir formato: cada servico de eco serializa os
# headers de um jeito (httpbingo poe o valor na linha seguinte a chave), e um
# grep por linha da "inconclusivo" quando na verdade daria para concluir.
#
# Tenta duas vezes e SEPARA "o eco nao respondeu" de "respondeu algo estranho".
# A versao anterior fundia os dois num "inconclusivo (eco fora do ar?)" que
# chutava a causa — e como httpbingo.org e servico de terceiro atras do fly.io,
# ele falha de vez em quando e o gate ficava dando aviso sem dizer de que.
# Verificado em 29/jul/2026 reproduzindo a requisicao a mao: o eco devolveu
# `"Bearer shuru_tok_..."` corretamente, ou seja, o aviso era do transporte.
body2=''; http2=''
for _ in 1 2; do
  body2=$(curl -s -m 30 -w '\n[HTTP %{http_code}]' \
            -H "Authorization: Bearer $CLAUDE_CODE_OAUTH_TOKEN" \
            https://httpbingo.org/headers 2>/dev/null) || true
  http2=${body2##*\[HTTP }; http2=${http2%%\]*}
  [ "$http2" = "200" ] && break
done
case "$body2" in
  *SENTINELA*)  echo "FALHA valor real vazou para host fora da lista de secrets"; fail=1 ;;
  *shuru_tok_*) echo "OK    host fora da lista recebeu so o placeholder" ;;
  *)
    if [ "$http2" = "200" ]; then
      # Respondeu, e o header nao tem nem o valor real nem o placeholder. Isso
      # nao e falha do isolamento, e o eco mudou de formato — mas o teste parou
      # de medir o que dizia medir, entao nao pode passar calado.
      echo "AVISO httpbingo respondeu 200 sem Authorization reconhecivel —"
      echo "      o formato do eco mudou; o teste 6 precisa ser reescrito."
    else
      echo "AVISO httpbingo indisponivel apos 2 tentativas (HTTP ${http2:-sem-resposta})."
      echo "      Escopo do secret NAO foi medido nesta rodada — reexecute."
    fi
    ;;
esac

echo
echo "== 7. Claude Code operante no guest"
claude --version >/dev/null 2>&1 && echo "OK    binario funcional" \
  || { echo "FALHA claude nao executa no guest"; fail=1; }

echo
echo "== 8. canary plantado (item 5.7)"
[ -f /root/.aws/credentials ] && echo "OK    isca em /root/.aws/credentials" \
  || { echo "FALHA canary ausente da imagem"; fail=1; }

echo
echo "== 9. onboarding pre-marcado: a TUI nao pode pedir /login"
# Isto e teste de SEGURANCA, nao de conforto. Sem estado de onboarding o Claude
# Code roda o first-run, cujo segundo passo e "Select login method" — a tela do
# /login que o ADR §6.4 proibe dentro da VM. Ou seja: a regressao apresenta ao
# usuario um convite para violar o desenho, e completa-lo gravaria access +
# refresh reais no guest (que e o que o teste 4 procura depois do estrago feito).
# Este teste pega a causa; o teste 4 so pegaria a consequencia.
# HOME=/ no guest (medido) — nao presuma /root aqui. O ${HOME%/} evita imprimir
# "//.claude.json", que parece defeito do teste e distrai de um FALHA real.
cfg="${HOME%/}/.claude.json"
if grep -q '"hasCompletedOnboarding" *: *true' "$cfg" 2>/dev/null; then
  echo "OK    $cfg marca onboarding concluido"
else
  echo "FALHA sem onboarding pre-marcado em $cfg —"
  echo "      a TUI vai abrir a tela de login. Reconstrua a imagem-base."
  fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "RESULTADO: PASSOU" || echo "RESULTADO: FALHOU"
exit "$fail"
