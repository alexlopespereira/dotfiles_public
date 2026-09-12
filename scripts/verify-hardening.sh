#!/bin/sh
# Verificação de hardening contínuo — Fase 4 de docs/plano-adocao-tokens.md,
# item de FASE 8 do checklist de reinstalação.
#
# Diferença para `verify-fase0.sh`: aquele é o gate de UMA fase, e responde
# "a fundação foi construída?". Este é periódico, e responde "ela continua de
# pé?". Coisas que passam num gate e apodrecem depois: canary substituído por
# credencial real, `shuru upgrade` rodado sem re-testar egress, `allow_net`
# ligado "só por um minuto", chave vencida.
#
# Uso: scripts/verify-hardening.sh [--rapido]
#   --rapido pula as checagens que sobem uma microVM (~1 min).
set -eu

RAPIDO=0
[ "${1:-}" = "--rapido" ] && RAPIDO=1
REPO="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
ok=0; alerta=0; falha=0
OK()     { echo "✅ $*"; ok=$((ok+1)); }
ALERTA() { echo "⚠️  $*"; alerta=$((alerta+1)); }
FALHA()  { echo "❌ $*"; falha=$((falha+1)); }

echo "=============== HARDENING CONTÍNUO ==============="
echo

# --------------------------------------------------------------- 1. fundação
echo "--- 1. fundação (delegado ao gate da Fase 0) ---"
# Exit 2 daquele script é "pendência de gesto humano", não regressão: só o 1
# (falha de verdade) conta aqui.
set +e
sh "$REPO/scripts/verify-fase0.sh" >/tmp/hardening-fase0.$$ 2>&1
rc=$?
set -e
grep -E '^(FALHA|PENDENTE)' /tmp/hardening-fase0.$$ | sed 's/^/   /' || true
case "$rc" in
  0) OK "gate da Fase 0 íntegro" ;;
  2) OK "gate da Fase 0 sem regressão (há pendências humanas, esperadas)" ;;
  *) FALHA "gate da Fase 0 REGREDIU — veja /tmp/hardening-fase0.$$" ;;
esac
rm -f /tmp/hardening-fase0.$$

# --------------------------------------------------------------- 2. rotação
echo
echo "--- 2. idade das credenciais ---"
if command -v av-broker >/dev/null 2>&1; then
  set +e; av-broker rotate | sed -n '3,10p' | sed 's/^/  /'; rot=$?; set -e
  [ "$rot" -eq 0 ] && OK "nenhuma credencial vencida" \
    || ALERTA "há credencial vencida — av-broker rotate --target <alvo>"
else
  ALERTA "av-broker fora do PATH: idade das credenciais não verificada"
fi

# --------------------------------------------------------------- 3. canaries
echo
echo "--- 3. canaries ainda armados ---"
# "Vivo" aqui não é só existir: é o arquivo-isca ainda conter a chave FALSA.
# O modo de falha real não é alguém apagar a isca — é alguém usar AWS de verdade
# e sobrescrever o [default] com credencial legítima. Aí a isca some sem avisar,
# e a detecção de exfiltração que se acredita ter deixa de existir.
CANARY_ID=$(security find-generic-password -s canary-host-aws -w 2>/dev/null \
            | jq -r '.aws_access_key_id // empty' 2>/dev/null || true)
if [ -z "$CANARY_ID" ]; then
  FALHA "canary-host-aws ausente do Keychain"
elif [ ! -f "$HOME/.aws/credentials" ]; then
  FALHA "isca ~/.aws/credentials sumiu — a detecção de exfiltração no host morreu"
elif grep -q "$CANARY_ID" "$HOME/.aws/credentials" 2>/dev/null; then
  OK "isca do host bate com o canary do Keychain"
else
  FALHA "~/.aws/credentials NÃO contém mais o canary — alguém pôs credencial real ali?
   A isca precisa voltar; use perfil nomeado para AWS de verdade (runbook §3)."
fi
security find-generic-password -s canary-vm-aws >/dev/null 2>&1 \
  && OK "canary da imagem-base custodiado" \
  || FALHA "canary-vm-aws ausente — a imagem-base não pode ser reconstruída armada"

# ------------------------------------------------------------ 4. pin do shuru
echo
echo "--- 4. runtime pinado ---"
PIN=$(grep -m1 '^VERSION=' "$REPO/scripts/install-shuru.sh" | cut -d'"' -f2)
ATUAL=$($HOME/.local/bin/shuru --version 2>/dev/null | awk '{print $2}')
if [ -z "$ATUAL" ]; then
  ALERTA "shuru não instalado"
elif [ "$ATUAL" = "$PIN" ]; then
  OK "shuru $ATUAL = pin do instalador"
else
  # Não é preciosismo: o gate de egress da Fase 2 vale para UMA versão. Subir
  # sem re-rodar os 12 testes é confiar num resultado que ninguém mediu.
  FALHA "shuru $ATUAL ≠ pin $PIN — alguém rodou 'shuru upgrade'.
   Re-rode scripts/shuru-verify-fase2.sh ANTES de voltar a usar rede na VM."
fi

# --------------------------------------------------------- 5. egress conforme
echo
echo "--- 5. egress conforme a decisão da Fase 2 ---"
# A decisão foi: sem pf, porque o shuru faz rede em modo usuário. O que pode
# apodrecer é o default do projeto — allow_net ligado, ou github.com entrando
# na allowlist (quem fala com o GitHub é o broker, no host).
if [ -f "$REPO/shuru.json" ]; then
  jq -e '.allow_net == false' "$REPO/shuru.json" >/dev/null 2>&1 \
    && OK "shuru.json continua offline-by-default" \
    || FALHA "shuru.json com allow_net habilitado por default"
  jq -e '[.network.allow[]] | index("github.com")' "$REPO/shuru.json" >/dev/null 2>&1 \
    && FALHA "github.com entrou na allowlist da VM — rede para o GitHub é decisão
       daquela sessão (--allow-host), nunca default do arquivo" \
    || OK "github.com fora da allowlist da VM"
else
  ALERTA "shuru.json ausente na raiz do repo"
fi
# pf NÃO deve estar configurado para isto (item 7.3): a ausência é a decisão.
if sudo -n pfctl -a egress -s rules 2>/dev/null | grep -q .; then
  ALERTA "existe anchor pf 'egress' — a Fase 2 decidiu não usar pf.
   Se o shuru passou a criar bridge NAT, reabra o item 7.3; se não, remova."
else
  OK "sem anchor pf (coerente com a decisão do item 7.3)"
fi

# ------------------------------------------- 6. credencial de nuvem em disco
echo
echo "--- 6. nenhuma credencial de longa vida em disco ---"
[ -f "$HOME/.config/gcloud/application_default_credentials.json" ] \
  && FALHA "ADC do gcloud presente — nunca rode 'gcloud auth application-default login' (checklist 6.6)" \
  || OK "sem ADC do gcloud"
if [ -f "$HOME/.config/gcloud/credentials.db" ]; then
  n=$(sqlite3 "$HOME/.config/gcloud/credentials.db" 'select count(*) from credentials;' 2>/dev/null || echo 0)
  [ "${n:-0}" -eq 0 ] && OK "gcloud sem conta persistida" \
    || ALERTA "$n conta(s) gcloud persistida(s) — sessão admin não foi revogada? (gcloud-admin)"
else
  OK "gcloud sem credentials.db"
fi

# ------------------------------------------------------ 7. higiene da imagem
echo
echo "--- 7. higiene da imagem-base ---"
if [ "$RAPIDO" -eq 1 ]; then
  echo "   (pulado por --rapido)"
elif [ ! -x "$HOME/.local/bin/shuru" ]; then
  ALERTA "shuru ausente — imagem não verificada"
else
  # Sobe a VM offline: nada aqui precisa de rede, e o default é o default.
  W=$(mktemp -d); mkdir "$W/g"
  cat > "$W/g/check.sh" <<'GUEST'
grep -q 'ignore-scripts=true' /etc/npmrc && echo "OK ignore-scripts" || echo "FALHA ignore-scripts"
grep -q 'minimum-release-age' /etc/npmrc && echo "OK cooldown" || echo "FALHA cooldown"
[ -f /root/.aws/credentials ] && echo "OK canary" || echo "FALHA canary"
pnpm --version >/dev/null 2>&1 && echo "OK pnpm" || echo "FALHA pnpm"
GUEST
  (cd "$W" && "$HOME/.local/bin/shuru" run --from base --disk-size 8192 \
     --mount ./g:/g -- sh /g/check.sh 2>/dev/null) > "$W/out" || true
  if grep -q OK "$W/out" 2>/dev/null; then
    while read -r linha; do
      case "$linha" in
        OK*)    OK "imagem: ${linha#OK }" ;;
        FALHA*) FALHA "imagem: ${linha#FALHA }" ;;
      esac
    done < "$W/out"
  else
    ALERTA "não deu para inspecionar a imagem-base (checkpoint 'base' existe?)"
  fi
  rm -rf "$W"
fi

echo
echo "================================================="
echo "$ok ok · $alerta alerta(s) · $falha falha(s)"
[ "$falha" -eq 0 ] || { echo "Hardening REGREDIU — trate as falhas acima."; exit 1; }
[ "$alerta" -eq 0 ] || { echo "Sem regressão; há alertas para olhar."; exit 0; }
echo "Hardening íntegro."
