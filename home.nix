{ config, pkgs, lib, user, inputs, ... }:

let
  # Aponta direto para o clone, nao para ~/.dotfiles. Aquele link e criado a mao
  # pelo rebuild.sh (nao pelo Nix), entao se sumisse os symlinks de config abaixo
  # dangariam e o app caia no padrao. Este caminho absoluto nao depende de nada
  # imperativo. (Se um dia mover o repo, e so ajustar esta linha.)
  dotfiles = "${config.home.homeDirectory}/Projects/dotfiles";

  # Clone das skills proprias mantidas num clone separado. Path canonico e contrato, nao gosto:
  # as SKILL.md leem o Foundation Layer por path ABSOLUTO daqui (install.sh
  # avisa quando SKILLS_HOME != canonico), entao mover isso quebra as skills do clone.
  minhasSkills = "${config.home.homeDirectory}/.claude/minhas-skills";

  # Toolchain que o firstmate exige. Nao e opcional: fm-bootstrap.sh define
  #   COMMON_TOOLS="node git gh no-mistakes gh-axi chrome-devtools-axi \
  #                 lavish-axi tasks-axi quota-axi"
  # como "a universal toolchain every home needs".

  # no-mistakes vem compilado do source. O pin (version/rev/hash) mora em
  # nix/no-mistakes.nix porque a imagem-base das microVMs precisa do MESMO
  # commit compilado para linux/arm64 — ver scripts/shuru-base-image.sh. Duas
  # copias do pin dariam drift silencioso entre o que o host valida e o que o
  # guest roda.
  no-mistakes = import ./nix/no-mistakes.nix { inherit pkgs; };

  # Kit de harness do Claude Code: os quatro checkout-* e o claude-yolo. Segue o
  # precedente do no-mistakes acima — a unica extracao para nix/ que o repo faz —
  # em vez de inventar um modules/ que nao existe. A justificativa de
  # writeShellApplication vs mkOutOfStoreSymlink (shellcheck no build, `git`
  # pinnado nos scripts que rodam `reset --hard`) mora no cabecalho do arquivo.
  claude-kit = import ./nix/claude-kit.nix { inherit pkgs; };

  # Kits de TERCEIROS que ficam globais em toda sessao do Claude Code: o ralph
  # (loop autonomo), a CLI backpass e sete skills. Mesmo idioma de import dos
  # dois acima, mas devolve um ATTRSET e nao uma lista, porque estes kits sao
  # meio pacote (home.packages) e meio arquivo (home.file, um a um).
  #
  # A pinagem por rev+hash de cada repo, a razao de cada escolha de empacotamento
  # e o que ficou de fora moram no cabecalho e nos comentarios do arquivo. Leia
  # ANTES de bumpar qualquer rev: o motivo de ralph.sh nao ser
  # writeShellApplication esta la, medido, e nao e estetica.
  kits-externos = import ./nix/kits-externos.nix { inherit pkgs; };

  # Os 5 CLIs -axi so existem como pacote npm: nao ha flake, nem release, nem
  # package-lock.json publicado (verificado nos 5 repos em 29/jul/2026), entao
  # buildNpmPackage nao tem lockfile pra morder. Ficam pinnados por versao e
  # instalados na ativacao num prefixo escrivivel.
  #
  # Por que nao `npm install -g` como o bootstrap sugere: o prefixo do npm aqui e
  # o proprio nix store (nodejs-slim-22.23.1), read-only — o comando do bootstrap
  # falha de saida nesta maquina.
  fmAxiVersions = {
    "gh-axi" = "0.1.28";
    "chrome-devtools-axi" = "0.1.27";
    "lavish-axi" = "0.1.43";
    "tasks-axi" = "0.2.3";
    "quota-axi" = "0.1.16";
  };
  # Os 3 primeiros tem `setup hooks`; tasks-axi e quota-axi nao.
  fmAxiWithHooks = [ "gh-axi" "chrome-devtools-axi" "lavish-axi" ];
  fmNpmPrefix = "${config.home.homeDirectory}/.local/state/fm-npm";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    gh        # GitHub CLI. Veio do tap da Automic Vault ate 02/ago/2026, quando
              # o `av harden gh` foi aposentado (item 3.4 do checklist) e o unico
              # motivo daquele formulario — atestar o hash de uma binaria que ELES
              # distribuem — deixou de existir. Passou para o nixpkgs, e nao para
              # o release oficial do cli/cli nem para o homebrew-core, por um
              # motivo so: o `gh` agora E o caminho de credencial desta maquina,
              # entao a versao tem que estar presa no flake.lock como o resto do
              # sistema, nao andando sozinha num `brew upgrade`. Verificado: o
              # nixpkgs fixado compila de github.com/cli/cli/archive/refs/tags/
              # v2.96.0.tar.gz, a MESMA tag do release oficial. Quem consome isto
              # e o wrapper scripts/gh-token.sh, via GH_REAL abaixo.
    lazygit
    neovim
    # Cadeia de ferramentas que a config do Neovim (home/.config/nvim) chama por
    # nome. Vem do nix, e nao do mason, porque nao sao "servidor de linguagem
    # que o editor baixa": o `tree-sitter` e requisito de BUILD dos parsers e sem
    # ele a linha nova do nvim-treesitter nao compila nada — sintoma que se le
    # como erro de compilador C quando e ferramenta ausente. Ver a secao 5 do
    # nvim/README.md e lua/configs/treesitter.lua.
    tree-sitter
    stylua    # formatador de lua (conform + .stylua.toml da config)
    shfmt     # formatador de shell (conform + none-ls)
    shellcheck # linter de shell, entregue como diagnostico pelo none-ls
              # tmux saiu daqui: agora vem de programs.tmux (abaixo), que instala
              # o pacote E gera o config. Deixar nos dois lugares colide.
    nodejs_22 # runtime do @playwright/mcp (servidor MCP Node que dirige o
              # navegador). Declarado aqui em vez de `brew install node` porque
              # com onActivation.cleanup = "zap" um install imperativo seria
              # removido no proximo rebuild — e o MCP quebraria junto.
              # Rodar o Playwright no HOST e excecao consciente ao item 6.4 do
              # checklist (decisao de 29/jul/2026), valida so sob as condicoes
              # listadas la: Chromium proprio do Playwright, perfil isolado e
              # descartado, sem storageState em disco, sem modo extensao, sem
              # CDP no navegador pessoal. Trabalho nao supervisionado vai para o
              # container. Ler docs/arquitetura-navegadores.md antes de mexer.
    google-cloud-sdk
              # Ferramenta da sessao administrativa que cria a SA-broker
              # (broker/gcp/setup-sa-broker.sh, Fase 3 do plano de tokens). O
              # broker em si NAO chama gcloud: cunha token por HTTP com a chave
              # do Keychain.
              #
              # A disciplina que torna isto seguro NAO esta neste arquivo (veio
              # junto do cask que este pacote substitui; nao deixe se perder de
              # novo):
              #   - host DESLOGADO por default (checklist 6.6). Sessao admin e
              #     `gcloud-admin` (definida abaixo em initContent), que faz
              #     login -> subshell -> revoke no exit, porque `gcloud auth
              #     login` grava refresh token de USUARIO em texto plano em
              #     ~/.config/gcloud/credentials.db.
              #   - NUNCA `gcloud auth application-default login` (ADC em disco).
              #   - NUNCA chave de SA em arquivo — o setup-sa-broker.sh gera,
              #     importa no Keychain e apaga no mesmo passo.
              # Medido em 29/jul/2026: credentials.db com 0 linhas e sem
              # application_default_credentials.json. Esse e o estado a preservar.
              #
              # Aqui e nao no cask "gcloud-cli" (decisao de 29/jul/2026, depois
              # de dois rebuilds falharem). O cask instala executando o
              # install.sh da Google como passo de postflight e declara
              # auto_updates — o mesmo padrao que este repo ja recusou para o
              # automic-vault por nao ser reproduzivel. Aqui a versao e travada
              # pelo flake.lock e nada se atualiza por baixo.
              # O motivo imediato foi outro e vale registrar: brew vem travado do
              # nix store enquanto homebrew-core/cask vem da API sempre-ultima,
              # entao passos de instalacao novos ("set_permissions", depois
              # "run") quebram fora de ordem. Essa defasagem CONTINUA de pe para
              # as demais formulas; a correcao estrutural seria fixar os taps
              # como inputs do flake com mutableTaps = false.
    # the font everything renders in
    nerd-fonts.hack
  ] ++ [
    # Fora do `with pkgs` porque nao vem do nixpkgs: e o output do flake do
    # upstream, declarado como input em flake.nix. Ver o comentario de lá sobre
    # o `follows`.
    inputs.treehouse.packages.${pkgs.stdenv.hostPlatform.system}.default
    no-mistakes
  ] ++ claude-kit          # ja e uma lista: concatena direto, nao envolva em [ ].
    ++ kits-externos.packages;  # idem: hoje so o `backpass`.
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    CLAUDE_CODE_AUTO_COMPACT_WINDOW = "280000";
    # Claude Code vem do cask (claude-code@latest). Instalacoes por Homebrew ja
    # nao se auto-atualizam, mas fixar aqui garante que o self-updater nunca
    # reescreva o binario por baixo do brew — foi exatamente isso que disparou o
    # `zap` destrutivo (~/.claude.json + binario pra Lixeira). Updates passam a
    # vir so por `brew upgrade` / rebuild. `claude update` manual ainda funciona.
    DISABLE_AUTOUPDATER = "1";
    # O `gh` REAL, para o wrapper ~/.local/bin/gh nao se chamar em laco. Caminho
    # exato do store, e nao um nome no PATH: o wrapper vem ANTES do nixpkgs no
    # PATH de proposito, entao qualquer busca por nome acharia ele mesmo.
    GH_REAL = "${pkgs.gh}/bin/gh";
  };
  home.sessionPath = [
    "$HOME/.local/bin"
    # Onde a ativacao instala os CLIs -axi (ver home.activation.fmAxi).
    "${fmNpmPrefix}/bin"
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept

      # ~/.local/bin ANTES do Homebrew. Nao da pra fazer isso em
      # home.sessionPath: aquilo escreve no ~/.zshenv, e o /etc/zshrc roda
      # depois com `eval "$(brew shellenv)"`, que reprepende /opt/homebrew/bin
      # incondicionalmente. O ~/.zshrc (este bloco) e o unico ponto que roda
      # DEPOIS do /etc/zshrc. Verificado: sem isto, `command -v gh` da
      # /opt/homebrew/bin/gh.
      # Serve para o wrapper ~/.local/bin/gh (scripts/gh-token.sh, que le o
      # PAT do keychain)
      # sombrear o gh do Homebrew, inclusive nos processos filhos — agente,
      # herdr, tudo herda o PATH desta shell.
      typeset -U path   # mantem a PRIMEIRA ocorrencia e descarta as repetidas
      path=("$HOME/.local/bin" $path)

      # O servidor do herdr e persistente (tipo tmux); se ele foi iniciado de
      # dentro de uma sessao do Claude, capturou CLAUDE_CODE_CHILD_SESSION=1 no
      # ambiente e TODO painel herda isso — cada claude aberto num painel se ve
      # como sessao-filha e desliga o salvamento do transcript ("Transcript
      # saving is off"). Nao da pra corrigir na config.toml do herdr (ela nao
      # injeta env). Dentro de um painel do herdr (HERDR_ENV=1) forcamos a
      # persistencia, entao o transcript volta a ser gravado e da pra --resume.
      if [ "''${HERDR_ENV:-}" = "1" ]; then
        export CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1
      fi

      # Sessao administrativa efemera do gcloud (Fase 3/4 do plano de tokens).
      # `gcloud auth login` grava refresh token de USUARIO em texto plano, fora
      # do TCC e fora do Automic Vault; a funcao amarra a credencial ao tempo de
      # vida de um subshell e revoga na saida. Necessaria para a revisao
      # trimestral das SAs (Fase 4) e para criar a SA-broker.
      source ${dotfiles}/broker/shell/gcloud-admin.zsh

      # Removido deliberadamente (item 4.2 do checklist de reinstalacao): a ponte
      # que fazia `set -a; . ~/Projects/.env` e exportava GH_PAT_TOKEN_ALEX como
      # GH_TOKEN. Ela exportava TODAS as variaveis do .env para todo processo
      # filho — inclusive agentes — e ainda quebrava `gh auth switch`.
      # O gh autenticado por device flow guarda o token no keyring e dispensa isso.
      # Nao reintroduzir: nenhum segredo entra no ambiente a partir de arquivo.
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  # tmux existe aqui por DOIS motivos, e o segundo e novo.
  #
  # (1) Fallback do herdr: o backend escolhido para o terminal local ainda e
  #     marcado como experimental pelo firstmate, e manter o caminho suportado
  #     instalado evita depender de um rebuild se ele travar.
  # (2) Persistencia de sessao no ACESSO REMOTO: a conexao de um celular cai
  #     toda vez que troca de Wi-Fi para 5G. O tmux e o que faz o trabalho
  #     sobreviver a isso — a sessao vive NESTE Mac, o cliente so se reconecta.
  #     E o substituto pobre do Mosh, que exigiria mosh-server e portas UDP.
  #
  # Config deliberadamente pequena: cada linha abaixo existe por um motivo de
  # acesso remoto, nao por gosto. Prefixo fica no Ctrl+B padrao de proposito —
  # quem entra de um app de celular nao quer descobrir que o atalho e outro.
  programs.tmux = {
    enable = true;
    # ESC instantaneo. O default de 500ms faz o neovim engasgar em cada Esc
    # sobre SSH, e o sintoma parece lentidao da rede.
    escapeTime = 0;
    # O default de 2000 linhas some rapido quando um build longo roda sem
    # ninguem olhando — que e justamente o caso de uso do acesso remoto.
    historyLimit = 50000;
    # A MESMA sessao vai ser aberta de telas de tamanhos muito diferentes
    # (iPhone e um Mac). Sem isto, a janela fica presa ao menor cliente ja
    # conectado, mesmo depois que ele sai.
    aggressiveResize = true;
    # Rolagem por toque/trackpad. Custo consciente: para selecionar texto com
    # o comportamento nativo do terminal, segure Shift.
    mouse = true;
    # screen-256color e nao tmux-256color: o segundo exige um terminfo que
    # clientes de celular frequentemente nao tem, e o sintoma e cor quebrada
    # num app que voce nao controla.
    terminal = "screen-256color";
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  # Ao contrario do herdr, o treehouse nao escreve runtime aqui: o estado do pool
  # e o lock ficam no proprio pool (<pool>/treehouse-state.json). Este diretorio
  # tem so o config.toml, entao nao precisa de nada no .gitignore.
  home.file.".config/treehouse".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/treehouse";

  # O firstmate invoca este wrapper pelo PATH como launch command cru, entao ele
  # precisa de um nome estavel em ~/.local/bin. Symlink out-of-store (e nao um
  # pacote) porque o basename `claude-shuru` e o que faz o fm-spawn instalar o
  # hook de Stop (ele casa `claude*`), e porque editar o script durante a Fase 4
  # do plano nao deve exigir rebuild.
  home.file.".local/bin/claude-shuru".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/scripts/claude-shuru";

  # Cola de atalhos do Neovim (nvim/README.md documenta o que ela especifica).
  # Sem o `.sh` no nome do link: e para digitar `nvim-atalhos`, nao o arquivo.
  # Out-of-store pelo mesmo motivo dos vizinhos — a lista de atalhos muda junto
  # com a config do editor, e nao deve cobrar rebuild por isso.
  home.file.".local/bin/nvim-atalhos".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim/nvim-atalhos.sh";

  # `gh` do host le um PAT fine-grained do login keychain (item `github-pat`) e
  # o injeta por ambiente. Historico, porque o caminho ate aqui foi longo:
  #  - ate 02/ago/2026: token pessoal no Automic Vault. Caiu porque o Secret
  #    Gate cobrava 582 dialogos em 24 h e nenhuma config do AV resolvia — ele
  #    atribui o pedido ao primeiro app verificado na arvore de processos, que e
  #    o Claude Code, e o Claude Code e inelegivel por assinatura.
  #  - 02/ago a 18/ago/2026: token de instalacao do GitHub App, TTL 1 h, cunhado
  #    pelo av-broker (scripts/gh-broker.sh). Caiu por custo humano: um gesto por
  #    cunhagem e um token que morria no meio da sessao.
  #  - desde 18/ago/2026: PAT de vida longa, decisao consciente de abrir mao da
  #    credencial efemera. O cabecalho de scripts/gh-token.sh tem o balanco.
  #
  # Symlink out-of-store pelo mesmo motivo do claude-shuru: mexer no wrapper nao
  # deve exigir rebuild.
  home.file.".local/bin/gh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/scripts/gh-token.sh";

  # O helper que le/grava os dois PATs no keychain. Precisa de nome estavel no
  # PATH porque o gh-token.sh e o claude-shuru chamam ele, e porque voce vai
  # rodar `gh-pat set` a mao na rotacao.
  home.file.".local/bin/gh-pat".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/scripts/gh-pat.sh";

  # O proprio broker. Desde 18/ago/2026 ele NAO serve mais o GitHub — o alvo
  # `github` e todo o subsistema de agente sairam junto com a cunhagem. O que
  # resta e Shopify, GCP e Salesforce, que seguem com credencial efemera e
  # portao; a decisao de abrir mao disso foi so para o GitHub.
  # Mesmo idioma out-of-store: o broker e editado com frequencia e nao faz
  # sentido pedir rebuild para cada ajuste de politica.
  home.file.".local/bin/av-broker".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/broker/bin/av-broker";

  # interrupcoes-report.sh e a metrica do objetivo declarado — quantas vezes eu
  # interrompi para pedir algo que o agente devia ter feito sozinho. E o unico
  # script do claude-kit que NAO entra em nix/claude-kit.nix, por dois motivos
  # concretos:
  #
  #  1. Ele se auto-envia por ssh: a chamada remota e
  #     `ssh "$dest" bash -s -- --emit-json ... < "$0"`. Sob writeShellApplication
  #     o "$0" e o wrapper do store, cujo corpo comeca com
  #     `export PATH="/nix/store/...:$PATH"` — e isso ia parar num host que nao
  #     tem /nix/store. Nao quebra (diretorio inexistente no PATH e so ignorado
  #     na busca), mas mandar prelude nix para maquina estrangeira e efeito
  #     colateral sem nenhum ganho.
  #  2. Toda categoria nova de interrupcao e uma regex a mais no python inline.
  #     Exigir rebuild a cada ajuste e o caminho garantido para parar de ajustar.
  #
  # Mesmo idioma out-of-store do claude-shuru/gh/gh-pat/av-broker acima.
  home.file.".local/bin/interrupcoes-report".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/scripts/claude-kit/interrupcoes-report.sh";

  # ralph.sh (snarktank/ralph, MIT) — o laco de agente autonomo. Aqui ele NAO e
  # mkOutOfStoreSymlink nem writeShellApplication: e ARQUIVO DO STORE, com
  # executable = true. Nao e um terceiro idioma inventado, sao os dois criterios
  # do repo aplicados a um caso que nenhum dos dois cobre:
  #
  #   - mkOutOfStoreSymlink e para "script meu, editado direto, sem rebuild".
  #     Este nao e meu; a graca dele e estar preso num rev com hash.
  #   - writeShellApplication reprova no shellcheck (SC2001 e SC2086, medido) e,
  #     pior, prependa `set -o nounset -o pipefail` a um script de terceiro que
  #     so pediu `set -e`. E ancorado em SCRIPT_DIR, entao um bin/ do store e
  #     read-only e sem os irmaos que ele le. Detalhe em nix/kits-externos.nix.
  #
  # Fica em ~/.local/bin porque o briefing pede o PATH do usuario e porque
  # `command -v ralph.sh` e o jeito estavel de achar a copia pinada. Mas note o
  # desenho do upstream (README, Setup Option 1): ralph.sh roda de DENTRO do
  # projeto, copiado para scripts/ralph/ junto do template de prompt — invocado
  # do PATH, ele procuraria prd.json e escreveria progress.txt em ~/.local/bin.
  # Por isso o payload completo vai tambem para ~/.local/share/ralph/ abaixo, que
  # e de onde se copia. `jq`, que ele exige, ja esta em home.packages.
  home.file.".local/bin/ralph.sh" = {
    source = kits-externos.ralphScript;
    executable = true;
  };

  # O payload do ralph num diretorio so. Uma entrada por arquivo e nao
  # `home.file.".local/share/ralph".source = <dir>` de proposito: o repo upstream
  # traz um PNG de 4,7 MB e um webp na raiz, e linkar a arvore inteira arrastaria
  # os dois para o store da geracao sem nenhum uso.
  #
  # `prompt.md` e o template do amp; `CLAUDE.md` e o do Claude Code (e o que o
  # laco le quando `--tool claude`). Este CLAUDE.md NAO e memoria de projeto: ele
  # mora em ~/.local/share, fora de qualquer arvore que o Claude Code varra.
  home.file.".local/share/ralph/ralph.sh" = {
    source = kits-externos.ralphFiles."ralph.sh";
    executable = true;
  };
  home.file.".local/share/ralph/prompt.md".source =
    kits-externos.ralphFiles."prompt.md";
  home.file.".local/share/ralph/CLAUDE.md".source =
    kits-externos.ralphFiles."CLAUDE.md";
  home.file.".local/share/ralph/prd.json.example".source =
    kits-externos.ralphFiles."prd.json.example";

  # firstmate: clone git travado no rev do flake.lock, NAO um pacote em
  # home.packages. Dois motivos medidos em 29/jul/2026, nesta ordem de peso:
  #
  #  1. O cd-guard (bin/fm-cd-pretool-check.sh) exige que FM_ROOT seja um repo
  #     git plano — ele roda `git -C "$FM_ROOT" rev-parse --git-dir` e sai com
  #     exit 0 se falhar. E falha ABERTO por design ("never a block, so a broken
  #     environment never denies a shell command"). No /nix/store isso desligaria
  #     em silencio o seatbelt que barra o `cd` acidental que reloca a shell
  #     primaria pra dentro de um clone de projeto. Guard inerte sem aviso e pior
  #     que guard ausente.
  #  2. FM_HOME cai em FM_ROOT por default, e o firstmate escreve projects/,
  #     state/, data/ e config/* ali dentro (todos no .gitignore do upstream, por
  #     isso o teste de arvore limpa abaixo distingue codigo de estado).
  #
  # O que este bloco NAO faz: instalar dependencias. O firstmate exige harness de
  # agente, gh autenticado e o backend (herdr, declarado em brews) — o
  # fm-bootstrap.sh reporta o que faltar.
  #
  # Atualizar: nix flake update firstmate && ./rebuild.sh
  home.activation.firstmate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fmDir="${config.home.homeDirectory}/Projects/firstmate"
    fmRev="${inputs.firstmate.rev}"
    fmGit=${pkgs.git}/bin/git

    if [ ! -e "$fmDir" ]; then
      $DRY_RUN_CMD "$fmGit" clone --quiet \
        https://github.com/kunchenguid/firstmate "$fmDir"
    fi

    if [ -d "$fmDir/.git" ]; then
      fmCur=$("$fmGit" -C "$fmDir" rev-parse HEAD 2>/dev/null || echo none)
      if [ "$fmCur" != "$fmRev" ]; then
        if [ -n "$("$fmGit" -C "$fmDir" status --porcelain 2>/dev/null)" ]; then
          echo "firstmate: $fmDir tem mudancas locais no codigo;" \
               "pin para $fmRev PULADO. Resolva a mao e rode ./rebuild.sh."
        else
          # HEAD desanexado e deliberado: e a representacao honesta de "travado
          # pelo lock" e nao dispara o tangle check do fm-bootstrap.sh, que so
          # reclama de branch nomeada != default (fm-tangle-lib.sh usa
          # `symbolic-ref`, vazio em detached).
          $DRY_RUN_CMD "$fmGit" -C "$fmDir" fetch --quiet origin
          $DRY_RUN_CMD "$fmGit" -C "$fmDir" checkout --quiet --detach "$fmRev"
        fi
      fi
    fi
  '';

  # minhas-skills: clone travado num rev LITERAL, nao um input do flake.
  # O repo e PRIVADO e um input `github:...` seria resolvido pelo nix na
  # avaliacao, exigindo `access-tokens` no nix.conf — um PAT em arquivo, o que o
  # reinstall-checklist 3.2 proibe (device flow, nunca PAT). O clone abaixo usa o
  # credential helper que o `gh auth login` ja configurou: nenhum segredo novo.
  #
  # Preco assumido: sem input nao ha flake.lock pra travar o rev. Bumpar e trocar
  # a string e rodar ./rebuild.sh — deliberadamente manual, porque o upstream
  # auto-descobre skills novas e eu quero decidir quando elas entram no host.
  #
  # NAO chamamos o install.sh do upstream aqui, embora ele exista e faca isso.
  # Tres motivos lidos no script: ele termina em `die` (exit 1) a cada aviso, o
  # que derrubaria o rebuild; faz `mv` de backup com timestamp se achar diretorio
  # real, efeito colateral nao-idempotente numa ativacao; e auto-descobre
  # qualquer dir com SKILL.md. Os symlinks estao declarados abaixo, um a um.
  home.activation.minhasSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    amsDir="${minhasSkills}"
    amsRev="0000000000000000000000000000000000000000"  # troque pelo rev do SEU clone
    amsGit=${pkgs.git}/bin/git

    if [ ! -e "$amsDir" ]; then
      $DRY_RUN_CMD "$amsGit" clone --quiet \
        https://github.com/SEU-USUARIO/minhas-skills "$amsDir"
    fi

    if [ -d "$amsDir/.git" ]; then
      amsCur=$("$amsGit" -C "$amsDir" rev-parse HEAD 2>/dev/null || echo none)
      if [ "$amsCur" != "$amsRev" ]; then
        if [ -n "$("$amsGit" -C "$amsDir" status --porcelain 2>/dev/null)" ]; then
          echo "minhas-skills: $amsDir tem mudancas locais;" \
               "pin para $amsRev PULADO. Resolva a mao e rode ./rebuild.sh."
        else
          $DRY_RUN_CMD "$amsGit" -C "$amsDir" fetch --quiet origin
          $DRY_RUN_CMD "$amsGit" -C "$amsDir" checkout --quiet --detach "$amsRev"
        fi
      fi
    fi
  '';

  # As skills do clone proprio, uma a uma. NUNCA `home.file.".claude/skills"` como diretorio:
  # ele ja contem grill-me, grilling e no-mistakes, que nao vem daqui, e declarar
  # o diretorio inteiro faria o home-manager reivindicar os tres.
  #
  # mkOutOfStoreSymlink e nao `source = ...` do store pelo mesmo motivo do
  # minhasSkills acima, e porque `git -C ~/.claude/minhas-skills pull` deve
  # propagar skills + foundation sem rebuild quando voce estiver editando.
  # Nesta copia publica os NOMES das skills viraram placeholders: eles diziam
  # de que a organizacao trata. Troque por um nome por skill do seu clone.
  home.file.".claude/skills/minha-skill-1".source =
    config.lib.file.mkOutOfStoreSymlink "${minhasSkills}/skills/minha-skill-1";
  home.file.".claude/skills/minha-skill-2".source =
    config.lib.file.mkOutOfStoreSymlink "${minhasSkills}/skills/minha-skill-2";

  # ── As 7 skills de terceiro (kits-externos) ─────────────────────────────────
  #
  # A MESMA regra do bloco acima, e ela vale duplamente aqui: uma entrada por
  # skill, NUNCA `home.file.".claude/skills"` como diretorio. Hoje ~/.claude/skills
  # e hibrido — 7 symlinks gerenciados pelo nix convivendo com grill-me, grilling
  # e no-mistakes, postas a mao. Declarar o diretorio faria o home-manager
  # reivindica-lo e apagar as tres. Com as 14 entradas abaixo o diretorio segue
  # sendo real e so os 14 nomes listados sao gerenciados.
  #
  # `grill-me` e `grilling` NAO sao tocadas: `grill-with-docs` e da mesma familia
  # (mattpocock) mas e um terceiro nome, entra ao lado delas e nao no lugar.
  #
  # Aqui `source` e do store, e nao mkOutOfStoreSymlink como nas skills do clone proprio.
  # A diferenca e de titularidade, nao de gosto: as do clone proprio sao minhas e eu quero
  # `git pull` no clone valendo sem rebuild; estas sao de terceiro e o valor delas
  # e serem imutaveis e conferiveis pelo hash em nix/kits-externos.nix.
  #
  # CUSTO DE CONTEXTO (medido em 28/ago/2026, ver o commit): das sete, so `prd` e
  # `ralph` entram no listing que o modelo recebe a cada sessao — ~124 tokens
  # somados. As cinco do Pocock trazem `disable-model-invocation: true` no
  # front-matter e ficam de fora do listing; continuam invocaveis pelo usuario.
  home.file.".claude/skills/prd".source = kits-externos.skills.prd;
  home.file.".claude/skills/ralph".source = kits-externos.skills.ralph;
  home.file.".claude/skills/grill-with-docs".source =
    kits-externos.skills.grill-with-docs;
  home.file.".claude/skills/wayfinder".source = kits-externos.skills.wayfinder;
  home.file.".claude/skills/to-spec".source = kits-externos.skills.to-spec;
  home.file.".claude/skills/to-tickets".source = kits-externos.skills.to-tickets;
  home.file.".claude/skills/implement".source = kits-externos.skills.implement;

  # ── Skills proprias, versionadas NESTE repo ─────────────────────────────────
  #
  # Terceira titularidade, ao lado das duas de cima: a fonte-da-verdade e um
  # diretorio de home/.claude/skills/ aqui no dotfiles, nao um clone externo
  # (clone proprio) nem um tarball pinnado por hash (kits-externos). O historico da skill
  # e o historico deste repo — `git log home/.claude/skills/<nome>` — e um setup
  # novo a instala no mesmo rebuild que instala o resto.
  #
  # mkOutOfStoreSymlink, mesmo idioma de home/.claude/CLAUDE.md: o arquivo real e
  # o do repo, e editar o prompt vale na sessao seguinte sem rebuild. Uma copia
  # para o store cobraria `./rebuild.sh` a cada virgula de um arquivo que e so
  # texto para o modelo ler — e o texto e exatamente o que se ajusta iterando.
  #
  # A regra do bloco anterior continua valendo: UMA entrada por skill, nunca
  # `home.file.".claude/skills"` como diretorio (ele e hibrido e o home-manager
  # reivindicaria grill-me, grilling e no-mistakes, que nao vem daqui).
  #
  # Aponta para o DIRETORIO, nao para o SKILL.md: o formato admite arquivos de
  # apoio ao lado (references/, scripts/), e linkar so o .md os deixaria de fora
  # no dia em que existirem.
  home.file.".claude/skills/react-feynman".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/home/.claude/skills/react-feynman";

  # CLIs -axi do firstmate: instala as versoes pinnadas de fmAxiVersions num
  # prefixo escrivivel e registra os hooks nos harnesses.
  #
  # Sobre a titularidade do ~/.claude/settings.json (decisao de 29/jul/2026):
  # ela CONTINUA com o rig, e nao passou para o dotfiles. Nao por preferencia —
  # por tres medicoes:
  #   1. Symlink esta descartado. O Claude Code reescreve o arquivo em runtime
  #      (visto: mtime mudando durante a sessao), e o comentario mais abaixo neste
  #      arquivo ja registrava isso. Store read-only nao aceita reescrita.
  #   2. Titularidade do arquivo inteiro clobberia o que o runtime escreve. O
  #      arquivo vivo tem model, theme, tui, agentPushNotifEnabled e
  #      skipDangerousModePermissionPrompt, mais o SessionStart do rig. A copia
  #      versionada em home/.claude/settings.json e do initial commit e so tem
  #      theme + statusLine: declarar ela como verdade apagaria o resto.
  #   3. `setup hooks` escreve 7 arquivos em 4 harnesses (~/.claude/settings.json,
  #      ~/.codex/hooks.json, ~/.codex/config.toml, ~/.copilot/hooks/, e 3 plugins
  #      em ~/.config/opencode/plugins/). Reimplementar isso em nix seria clonar o
  #      formato de hook de quatro harnesses e quebrar a cada bump dos -axi.
  # O que o dotfiles passa a possuir e o que importa: QUAIS ferramentas e em QUE
  # versao, aqui em fmAxiVersions, com o registro reproduzivel de um wipe.
  # Depois de claudeSettings de proposito: a copia do settings.json roda antes,
  # e o `setup hooks` daqui roda por cima dela — na ordem inversa, a copia
  # apagaria hooks recem-registrados de ferramenta nova ainda fora do arquivo
  # versionado.
  home.activation.fmAxi = lib.hm.dag.entryAfter [ "writeBoundary" "claudeSettings" ] ''
    axiPrefix="${fmNpmPrefix}"
    axiNpm=${pkgs.nodejs_22}/bin/npm
    axiJq=${pkgs.jq}/bin/jq

    $DRY_RUN_CMD mkdir -p "$axiPrefix"

    axiInstall() {
      axiName=$1
      axiWant=$2
      axiManifest="$axiPrefix/lib/node_modules/$axiName/package.json"
      axiHave=none
      if [ -f "$axiManifest" ]; then
        axiHave=$("$axiJq" -r '.version // "none"' "$axiManifest" 2>/dev/null \
          || echo none)
      fi
      if [ "$axiHave" != "$axiWant" ]; then
        echo "firstmate: instalando $axiName@$axiWant (tinha: $axiHave)"
        $DRY_RUN_CMD "$axiNpm" install -g --prefix "$axiPrefix" \
          --no-fund --no-audit "$axiName@$axiWant"
      fi
    }

    ${lib.concatStringsSep "\n    "
      (lib.mapAttrsToList (n: v: "axiInstall ${n} ${v}") fmAxiVersions)}

    # `setup hooks` roda em toda ativacao, nao so quando instalou: e idempotente e
    # assim auto-cicatriza se o Claude Code reescrever o settings.json e perder o
    # hook. Medido em 29/jul/2026 num HOME descartavel: 3 execucoes seguidas
    # mantem 3 entradas em hooks.SessionStart (nao duplica), preservam um
    # SessionStart alheio ja presente e preservam as demais chaves do arquivo.
    # PATH com o node do nix na frente, e NAO herdado. Medido em 19/ago/2026: os
    # binarios -axi tem shebang `#!/usr/bin/env node`, e a ativacao do
    # home-manager roda com um PATH saneado onde `node` nao existe — as tres
    # chamadas morriam em `env: node: No such file or directory` (127), em TODA
    # ativacao, desde sempre. O `npm` acima nunca sofreu disso porque e invocado
    # por caminho absoluto do store; o shebang e que depende do PATH.
    #
    # E o mesmo defeito que derrubou o ensure-keychain-search-list.sh no mesmo
    # dia: ativacao nao herda o seu shell, e todo comando externo precisa vir de
    # caminho absoluto ou de um PATH montado aqui.
    #
    # A saida deixou de ser jogada fora. Ela era suprimida para nao poluir o
    # rebuild no caso bom, e o efeito colateral foi esconder a causa por semanas:
    # a mensagem dizia "rode a mao pra ver", e rodar a mao FUNCIONAVA, porque o
    # shell interativo tem node no PATH. Agora o caso bom segue mudo e o ruim
    # imprime o motivo.
    axiPath="${pkgs.nodejs_22}/bin:$PATH"
    for axiTool in ${lib.concatStringsSep " " fmAxiWithHooks}; do
      if [ -x "$axiPrefix/bin/$axiTool" ]; then
        if ! axiOut=$(PATH="$axiPath" $DRY_RUN_CMD "$axiPrefix/bin/$axiTool" setup hooks 2>&1); then
          echo "firstmate: '$axiTool setup hooks' falhou:"
          echo "$axiOut"
        fi
      fi
    done
  '';

  # ~/.claude/settings.json: o dotfiles E o dono (decisao de 29/jul/2026,
  # revertendo o ADR do rig — o rig foi aposentado; os arquivos que ele possuia,
  # ~/.claude/CLAUDE.md e os AGENTS.md do codex/opencode, ja nem existem no
  # disco).
  #
  # Dono por COPIA na ativacao, nao por symlink nem home.file: o Claude Code
  # reescreve o arquivo em runtime (/model, por exemplo, grava o default nele),
  # entao ele precisa ser um arquivo regular escrivivel. A semantica de dono e:
  # a cada rebuild, o que esta versionado em home/.claude/settings.json vence.
  # Mudou algo em runtime e quer manter? Backporte pro arquivo do repo, senao o
  # proximo rebuild desfaz.
  #
  # As entradas dos hooks -axi ja vem GRAVADAS no arquivo versionado (mesmo
  # caminho absoluto que o `setup hooks` escreve), por dois motivos: a copia nao
  # depender da ativacao fmAxi pra ter um settings completo, e o `setup hooks`
  # reconhecer as entradas como suas e nao duplicar (idempotencia medida).
  #
  # O permissions.deny do settings versionado nao esta ali por seguranca, e sim
  # por CONTEXTO: negar uma ferramenta pelo nome remove o schema dela do system
  # prompt, nao so bloqueia a chamada. Medido em 31/jul/2026 neste repo, sessao
  # vazia, via `claude -p --output-format json` somando input+cache_creation+
  # cache_read: 25.8k tokens no baseline contra 16.4k com as tres negadas. O
  # mesmo numero sai do --disallowedTools, o que confirma que os dois caminhos
  # batem no mesmo lugar.
  #
  # Custo individual (isolado com --setting-sources project,local para tirar
  # este proprio deny da conta; base ~21.2k): Workflow 8208 tokens, Agent 1818,
  # ScheduleWakeup ~1500, ReportFindings ~1000. Workflow sozinha e a quase
  # totalidade do ganho — as outras entram por serem inuteis aqui, nao caras.
  #
  # O piso de ruido da medicao e 308 tokens: duas rodadas identicas de base
  # diferiram nisso, e negar um nome inventado (NomeFalsoXYZ123) deu o mesmo
  # numero que negar Artifact. Qualquer delta <= 308 aqui e ruido, nao ganho.
  #
  # Artifact fica no deny sem economia comprovada: ela nao existe no modo -p
  # (a sessao aninhada responde AUSENTE), que e a unica superficie que da pra
  # medir por script. Em sessao interativa ela provavelmente existe — o schema
  # tem disableArtifact/enableArtifact e as descricoes dos agentes a citam.
  # Manter e inofensivo; alegar economia por ela nao seria medido.
  #
  # Agent e ReportFindings ficaram de FORA do deny de proposito, custando seus
  # ~1.8k e ~1k: deny e mais forte que a regra escrita. O AGENTS.md pede para
  # nao usar subagente sem pedido explicito, mas com a ferramenta negada o
  # agente nao conseguiria nem quando pedido — e o isolamento de contexto de
  # uma varredura ampla (o subagente le 40 arquivos e devolve 10 linhas) vale
  # o preco em repo grande. ReportFindings e o que faz /code-review e
  # /security-review devolverem achados estruturados (arquivo, linha, veredito)
  # em vez de texto corrido; negar degradaria exatamente o output que se quer
  # ler. Regra de bolso: deny para o que nunca deve acontecer, AGENTS.md para
  # o que deve acontecer so sob pedido.
  #
  # Workflow continua negada mesmo tendo guardrail proprio: a descricao dela
  # exige opt-in explicito do usuario ("ultracode", pedido em palavras suas,
  # skill que mande chamar) e proibe disparo por decisao do modelo, mesmo em
  # tarefa que se beneficiaria de paralelismo. Mas guardrail e texto; as 8.2k
  # de schema sao cobradas em toda sessao, inclusive nas que nunca pediriam.
  #
  # Deny nao tem resgate DENTRO da sessao: o schema some, e ToolSearch so
  # alcanca ferramentas diferidas (as MCP, que por isso custam ~0). Medido:
  # `--allowedTools Workflow` nao vence o deny, da o mesmo numero. Para uma
  # sessao com tudo, sem perder modelo/hooks/statusline:
  #   claude --setting-sources project,local --settings <copia sem permissions>
  # Medido: 25.2k tokens, com o fable-5[1m] e os hooks -axi intactos.
  #
  # Reverter = apagar o bloco. Duas armadilhas medidas:
  #   - NAO trocar por `--tools`: passar --tools desliga o carregamento sob
  #     demanda das ferramentas MCP e elas entram inteiras no prompt
  #     (`--tools ""` deu 31.6k, PIOR que o baseline).
  #   - `--settings` SOMA ao deny daqui em vez de substituir. Para medir o
  #     custo de uma ferramenta ja negada, use --setting-sources project,local.
  #
  # O hook do herdr (SessionStart) fica declarado aqui, mas o script que ele
  # chama (~/.claude/hooks/herdr-agent-state.sh) NAO e versionado: o header diz
  # "managed by herdr; reinstalling or updating the integration overwrites this
  # file". Depois de um wipe o hook aponta pro vazio ate o herdr reinstalar a
  # integracao — inocuo, o Claude Code so loga a falha do hook.
  # A validacao de JSON antes do cp existe porque o modo de falha e assimetrico
  # e silencioso do lado que mais importa. Medido em 1/ago/2026: uma virgula
  # sobrando na lista do deny quebra o parse; em sessao interativa aparece
  # dialogo de erro, mas no `claude -p` o proprio --help documenta que
  # "Settings files that fail validation are silently ignored in this mode" —
  # ou seja, todo script que chama `claude -p` rodaria sem o deny e sem o
  # fable-5[1m], sem um unico aviso. Aconteceu uma vez, pega a mao.
  #
  # Aborta em vez de pular a copia: o `else` abaixo trata fonte AUSENTE, que e
  # legitimo (pos-wipe). JSON invalido e sempre erro de quem editou, e falhar
  # o rebuild na hora e melhor que descobrir tres dias depois num -p mudo.
  #
  # POR QUE COPIA E NAO SYMLINK, e por que isso nao briga com o CLAUDE.md logo
  # abaixo (que E symlink): o runtime ESCREVE neste arquivo — tema, estado de
  # TUI e os registros dos `setup hooks` dos -axi — e um alvo no /nix/store e
  # read-only, entao o primeiro write estouraria. O CLAUDE.md o runtime so le.
  # A regra unica e "o que o produto escreve nunca vira symlink de store"; o
  # bloco do CLAUDE.md tem a tabela completa.
  #
  # Corolario operacional: editar ~/.claude/settings.json a mao NAO persiste —
  # o proximo rebuild copia o versionado por cima, sem avisar. Mudanca que deve
  # durar vai em home/.claude/settings.json.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claudeSrc="${dotfiles}/home/.claude/settings.json"
    claudeDst="${config.home.homeDirectory}/.claude/settings.json"
    if [ -f "$claudeSrc" ]; then
      if ! ${pkgs.jq}/bin/jq -e . "$claudeSrc" >/dev/null 2>&1; then
        echo "claudeSettings: $claudeSrc nao e JSON valido. ABORTANDO o rebuild" >&2
        echo "  para nao propagar um settings quebrado (o claude -p o ignoraria" >&2
        echo "  em silencio). Erro do jq:" >&2
        ${pkgs.jq}/bin/jq -e . "$claudeSrc" >/dev/null || true
        exit 1
      fi
      $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/.claude"
      $DRY_RUN_CMD cp "$claudeSrc" "$claudeDst"
      $DRY_RUN_CMD chmod 644 "$claudeDst"
    else
      echo "claudeSettings: $claudeSrc nao existe; copia PULADA."
    fi
  '';

  # O statusline e um arquivo que o runtime NAO reescreve, entao aqui o idiom
  # normal de edit-in-place se aplica.
  home.file.".claude/statusline-command.sh".source =
    config.lib.file.mkOutOfStoreSymlink
      "${dotfiles}/home/.claude/statusline-command.sh";

  # ~/.claude/CLAUDE.md — memoria de usuario: um principio so (autonomia por
  # default), ~600 tokens, carregada em TODA sessao.
  #
  # POR QUE AQUI PODE SER SYMLINK E NO settings.json NAO PODE. Nao e
  # incoerencia: e a mesma regra — *o que o produto escreve nunca vira symlink
  # de store* — aplicada a dois arquivos com regimes de escrita diferentes.
  #
  #   settings.json  o RUNTIME ESCREVE nele: preferencia de tema, estado de TUI
  #                  e o que os `setup hooks` dos -axi registram. Symlink para o
  #                  store faria o primeiro write bater em read-only, entao ele
  #                  e COPIA — ver home.activation.claudeSettings acima, cujo
  #                  cabecalho tem o resto do racional.
  #   CLAUDE.md      o runtime so LE. Nenhum caminho do produto escreve na
  #                  memoria de usuario. Entao vale o idiom de edit-in-place,
  #                  igual ao statusline-command.sh logo acima — symlink desde
  #                  28/jul/2026, sem nenhum problema.
  #
  # A cadeia realizada tem tres saltos, e isso e o normal do home-manager:
  # ~/.claude/CLAUDE.md -> /nix/store/...-home-manager-files/.claude/CLAUDE.md
  # -> /nix/store/...-hm_claudemd -> o arquivo do repo. O statusline ja prova
  # que o Claude Code segue a cadeia inteira:
  #   readlink -f ~/.claude/statusline-command.sh
  #   # -> /Users/alex/Projects/dotfiles/home/.claude/statusline-command.sh
  #
  # QUAL LADO E O ARQUIVO REAL: o do repo. `CLAUDE.md` e o nome que o produto le
  # — testado em 27/ago/2026, e ele NAO le `~/.claude/AGENTS.md`, nem como
  # arquivo comum nem como symlink. Por isso o nome do consumidor fica no
  # destino e a fonte-da-verdade fica versionada em home/.claude/CLAUDE.md.
  #
  # Se voce criar ~/.claude/CLAUDE.md a mao antes do rebuild, o
  # home-manager.backupFileExtension = "hm-bak" do flake.nix move para
  # CLAUDE.md.hm-bak e cria o link — nao aborta.
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/CLAUDE.md";

  # O segundo link (convencao AGENTS.md de outras ferramentas) PODE ser
  # declarado aqui, sem activation script — o home-manager cria o diretorio pai.
  # Fica comentado de proposito: o Codex NAO esta instalado nesta maquina
  # (verificado em 27/ago/2026) e NAO foi verificado em que caminho ele le
  # instrucao global. Descomentar so depois de confirmar o caminho na doc da
  # ferramenta — symlink para path que ninguem le e mentira versionada.
  #
  # home.file.".codex/AGENTS.md".source =
  #   config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/CLAUDE.md";

  # A search list do Keychain, que e onde as cinco credenciais do broker sao
  # encontradas desde 02/ago/2026.
  #
  # Por que activation e nao home.file: isto nao e arquivo, e preferencia do
  # `security` (mora no plist do usuario e o proprio comando a reescreve). O que
  # da para declarar e a GARANTIA de que o chaveiro dedicado esta la.
  #
  # Sem esta lista o sintoma e cruel: `find-generic-password` nao acha item
  # nenhum, com o arquivo do chaveiro intacto no disco a dois centimetros do
  # processo que nao o enxerga. Era o unico estado manual que sobrava depois da
  # migracao, e um wipe o perdia em silencio.
  #
  # NAO cria o chaveiro: `create-keychain` pede senha, e activation nao e lugar
  # de dialogo. Se ele nao existir, avisa e sai — a criacao esta no checklist.
  # A logica mora num script do repo, nao aqui: heredoc e `set --` dentro de uma
  # string nix indentada sao um campo minado de escape, e um script de verdade se
  # testa a mao (`sh scripts/ensure-keychain-search-list.sh --dry-run`).
  home.activation.avKeychainSearchList = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x "${dotfiles}/scripts/ensure-keychain-search-list.sh" ]; then
      $DRY_RUN_CMD /bin/sh "${dotfiles}/scripts/ensure-keychain-search-list.sh"
    else
      echo "avKeychainSearchList: script ausente em ${dotfiles}/scripts; PULADO."
    fi
  '';
}
