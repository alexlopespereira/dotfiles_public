# claude-kit — os scripts do dia um do ambiente pos-firstmate.
#
# Chamado de home.nix como `import ./nix/claude-kit.nix { inherit pkgs; }`, no
# mesmo formato de nix/no-mistakes.nix. Devolve uma LISTA de derivacoes pronta
# para concatenar em home.packages.
#
# Os caminhos abaixo sao `../scripts/claude-kit/...` porque path relativo em nix
# resolve contra o ARQUIVO que o escreve, e este mora em nix/. O rascunho de
# origem tinha `./scripts/...` porque la os dois diretorios eram irmaos; no repo
# eles nao sao. Errar isto nao da erro de avaliacao obvio — da "path does not
# exist" na hora do build, que e facil de ler como problema do script.
#
# ── Por que writeShellApplication e nao mkOutOfStoreSymlink ──────────────────
#
# home.nix ja usa os dois idiomas, e a escolha aqui nao e de gosto:
#
#   mkOutOfStoreSymlink  (claude-shuru, gh, gh-pat, av-broker, statusline)
#     → edita e ja vale, sem rebuild. Nenhuma dependencia pinnada, nenhum
#       shellcheck. Bom para script que muda toda semana.
#   writeShellApplication  (este arquivo)
#     → imutavel no store, dependencias pinnadas em runtimeInputs, shellcheck
#       roda no BUILD e reprova o rebuild inteiro.
#
# Os quatro `checkout-*` rodam `git reset --hard`, `git clean -fd` e
# `git branch -d`. Sao a superficie que destroi trabalho. Nesses o custo de
# precisar de um rebuild para editar e o preco de (a) o mesmo `git` nas duas
# maquinas — nao "o do Homebrew aqui, o do sistema la" — e (b) um shellcheck
# que barra o commit antes de o script rodar num pool de verdade.
#
# `claude-yolo` entra pelo mesmo motivo com uma volta a mais: ele liga
# --dangerously-skip-permissions. Um script de tres linhas que desliga TODOS os
# prompts de permissao e exatamente o que nao pode divergir entre maquinas.
#
# `interrupcoes-report.sh` NAO esta aqui de proposito. Ver o comentario no fim
# do arquivo e o bloco correspondente em home.nix.
#
# ── PATH: writeShellApplication PREPENDA, nao substitui ──────────────────────
#
# O wrapper gerado emite `export PATH="<runtimeInputs>:$PATH"`. Com
# runtimeInputs = [] ele emite `export PATH="$PATH"`. Em nenhum caso o PATH do
# usuario e descartado — verificado lendo o texto da derivacao construida em
# 27/ago/2026. E por isso que `claude-yolo` acha o `claude` do Homebrew cask
# mesmo sem nenhum runtimeInput.
#
# ── Por que `claude` NAO e pinnado em runtimeInputs ──────────────────────────
#
# O CLI vem do cask claude-code@latest e se auto-atualiza (2.1.236 hoje). Pinar
# uma segunda copia pelo nixpkgs criaria duas versoes brigando: o cask atualiza,
# o nix nao, e `claude-yolo` passaria a abrir uma versao diferente da que ele
# abre digitando `claude`. Resolucao ambiente e a escolha certa aqui.
{ pkgs }:

let
  inherit (pkgs) writeShellApplication;

  # Dependencias comuns dos checkout-*. `coreutils` cobre basename/head/date/
  # wc/tr/sort/cut/seq; `gnused` e `gnugrep` evitam o BSD sed/grep do macOS, que
  # e onde mora a diferenca de comportamento entre esta maquina e qualquer outra.
  checkoutDeps = with pkgs; [ git coreutils gnused gnugrep findutils gawk ];

  mk = name: file: extra: shellchecksToSkip:
    writeShellApplication {
      inherit name;
      runtimeInputs = checkoutDeps ++ extra;
      excludeShellChecks = shellchecksToSkip;
      text = builtins.readFile file;
    };

  # Nomeado no let (e nao inline na lista) porque o checkout-sync precisa dele em
  # runtimeInputs — ver o comentario la embaixo.
  checkout-sync-all =
    mk "checkout-sync-all" ../scripts/claude-kit/checkout-sync-all.sh [ ] [ ];

  # ── O pipeline de entrega: commit-push-pr → force-merge → ship ─────────────
  #
  # Os tres se CHAMAM entre si, e e por isso que moram no let em vez de inline na
  # lista: o de cima precisa do de baixo como runtimeInput. A ordem aqui e a
  # ordem da dependencia, nao alfabetica — nix e lazy e aceitaria qualquer ordem,
  # mas quem le precisa ver o grafo.
  #
  # No dotclaude os tres se achavam por SCRIPT_DIR (o bin/ compartilhado). No
  # store cada um e uma derivacao isolada e nao existe irmao ao lado, entao a
  # copia em scripts/claude-kit/ resolve por `command -v` e o pin vem daqui. Sem
  # esse pin o `ship` chamaria o que estivesse no PATH do usuario — ou nada.

  # commit-push-pr.sh — commita na main local, cria branch efemera derivada da
  # mensagem, pusha, abre PR e liga auto-merge --squash. Reseta a main local para
  # origin/main no fim (o slot volta limpo). Nao chama nenhum irmao: e a folha.
  #
  # SC2001: as tres ocorrencias sao `sed 's/^/    /'` para indentar uma saida de
  # varias linhas. O shellcheck sugere ${var//busca/troca}, que aqui NAO serve —
  # a substituicao de parametro do bash nao tem ancora `^` por linha, entao ela
  # indentaria so a primeira. A sugestao esta errada para este caso.
  commit-push-pr =
    mk "commit-push-pr" ../scripts/claude-kit/commit-push-pr.sh [ pkgs.gh pkgs.jq ] [ "SC2001" ];

  # force-merge.sh — mergea um PR aberto AGORA (soft / --wait / --admin) e
  # sincroniza o pool depois. A confirmacao humana NAO esta no script: ele exige
  # FORCE_MERGE_CONFIRMED=1, porque `read -r -p` nao recebe stdin quando o Claude
  # Code invoca via Bash tool. Rodar no terminal sem a env var falha cedo, com
  # instrucao — que e o comportamento seguro para um script com modo --admin.
  #
  # SC2015 (`A && B || C nao e if-then-else`): a ocorrencia e um
  # `$([ ADMIN ] && echo "ADMIN" || ([ WAIT ] && echo "WAIT" || echo "SOFT"))`
  # dentro do texto que descreve o modo na tela de confirmacao. O alerta existe
  # porque C roda quando B falha — mas B aqui e `echo` numa string literal, que
  # nao falha. Sem armadilha, e reescrever com if/else quebraria a interpolacao.
  force-merge =
    mk "force-merge" ../scripts/claude-kit/force-merge.sh [ pkgs.gh pkgs.jq checkout-sync ] [ "SC2015" ];

  # ship.sh — o pipeline inteiro: pre-checks → testes pre-merge → commit+push+PR
  # → auto-merge (ou force-merge soft em branch nao-protegida) → deploy → e2e.
  # Le `.claude/ship.json` do REPO, nao daqui: config e por projeto, entao nao ha
  # nada a empacotar junto. Os exit codes (10 pre-merge, 20 e2e, 30 protegida,
  # 99 race) sao contrato com o slash command, que e quem faz retry.
  #
  # SC2015: `[ -z "$MSG" ] && MSG="$1" || { erro }` no parser de argumentos.
  # Mesmo caso do force-merge — o B do meio e uma ATRIBUICAO, que sempre retorna
  # 0, entao o ramo de erro so roda quando MSG ja estava preenchido, que e a
  # intencao. Reescrever daria um if/else de quatro linhas sem ganho.
  ship =
    mk "ship" ../scripts/claude-kit/ship.sh
      [ pkgs.gh pkgs.jq commit-push-pr force-merge checkout-sync ] [ "SC2015" ];

  # checkout-sync.sh — atalho que infere o pool a partir do cwd e delega ao
  # checkout-sync-all. Sem argumento nenhum, de dentro de um slot, e o caminho
  # curto do pos-merge. Nomeado porque force-merge e ship dependem dele.
  checkout-sync =
    mk "checkout-sync" ../scripts/claude-kit/checkout-sync.sh [ checkout-sync-all ] [ ];
in
[
  # checkout-init.sh — provisiona ~/Projects/checkouts/<repo>-{1..N}.
  # gh: le o repo default / clona por URL. jq: le a resposta do gh.
  (mk "checkout-init" ../scripts/claude-kit/checkout-init.sh [ pkgs.gh pkgs.jq ] [ ])

  # checkout-use.sh — aloca um slot JA existente: exige main limpa, faz
  # fetch + pull --ff-only e grava .claude/.slot-info com o label. NAO cria
  # branch e NAO escolhe o slot por voce — o numero vem por argumento
  # (`checkout-use <repo> <slot> [label]`) e a saida e um resumo legivel, nao um
  # caminho para `cd $(...)`.
  (mk "checkout-use" ../scripts/claude-kit/checkout-use.sh [ ] [ ])

  # checkout-status.sh — panorama dos slots.
  # SC2016: o script imprime literalmente uma linha com $(...) dentro de aspas
  # simples, para o usuario copiar. E intencional, nao uma expansao esquecida.
  (mk "checkout-status" ../scripts/claude-kit/checkout-status.sh [ ] [ "SC2016" ])

  # checkout-sync-all.sh — sincroniza todos os slots com origin/main e poda
  # branches ja mergeadas.
  #
  # ATENCAO ao lift: a copia em scripts/claude-kit/ ja esta com o graphify
  # REMOVIDO. O original do dotclaude fazia, na linha 12,
  #   SYNC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
  #   . "$SYNC_LIB_DIR/graphify_version.sh"
  # e isso NAO funciona no store: BASH_SOURCE aponta para
  # /nix/store/...-checkout-sync-all/bin/checkout-sync-all e nao existe `lib/`
  # ao lado. O script morreria com `set -e` na primeira linha util. Como o
  # horizons ja removeu o graphify (PR 343), a saida foi tirar os tres blocos
  # inteiros em vez de empacotar a lib junto — some tambem a dependencia de
  # uv/pip/graphify.
  checkout-sync-all

  # checkout-launch.sh — abre 1 janela com N abas, uma por slot, opcionalmente
  # ja rodando `claude` em cada uma. E o script que faz o pool valer a pena: sem
  # ele o workflow paralelo vira cinco `cd` na mao.
  #
  # runtimeInputs NAO ganha nada de `osascript` nem de `defaults`: os dois sao
  # binarios de sistema do macOS (/usr/bin), nao tem pacote no nixpkgs, e o
  # wrapper PREPENDA ao PATH em vez de substituir (ver o bloco sobre PATH acima),
  # entao continuam resolvendo. Consequencia aceita: este e o unico script do kit
  # que so funciona no macOS.
  #
  # SC2016: o heredoc do AppleScript passa `$esc` ja expandido pelo bash, mas o
  # corpo carrega aspas simples com `$` literal que o shellcheck le como expansao
  # esquecida.
  (mk "checkout-launch" ../scripts/claude-kit/checkout-launch.sh [ ] [ "SC2016" ])

  checkout-sync

  # Pipeline de entrega. Definidos e comentados no let acima, onde o grafo de
  # dependencia entre eles fica visivel.
  commit-push-pr
  force-merge
  ship

  # claude-yolo — `claude --dangerously-skip-permissions "$@"`.
  # runtimeInputs vazio de proposito: ver o bloco sobre PATH acima.
  (writeShellApplication {
    name = "claude-yolo";
    runtimeInputs = [ ];
    text = builtins.readFile ../scripts/claude-kit/claude-yolo;
  })
]

# ── interrupcoes-report.sh: por que fica de fora desta lista ─────────────────
#
# Duas razoes concretas, nao estetica.
#
# 1. Ele se auto-envia por ssh. A linha 291 do original e
#      remote_json="$("$SSH_BIN" ... "$dest" bash -s -- --emit-json ... < "$0")"
#    ou seja, pipa o ARQUIVO EM "$0" para o bash da outra maquina. Sob
#    writeShellApplication, "$0" e o wrapper do store, cujo corpo comeca com
#    `export PATH="/nix/store/...:$PATH"`. Isso e mandado para uma maquina que
#    nao tem /nix/store. Nao quebra — diretorio inexistente no PATH e ignorado
#    na busca — mas manda um prelude nix para um host estrangeiro, e o efeito
#    disso e mais dificil de prever do que o beneficio de pinar coreutils num
#    relatorio.
#
# 2. E a ferramenta de MEDICAO, e a medicao vai ser mexida. Toda categoria nova
#    de interrupcao e uma regex a mais no bloco python inline. Exigir rebuild
#    para cada ajuste e o caminho garantido para ele parar de ajustar.
#
# Por isso ele vai por mkOutOfStoreSymlink em ~/.local/bin/, junto de
# claude-shuru/gh/gh-pat/av-broker, que e exatamente o idioma que home.nix ja usa
# para "script meu, editado direto, sem rebuild". Ver home.nix.fragment.nix.
