# gcloud-admin — sessão administrativa efêmera do gcloud.
#
# ✅ Fiado no home.nix em 29/jul/2026 (`programs.zsh.initContent`), depois que a
# sessão das Fases 0/1 commitou os `.nix`. Vale a partir do próximo
# `darwin-rebuild switch`.
#
# Por que existe: `gcloud auth login` grava refresh token de USUÁRIO em texto
# plano em ~/.config/gcloud/, fora do TCC e fora do Automic Vault — é o mesmo
# anti-padrão do ~/Projects/.env que o item 0.2 do checklist eliminou. A
# credencial mais poderosa da máquina não pode ser a única sem gate.
#
# O desenho: a credencial existe só enquanto o subshell existe. Sair revoga —
# inclusive por Ctrl-C, inclusive se o subshell morrer com erro.

gcloud-admin() {
  emulate -L zsh
  if ! command -v gcloud >/dev/null; then
    print -u2 "gcloud-admin: gcloud não está instalado."
    return 1
  fi

  local _revoked=0
  _gcloud_admin_revoke() {
    (( _revoked )) && return
    _revoked=1
    print -u2 "\n▸ encerrando sessão administrativa…"
    gcloud auth revoke --all >/dev/null 2>&1
    if gcloud auth list 2>&1 | grep -q "No credentialed accounts"; then
      print -u2 "✅ gcloud sem conta ativa"
    else
      print -u2 "❌ ainda há conta ativa — rode: gcloud auth revoke --all"
    fi
  }
  # ERR/EXIT não bastam: a saída normal do subshell não os dispara.
  trap '_gcloud_admin_revoke' INT TERM

  gcloud auth login --brief || { _gcloud_admin_revoke; return 1; }

  print -u2 "\n┌──────────────────────────────────────────────────────────┐"
  print -u2 "│  SESSÃO ADMINISTRATIVA DO GCLOUD ABERTA                   │"
  print -u2 "│  'exit' encerra o subshell E revoga a credencial.         │"
  print -u2 "└──────────────────────────────────────────────────────────┘"

  # Subshell interativo: o prompt marcado deixa óbvio que a credencial está viva.
  GCLOUD_ADMIN_SESSION=1 ${SHELL:-/bin/zsh} -i

  _gcloud_admin_revoke
  trap - INT TERM
  unfunction _gcloud_admin_revoke
}
