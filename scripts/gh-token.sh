#!/bin/sh
# `gh` com o PAT do Mac, lido do keychain a cada invocacao.
#
# SUCESSOR do gh-broker.sh (removido em 18/ago/2026)
# O antecessor cunhava token de instalacao do GitHub App por comando: descobria
# o repo a partir de -R/--repo/path do `gh api`/remote origin, classificava o
# comando em leitura ou escrita para pedir o conjunto minimo de permissoes,
# mantinha cache de leitura de 45 min e cache negativo de 24 h, e falava com um
# agente launchd que segurava a chave privada em RAM. Tudo isso — umas 260
# linhas — existia por UMA razao: o token durava 1 h e cunha-lo custava um gesto
# humano. Com PAT de vida longa nao ha o que cachear nem o que classificar, e o
# arquivo inteiro colapsa nestas linhas.
#
# O QUE MUDA NA PRATICA, alem do conforto:
#  - Antes o token era por REPOSITORIO. `gh repo list` da conta inteira, `gh
#    search`, criar repo — nada disso funcionava, por definicao do token de
#    instalacao. Agora funciona, dentro do que o PAT alcancar.
#  - Antes um vazamento valia <= 45 min, so leitura, so um repo. Agora vale ate
#    voce revogar, com o escopo que o PAT tiver. Escolha o escopo no
#    github.com/settings/personal-access-tokens com isso em mente.
#  - Nao ha mais log de auditoria de cunhagem (~/.local/state/av-broker/
#    mints.jsonl nao recebe mais nada de github). Quem quiser saber o que o
#    token fez olha o proprio GitHub.
set -eu

die() { printf 'gh-token: %s\n' "$*" >&2; exit 1; }

PAT_HELPER="${GH_PAT_HELPER:-$HOME/Projects/dotfiles/scripts/gh-pat.sh}"

# --- onde esta o gh de verdade ----------------------------------------------
# Herdado inteiro do gh-broker.sh, e a razao continua valendo: o normal e o
# GH_REAL do home.sessionVariables apontando para o caminho exato do store. O
# fallback NAO pode ser `command -v gh` — este script E o `gh` do PATH, e a
# busca acharia ele mesmo, em laco infinito. A comparacao e por inode do alvo
# final (`stat -L`), nao por string, porque ~/.local/bin/gh e um symlink em dois
# saltos ate aqui e comparar caminho deixaria o laco passar.
REAL="${GH_REAL:-}"
if [ -z "$REAL" ]; then
  self=$(stat -L -f '%d:%i' "$0" 2>/dev/null || echo "?")
  IFS=:
  for d in $PATH; do
    unset IFS
    cand="$d/gh"
    [ -x "$cand" ] || continue
    [ "$(stat -L -f '%d:%i' "$cand" 2>/dev/null || echo "??")" = "$self" ] && continue
    REAL="$cand"
    break
  done
  unset IFS
fi

[ -n "$REAL" ] && [ -x "$REAL" ] || die "nao achei o gh real. Normalmente ele vem
  de GH_REAL (home.sessionVariables aponta para o gh do nixpkgs). Exporte GH_REAL
  com o caminho absoluto, ou garanta um gh no PATH que nao seja este wrapper."

# --- comandos que nao falam com a API ---------------------------------------
# Passam sem tocar no keychain. `gh --version` nao deve depender de haver token.
case "${1:-}" in
  --version|-v|--help|-h|help|version|completion|alias|config|extension|"")
    exec "$REAL" "$@" ;;
esac

# --- o que continua proibido ------------------------------------------------
# O bloqueio sobreviveu a troca, mas por outro motivo. Antes: `gh auth login`
# criaria um token pessoal de longo prazo, o anti-padrao que o arranjo evitava.
# Agora o token pessoal E o arranjo — o problema virou a SEGUNDA COPIA. O login
# grava `oauth_token` em texto puro em ~/.config/gh/hosts.yml, e a partir dai
# existem dois segredos vivos com o mesmo poder: um no keychain, que voce sabe
# rotacionar, e um em disco, que voce vai esquecer. Uma copia, um lugar.
case "${1:-} ${2:-}" in
  "auth login"|"auth refresh"|"auth logout"|"auth switch"|"auth setup-git")
    die "'$1 $2' e proibido nesta maquina. O PAT vive no keychain (item
  'github-pat') e este wrapper o injeta por ambiente a cada comando. Um login
  gravaria uma SEGUNDA copia do token em texto puro em ~/.config/gh/hosts.yml,
  que ninguem lembra de revogar.
  Para trocar o token:  scripts/gh-pat.sh set host
  Se um comando gh falhou, o problema provavelmente NAO e autenticacao: releia
  o erro dele." ;;
esac

tok=$("$PAT_HELPER" get host) || die "nao consegui ler o PAT do keychain (mensagem acima)."

# O token vai por ENV, nunca por argv: argv e legivel por qualquer processo do
# mesmo usuario via `ps`.
GH_TOKEN="$tok" GITHUB_TOKEN="$tok" exec "$REAL" "$@"
