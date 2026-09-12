#!/bin/sh
# Leitor (e gravador) dos PATs do GitHub no login keychain.
#
# POR QUE ISTO EXISTE (decisao de 18/ago/2026)
# Ate hoje esta maquina nao tinha token pessoal do GitHub: todo acesso vinha de
# token de instalacao do GitHub App, TTL de 1 h, cunhado sob demanda pelo
# av-broker. O capitao encerrou esse arranjo por custo humano — a cunhagem
# cobrava um gesto (dialogo do macOS, e a palavra do desafio na escrita) e o
# token morria em 1 h, o que obrigava um pipeline de duas etapas nas VMs. A
# troca foi explicita e o preco esta aceito: DOIS PATs fine-grained de vida
# longa no lugar de credencial efemera.
#
# SAO DOIS, e nao um, de proposito. Um token por lugar e a unica forma de saber
# QUAL copia vazou e de revogar so ela:
#   github-pat      -> vive aqui no Mac, usado pelo gh-token.sh (o `gh` do PATH)
#   github-pat-vm   -> viaja para dentro do guest do shuru, onde qualquer codigo
#                      que rode na VM consegue le-lo. E o de MENOR privilegio.
#
# O QUE SE PERDEU, escrito aqui para nao ser redescoberto como surpresa:
#  - O item fica no LOGIN keychain com ACL normal, entao qualquer processo seu
#    le sem dialogo enquanto o chaveiro estiver destrancado. Nao adianta criar
#    com `-T ""`: a Automic Vault destranca o chaveiro e isso anula a ACL
#    (medido, ver a memoria keychain-lock-nao-acl). Colocar `-T ""` aqui daria
#    a aparencia de portao sem o portao — pior que nao ter.
#  - Escopo e prazo agora sao responsabilidade sua no github.com/settings, nao
#    de codigo. O `av-broker rotate --target github` nao existe mais.
set -eu

SERVICE_HOST="github-pat"
SERVICE_VM="github-pat-vm"

die() { printf 'gh-pat: %s\n' "$*" >&2; exit 1; }

service_for() {
  case "$1" in
    host|mac) printf '%s' "$SERVICE_HOST" ;;
    vm|guest|container) printf '%s' "$SERVICE_VM" ;;
    *) die "alvo desconhecido: '$1'. Use 'host' ou 'vm'." ;;
  esac
}

usage() {
  cat >&2 <<'EOF'
uso:
  gh-pat.sh get <host|vm>     imprime o PAT no stdout
  gh-pat.sh set <host|vm>     le o PAT do stdin (sem eco) e grava no keychain
  gh-pat.sh check             diz quais dos dois existem, sem imprimir valor

Para gravar sem deixar o token no historico do shell, NAO passe por argumento:
  gh-pat.sh set host    <- e entao cole o token e Enter
EOF
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  get)
    [ $# -eq 2 ] || usage
    svc=$(service_for "$2")
    # -w imprime SO a senha. O stderr do security vai para o nosso stderr de
    # proposito: quando o item nao existe a mensagem dele e mais util que a
    # nossa.
    tok=$(security find-generic-password -s "$svc" -w 2>/dev/null) || die "nao achei o item '$svc' no keychain.
  Grave com: gh-pat.sh set ${2}
  Crie o token em https://github.com/settings/personal-access-tokens"
    [ -n "$tok" ] || die "o item '$svc' existe mas esta vazio."
    printf '%s\n' "$tok"
    ;;

  set)
    [ $# -eq 2 ] || usage
    svc=$(service_for "$2")
    # `stty -echo` em vez de `read -s`: isto e /bin/sh, e `read -s` e bashism.
    #
    # Condicionado a `[ -t 0 ]` porque sem terminal o `stty` falha e, com
    # `set -e`, MATA o script — o que transformava um `echo tok | gh-pat set host`
    # num erro obscuro de tty em vez de gravar. O caminho por pipe existe para
    # automacao e para o teste; o eco desligado so faz sentido quando ha tela.
    if [ -t 0 ]; then
      printf 'cole o PAT para %s (nao aparece na tela): ' "$svc" >&2
      old_stty=$(stty -g)
      stty -echo
      IFS= read -r tok || true
      stty "$old_stty"
      printf '\n' >&2
    else
      IFS= read -r tok || true
    fi
    [ -n "$tok" ] || die "nada foi colado; nao gravei."
    case "$tok" in
      github_pat_*|ghp_*) ;;
      *) die "isso nao parece um PAT (esperado prefixo github_pat_ ou ghp_). Nao gravei." ;;
    esac
    # -U atualiza se ja existir, em vez de falhar com "item already exists".
    # -w com o valor em argv seria legivel por `ps`; o security nao le a senha do
    # stdin, entao usamos -w SEM valor, que faz o proprio security prompta-la...
    # o que quebraria o pipe. Solucao: passamos por argv mas so por microssegundos
    # e num processo cujo argv o `ps` de outro usuario nao ve (mesmo uid ve).
    # E o mesmo compromisso que o `security` impoe a todo mundo; anotado para
    # ninguem achar que passou despercebido.
    security add-generic-password -U -a "$USER" -s "$svc" -w "$tok" \
      || die "o security recusou a gravacao."
    printf 'gravado em %s (login keychain).\n' "$svc" >&2
    ;;

  check)
    for pair in "host $SERVICE_HOST" "vm $SERVICE_VM"; do
      set -- $pair
      if security find-generic-password -s "$2" >/dev/null 2>&1; then
        printf '  %-5s %-14s presente\n' "$1" "$2"
      else
        printf '  %-5s %-14s AUSENTE  (gh-pat.sh set %s)\n' "$1" "$2" "$1"
      fi
    done
    ;;

  ""|-h|--help|help) usage ;;
  *) die "comando desconhecido: '$cmd'" ;;
esac
