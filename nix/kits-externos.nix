# kits-externos — os kits de TERCEIROS que ficam globais em toda sessao do
# Claude Code: ralph (snarktank), backpass (kunchenguid) e cinco skills de
# engenharia do mattpocock/skills.
#
# Chamado de home.nix como `import ./nix/kits-externos.nix { inherit pkgs; }`,
# no mesmo formato de nix/no-mistakes.nix e nix/claude-kit.nix. Devolve um
# ATTRSET (e nao uma lista, como o claude-kit) porque estes kits tem duas
# naturezas: um pacote para home.packages e um punhado de caminhos do store que
# viram entradas home.file, uma a uma, em home.nix.
#
# Como os caminhos relativos, os paths `../scripts/...` do claude-kit.nix nao
# aparecem aqui: TUDO vem de fetchFromGitHub. Nada deste arquivo le a arvore do
# repo, entao a armadilha do "path does not exist" (cabecalho do claude-kit.nix)
# nao se aplica ao conteudo — mas se aplica a ESTE arquivo, que precisa estar no
# indice do git antes de qualquer `nix build`.
#
# ── Pinagem: rev + hash literais, nunca `ref = "main"` ───────────────────────
#
# Conteudo de terceiro que entra no contexto de TODA sessao tem que ser
# reproduzivel e auditavel: o rev diz exatamente que bytes foram lidos, e o hash
# prova que continuam sendo os mesmos. Bumpar e trocar as duas strings e rodar
# ./rebuild.sh — deliberadamente manual, pelo mesmo motivo do minhasSkills em
# home.nix (o upstream muda skill sem avisar; a decisao de quando ela entra na
# maquina e do dono da maquina).
#
# Revisoes colhidas em 28/ago/2026 (`git ls-remote`), todas o HEAD de `main`:
#   snarktank/ralph      6c53cb0b831ebe8739c6a003e22af14902d8b0b5   MIT
#   kunchenguid/backpass fba801bf574e81460ef45214956ffc0053dd8515   MIT  (v0.1.9)
#   mattpocock/skills    6654f6b60cd9d5be8b54c6fafe44346dabeb3b76   MIT
{ pkgs }:

let
  inherit (pkgs) fetchFromGitHub lib;

  ralphSrc = fetchFromGitHub {
    owner = "snarktank";
    repo = "ralph";
    rev = "6c53cb0b831ebe8739c6a003e22af14902d8b0b5";
    hash = "sha256-HuNtf9X/YuQVBQ4+EK0DP1lQe3RCUbj2OuwYzBqX7m0=";
  };

  backpassSrc = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "backpass";
    rev = "fba801bf574e81460ef45214956ffc0053dd8515";
    hash = "sha256-9Vk+l57BHhwzrmjkizaAanw3JSee+QdFyrMGmPeglyw=";
  };

  pocockSrc = fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "6654f6b60cd9d5be8b54c6fafe44346dabeb3b76";
    hash = "sha256-N5tpUIHO2VFeJntBTl6/VLDIVpqoshwFxNJlfXXUwsQ=";
  };

  # ── backpass ────────────────────────────────────────────────────────────────
  #
  # O briefing avisava que o `pnpm-lock.yaml` (e nao package-lock.json) dificulta
  # buildNpmPackage e que talvez fosse preciso escolher entre empacotar de
  # verdade e buscar o pacote em tempo de execucao. Nenhuma das duas: o lockfile
  # e IRRELEVANTE aqui, porque o package.json declara
  #
  #     "dependencies": {}
  #
  # e as 7 entradas de devDependencies sao so eslint/prettier/typescript/@types.
  # Medido em 28/ago/2026 varrendo bin/, src/ (59 arquivos) e templates/ atras de
  # todo especificador de import/require: o conjunto nao-relativo e exatamente
  # node:child_process, node:crypto, node:fs, node:os, node:path, node:process,
  # node:readline/promises, node:url, node:util — mais um `await import("node:sqlite")`
  # dinamico em src/discovery/adapters/sqlite.js. Zero pacotes de terceiro.
  #
  # Logo nao ha arvore npm para resolver: basta copiar os diretorios que o proprio
  # package.json lista em `files` e apontar o node para o entrypoint. Nada e
  # buscado em tempo de execucao, e a versao (0.1.9) fica presa no rev acima.
  #
  # node:sqlite e o motivo do `engines: { node: ">=22.5.0" }` do upstream.
  # nodejs_22 do nixpkgs fixado e 22.x >= 22.5, e ja esta em home.packages para o
  # @playwright/mcp — nao ha runtime novo entrando na maquina por causa disto.
  #
  # PATH: o wrapper NAO prefixa nada. backpass le transcricoes das harnesses do
  # usuario e invoca as CLIs delas (`acpx`, `claude`, ...) pelo PATH; prefixar
  # store na frente e o jeito de fazer o backpass enxergar uma harness diferente
  # da que o usuario digita. O unico binario que ele mesmo dispara e o `git`
  # (unico literal em spawn/exec de src/), e esse entra por --suffix: serve de
  # fallback se faltar, e nunca sombreia o git do usuario.
  backpass = pkgs.stdenvNoCC.mkDerivation {
    pname = "backpass";
    version = "0.1.9";
    src = backpassSrc;

    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/backpass" "$out/bin"
      cp -r bin src templates package.json LICENSE README.md "$out/lib/backpass/"

      makeWrapper ${pkgs.nodejs_22}/bin/node "$out/bin/backpass" \
        --add-flags "$out/lib/backpass/bin/backpass.js" \
        --suffix PATH : ${lib.makeBinPath [ pkgs.git ]}

      runHook postInstall
    '';

    meta = {
      description =
        "Gradient descent for your agent memory - analyzes past agent session "
        + "transcripts and proposes evidence-backed edits to AGENTS.md / CLAUDE.md";
      homepage = "https://github.com/kunchenguid/backpass";
      license = lib.licenses.mit;
      mainProgram = "backpass";
    };
  };
in
{
  # Vai para home.packages (concatenado como o claude-kit).
  packages = [ backpass ];

  # ── ralph.sh: arquivo do store, NAO writeShellApplication ────────────────────
  #
  # O criterio deste repo (cabecalho do claude-kit.nix) manda writeShellApplication
  # para superficie que destroi trabalho. ralph.sh e superficie dessas — roda um
  # agente com --dangerously-skip-permissions em laco. Mesmo assim ele NAO pode ir
  # por writeShellApplication, por tres motivos medidos em 28/ago/2026, nesta ordem
  # de peso:
  #
  # 1. O shellcheck do build REPROVA o script upstream, e reprovar aqui derruba o
  #    `./rebuild.sh` inteiro. Medido construindo o writeShellApplication a mao:
  #      ralph.sh:58  SC2001 (style) FOLDER_NAME=$(echo "$LAST_BRANCH" | sed ...)
  #      ralph.sh:91  SC2086 (info)  for i in $(seq 1 $MAX_ITERATIONS); do
  #    Da para silenciar com excludeShellChecks, mas ver (2) e (3) antes.
  #
  # 2. writeShellApplication PREPENDA `set -o errexit -o nounset -o pipefail` ao
  #    texto. ralph.sh tem `set -e` e mais nada; sob `nounset` um `--tool` sem
  #    valor deixa de ser argumento invalido e vira erro duro, e sob `pipefail` o
  #    pipe `... | tee /dev/stderr` do laco muda de status. Nao se patcha script
  #    de terceiro por conta propria — e trocar o modo do shell por baixo dele e
  #    patchar.
  #
  # 3. O que mata de vez: ralph.sh e ancorado em
  #      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  #    e a partir dai LE $SCRIPT_DIR/prompt.md e $SCRIPT_DIR/CLAUDE.md e ESCREVE
  #    $SCRIPT_DIR/progress.txt, $SCRIPT_DIR/.last-branch e $SCRIPT_DIR/archive/.
  #    Num bin/ do store isso e um diretorio read-only e sem os irmaos — a mesma
  #    armadilha do graphify em checkout-sync-all.sh, so que fatal em vez de
  #    contornavel. Nenhum idioma de empacotamento conserta isso, porque a
  #    ancoragem e o desenho do upstream: o README manda `cp ralph.sh
  #    scripts/ralph/` DENTRO do projeto (Setup, Option 1).
  #
  # Entao vai como arquivo do store com home.file + executable = true, e os tres
  # templates que o laco le viajam junto (ver ralphFiles). O que fica em
  # ~/.local/bin/ralph.sh e a copia pinada-por-hash sempre a mao, para o Option 1;
  # o diretorio ~/.local/share/ralph/ e a copia completa de onde se copia.
  #
  # NAO EXECUTADO: nenhuma invocacao de ralph.sh, nem `--help` (ele nao tem flag
  # de ajuda — todo argumento nao-numerico e ignorado e o laco comeca). O que
  # esta acima e leitura do fonte + o build do shellcheck, nao um run.
  ralphScript = "${ralphSrc}/ralph.sh";

  # Payload completo do ralph num diretorio so, para o `cp` do Option 1.
  # jq (que o script exige) ja esta em home.packages.
  ralphFiles = {
    "ralph.sh" = "${ralphSrc}/ralph.sh";
    "prompt.md" = "${ralphSrc}/prompt.md"; # template do amp
    "CLAUDE.md" = "${ralphSrc}/CLAUDE.md"; # template do claude code
    "prd.json.example" = "${ralphSrc}/prd.json.example";
  };

  # ── As 7 skills ─────────────────────────────────────────────────────────────
  #
  # Cada valor e o DIRETORIO da skill no store. home.nix declara uma entrada
  # home.file por nome — nunca o diretorio `.claude/skills`, ver o comentario de
  # la. Verificado em 28/ago/2026 que nenhuma das sete referencia caminho fora do
  # proprio diretorio (`grep -rnoE '\.\./...'` volta vazio), entao linkar a pasta
  # isolada basta; nao ha Foundation Layer como no minhas-skills.
  #
  # Aqui `source` e do STORE e nao mkOutOfStoreSymlink (que e o idioma das skills
  # do clone proprio): estas sao de terceiro e o ponto e justamente que NAO sejam
  # editaveis na hora — imutabilidade e o que o hash promete.
  #
  # Custo de contexto (medido em 28/ago/2026, ver o commit): as cinco do Pocock
  # carregam `disable-model-invocation: true` e por isso nao entram no listing do
  # modelo; so `prd` e `ralph` entram.
  skills = {
    # snarktank/ralph — user-invocable, ENTRAM no contexto.
    prd = "${ralphSrc}/skills/prd";
    ralph = "${ralphSrc}/skills/ralph";

    # mattpocock/skills — disable-model-invocation: true nas cinco.
    grill-with-docs = "${pocockSrc}/skills/engineering/grill-with-docs";
    wayfinder = "${pocockSrc}/skills/engineering/wayfinder";
    to-spec = "${pocockSrc}/skills/engineering/to-spec";
    to-tickets = "${pocockSrc}/skills/engineering/to-tickets";
    implement = "${pocockSrc}/skills/engineering/implement";
  };
}

# ── O nome que NAO existe ────────────────────────────────────────────────────
#
# O pedido original dizia "to-speck". Nao ha `to-speck` em mattpocock/skills; a
# skill chama-se `to-spec` (conferido no rev fixado acima, junto das outras 18 de
# skills/engineering/). Se um dia aparecer um `to-speck`, e outra coisa.
#
# ── O que NAO foi trazido, de proposito ──────────────────────────────────────
#
# - As outras 14 skills de mattpocock/skills/engineering/ (ask-matt, code-review,
#   tdd, ...). O pedido eram cinco.
# - `grill-me` e `grilling` continuam onde estao, postas a mao em ~/.claude/skills.
#   `grill-with-docs` e prima delas e NAO as substitui: sao entradas separadas e
#   nenhuma entrada gerenciada e criada com aqueles dois nomes.
# - O marketplace de plugin do ralph (`/plugin marketplace add snarktank/ralph`).
#   Ele resolveria as skills em tempo de execucao, sem rev nem hash — exatamente
#   o oposto da pinagem que este arquivo existe para dar.
