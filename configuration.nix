{ user, pkgs, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
    # Chaves SSH aceitas por este Mac. UMA POR APARELHO, nunca compartilhada:
    # e isso que torna a revogacao cirurgica — apagar a linha e rebuildar mata o
    # acesso daquele aparelho e so dele, sem tocar nos outros.
    #
    # Chave PUBLICA nao e segredo por si so (o GitHub publica as de todo mundo
    # em github.com/<user>.keys por desenho), mas ela CORRELACIONA um aparelho
    # concreto a este host — por isso nesta copia publica ficou so o formato.
    # A privada NUNCA vem para ca, e a regra vale mesmo com repo privado:
    # privado ainda e clonado para outras maquinas, entra em backup e vira
    # publico com um clique.
    # Perdeu? Gere outra e troque a linha; o custo de reposicao e zero.
    #
    # O nix-darwin escreve isto em /etc/ssh/nix_authorized_keys.d/<user>, lido
    # pelo AuthorizedKeysCommand de /etc/ssh/sshd_config.d/101-authorized-keys.conf.
    # Nao usa ~/.ssh/authorized_keys de proposito: config de seguranca mora em
    # git e passa por revisao (item 7.2), em vez de acumular num arquivo solto.
    openssh.authorizedKeys.keys = [
      # Uma linha por aparelho, com comentario dizendo QUAL aparelho e quando
      # a chave nasceu — e isso que torna a revogacao cirurgica.
      # Ex.: gere no proprio aparelho e cole a publica aqui:
      # "ssh-ed25519 AAAA...SUA-CHAVE-PUBLICA... iphone"
    ];
  };
  system.stateVersion = 6;

  # Item 2.3 do checklist: Touch ID para sudo. Declarado aqui em vez de copiar
  # /etc/pam.d/sudo_local.template na mao — o nix-darwin e dono desse arquivo e
  # aborta a ativacao se encontrar conteudo que nao gerou.
  security.pam.services.sudo_local.touchIdAuth = true;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      # Unidade dos dois: ticks de 15ms. Historico: ate 11/ago/2026 isto estava
      # em KeyRepeat=1 / InitialKeyRepeat=10 (~66 char/s), abaixo do que o
      # slider dos Ajustes do Sistema permite, e disparava caracteres repetidos
      # em digitacao normal. O teto do slider (2 / 15) ainda ficou rapido
      # demais na pratica, entao voltamos ao padrao de fabrica do macOS.
      KeyRepeat = 6;          # 90ms entre repeticoes (~11 char/s)
      InitialKeyRepeat = 25;  # 375ms antes de comecar a repetir
      # Sem isso o padrao do macOS e `true`: segurar tecla abre o menu de
      # acentos em vez de repetir, em todo app que usa o input de texto do
      # Cocoa (navegador, Electron, nativos). As duas chaves acima so mandam
      # na VELOCIDADE da repeticao — quem a LIGA nesses apps e esta.
      ApplePressAndHoldEnabled = false;
      _HIHideMenuBar = false;  # barra de menus sempre visivel
      AppleShowAllExtensions = true;
    };
    dock.autohide = false;  # Dock sempre visivel, sem esconder
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click

    # A janela que o macOS restaura no login (opcao "reabrir janelas") nasce
    # com o skin padrao do WezTerm: ela e recriada pelo NSWindow restoration
    # antes do config de aparencia se aplicar aquela janela. Janelas novas ja
    # vem certas. Desligar a restauracao SO do WezTerm (bundle id abaixo) faz o
    # macOS parar de recriar a janela crua; abrir o app a mao nasce com o skin
    # certo. Cirurgico — os outros apps seguem reabrindo no login.
    CustomUserPreferences."com.github.wez.wezterm".NSQuitAlwaysKeepsWindows = false;

    # Editor de Texto como bloco de notas puro: sem barra de formatacao, sem
    # regua, sem substituicao esperta. Nao existe versao "simplificada" do app —
    # quem some com a barra e a regua e o formato do DOCUMENTO ser texto simples,
    # entao a chave que manda e RichText. Vale so para documentos NOVOS; um .rtf
    # aberto continua rich text (converter com Shift-Cmd-T).
    CustomUserPreferences."com.apple.TextEdit" = {
      RichText = 0;                      # documentos novos nascem texto simples
      ShowRuler = 0;                     # regua off mesmo ao abrir um .rtf
      SmartQuotes = 0;                   # aspas/travessoes curvos off
      SmartDashes = 0;
      CorrectSpellingAutomatically = 0;  # sem autocorrecao
    };
  };
  # Nada de dormir por inatividade. Este Mac mini vinha com `sleep 1` (um minuto
  # ocioso ja derrubava a maquina), o que mata sessao SSH/Tailscale, rebuild
  # longo e qualquer coisa rodando sem ninguem na frente. O modulo traduz isso
  # para `systemsetup -setComputerSleep never` na ativacao.
  #
  # Sono do DISPLAY fica de fora de proposito: apagar a tela nao suspende a
  # maquina e continua economizando. Se um dia isso tambem precisar sumir, use
  # `power.sleep.display = "never"`.
  power.sleep.computer = "never";
  power.sleep.harddisk = "never";  # sem isso o disco ainda estaciona aos 10min
  # Religa sozinho apos queda de energia (pmset autorestart, vinha 0). Este Mac
  # roda sem ninguem na frente (SSH/Tailscale/rebuilds), entao voltar sozinho e
  # o comportamento desejado.
  power.restartAfterPowerFailure = true;

  # Tailscale como daemon de SISTEMA, e nao como app.
  #
  # A doc oficial (tailscale.com/kb/1065) e explicita: das tres variantes de
  # macOS, SO a CLI open source sobe ANTES do login. A da App Store e sandboxed
  # e nao sobe; a standalone precisa de sessao grafica. Num Mac mini que existe
  # para ser alcancado remotamente isso e requisito, nao preferencia. O preco
  # que a Tailscale declara para essa variante — sem GUI, sem MDM, Taildrop
  # parcial, so ANUNCIA exit node em vez de usar — nao custa nada neste uso.
  #
  # Instalar o app tambem colidiria com esta maquina: cask nao declarado morre
  # no `zap`, e as stanzas `zap` de cask pedem Full Disk Access, que e proibicao
  # dura aqui (ver AGENTS.md e docs/reinstall-checklist.md item 2.2).
  #
  # Isto TRADUZ `sudo brew services start tailscale` — o metodo oficial da wiki
  # da Tailscale para o Homebrew — em launchd declarado: mesmo launchd, mesma
  # binaria (a formula ja esta em homebrew.brews), so que versionado e revertido
  # por rebuild em vez de virar estado solto fora do git (item 7.2). A formula
  # so faz `run tailscaled` como root com keep_alive; o --state e explicito de
  # proposito, para o arquivo dizer onde mora a identidade deste no em vez de
  # depender do default calculado para o usuario que roda.
  #
  # NAO habilita exit node, subnet router, funnel, serve nem Tailscale SSH: o
  # acesso remoto e o OpenSSH nativo do macOS correndo SOBRE a rede Tailscale.
  launchd.daemons.tailscaled = {
    serviceConfig = {
      ProgramArguments = [
        "/opt/homebrew/bin/tailscaled"
        "--state=/var/lib/tailscale/tailscaled.state"
        "--socket=/var/run/tailscaled.socket"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/tailscaled.log";
      StandardErrorPath = "/var/log/tailscaled.log";
    };
  };

  # NAO existe mais LaunchAgent do av-broker aqui, e a ausencia e proposital.
  #
  # Ate 18/ago/2026 este bloco declarava `av-broker-agent`: um processo que
  # segurava a chave privada do GitHub App em RAM e servia cunhagens por socket
  # unix 0600, para que a senha do Keychain fosse cobrada uma vez por vida do
  # processo em vez de uma por leitura da chave (28 senhas num dia, medido em
  # 02/ago/2026). Ele subia com `--lazy-key` para nao abrir dialogo no login, e
  # com KeepAlive so em saida limpa para que o ciclo ociosidade->morte->recriacao
  # descartasse a chave de um jeito que o Python nao consegue com `str`.
  #
  # Ele existia INTEIRAMENTE para o GitHub — `_agent_handle` so conhecia a op de
  # cunhar token de instalacao. Com o GitHub migrado para PAT de vida longa no
  # keychain (scripts/gh-token.sh), o agente ficou sem nenhum chamador e foi
  # removido junto com o alvo `github` do broker. Se algum dia Shopify ou GCP
  # precisarem do mesmo truque, isto volta — mas volta para eles, com o handler
  # deles, e nao ressuscitado deste comentario.

  # Conserta o MagicDNS na variante CLI do Tailscale.
  #
  # Medido em 31/jul/2026: o tailscaled cria /etc/resolver/search.tailscale (so
  # o dominio de BUSCA) e NAO cria o resolver do sufixo. Resultado: o macOS
  # pergunta *.ts.net ao DNS do roteador, que responde NXDOMAIN, e `ping
  # meu-mac.SUA-TAILNET.ts.net` falha — enquanto
  # `nslookup <nome> 100.100.100.100` responde certo. Ou seja, o resolvedor do
  # Tailscale esta no ar; o que faltava era o macOS ser mandado ate ele.
  #
  # Isto so afeta consultas terminadas no sufixo da tailnet. Se o Tailscale
  # estiver fora, elas falham — que e exatamente o que ja acontecia. O DNS do
  # resto do sistema nao e tocado.
  #
  # O sufixo e fixo de proposito: se a tailnet for renomeada isto para de
  # resolver (falha fechada e obvia), em vez de apontar para lugar nenhum.
  #
  # TROQUE `SUA-TAILNET` pelo sufixo real da sua tailnet (`tailscale status
  # --json | jq -r .MagicDNSSuffix`). O nome esta parametrizado aqui porque o
  # sufixo identifica a sua rede privada.
  environment.etc."resolver/SUA-TAILNET.ts.net".text = ''
    # Gerado pelo nix-darwin (configuration.nix), nao pelo tailscaled.
    nameserver 100.100.100.100
  '';

  nix-homebrew = {
    enable = true;
    inherit user;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.upgrade = true;   # sem isto o rebuild instala mas nao ATUALIZA:
                                   # claude-code@latest (e os demais) congelariam
                                   # na versao instalada ate um `brew upgrade`
                                   # manual. Default: false.
    onActivation.extraFlags = [ "--force" ];
    taps = [
      "anomalyco/tap"
      "automic-vault/isotopes"
      "geronimo-iia/tap"
      "twilio/brew"
    ];
    brews = [
      "herdr"
      # Migrated from the pre-nix-homebrew installation (top-level formulae only;
      # transitive deps come back automatically).
      "age"
      # bitwarden-cli removido: o gerenciador de segredos passa a ser o
      # automic-vault (item 3.3/3.4 do checklist). Com cleanup = "zap" a
      # remocao daqui ja desinstala no proximo switch.
      "composer"
      "ffmpeg"
      # gh saiu daqui em 02/ago/2026 e foi para `home.packages` (nixpkgs).
      # Ele vinha do tap da Automic Vault por um motivo unico: `av harden gh`
      # so entrega o token para uma binaria de hash conhecido, e so da pra
      # atestar o hash de uma que ELES distribuam. Com o harden aposentado
      # (item 3.4 do checklist) sobrava so o custo — um rebuild de terceiro do
      # `gh`, assinado por `Developer ID Application: Max Howell (ZU76A67LGU)`,
      # um individuo, sem versao presa a lock nenhum.
      # Nao reintroduza sem reintroduzir o harden junto; e `conflicts_with "gh"`,
      # entao voltar exige tirar o do nixpkgs no mesmo commit.
      "git-filter-repo"
      "pandoc"
      "poppler"
      "rclone"
      "shellcheck"
      "smartmontools"
      "sshpass"
      "tailscale"
      "anomalyco/tap/opencode"
      "geronimo-iia/tap/llm-wiki"
      "twilio/brew/twilio"
    ];
    casks = [
      "wezterm"
      # Canal "latest" do Claude Code: o cask claude-code@latest segue o release
      # `latest` (livecheck em .../latest, hoje 2.1.220), enquanto o cask
      # "claude-code" segue o `stable`, que atrasa. Instalacoes por Homebrew NAO
      # se auto-atualizam — o self-updater do Claude Code so age em install nativo
      # — entao o binario nao deriva por baixo do brew, o que elimina o conflito
      # "already a Binary at /opt/homebrew/bin/claude" que fez a stanza `zap` do
      # cask mandar ~/.claude.json e o binario pra Lixeira. Garantia extra:
      # DISABLE_AUTOUPDATER=1 no home.nix. Seguir o latest ao longo do tempo
      # depende de onActivation.upgrade (acima) — a versao e fixada na formula e
      # sobe quando os mantenedores bumpam. NUNCA rodar o installer nativo junto.
      "claude-code@latest"
      # LuLu REMOVIDO em 29/jul/2026 (decisao do item 7.1, a partir de
      # research/egress.md). Nao e a camada de egress do agente: filtra por
      # processo do host (NEFilterDataProvider) e o NAT do vmnet acontece no
      # kernel, entao o trafego de dentro da microVM nunca aparece para ele.
      # Little Snitch 6 tambem descartado — mesma cegueira, e pago. O controle
      # real e o proxy default-deny + anchor de pf (itens 7.2/7.3 do checklist).
      # NAO reintroduzir aqui sem antes reabrir o item 7.1.
      # Item 3.4: guarda os segredos mestres no host e e o gate para derivar
      # credencial efemera. Declarado pelo tap oficial em vez do install.sh —
      # o curl|sh nao e reproduzivel nem sobrevive a um wipe.
      # Ele instala um stub root em /usr/local/bin na etapa de hardening (que e
      # feita pela GUI do app, nao pelo cask).
      "automic-vault/isotopes/automic-vault"
      # FASE 6, item 6.7 (ver docs/arquitetura-navegadores.md).
      # ATENCAO — premissa corrigida em 28/jul/2026: NAO ha protecao de TCC sobre
      # ~/Library/CloudStorage. Medido com o Drive montado: o terminal sem FDA e
      # sem "Arquivos e Pastas" lista Meu Drive e Drives compartilhados e le
      # conteudo de arquivo (com ~/Documents bloqueado no mesmo teste, como
      # controle). Ou seja: qualquer processo rodando como alex — inclusive um
      # agente no host — alcanca o Drive inteiro, para ler E para escrever.
      # Risco ACEITO conscientemente (decisao de 29/jul/2026): o Claude Code roda
      # no host apenas para tarefas curtas e sob supervisao. Trabalho longo ou
      # nao supervisionado vai para o container da FASE 5, que e o unico
      # mecanismo que separa o agente do Drive.
      # O cask instala um .pkg (pede admin) e o app registra uma extensao de File
      # Provider. O que o Nix NAO reproduz e ficam como passos manuais no
      # checklist: login (so a conta pessoal), modo "stream" em vez de "mirror",
      # e NAO ativar o backup de Mesa/Documentos/Downloads.
      "google-drive"
      # Chrome Remote Desktop (acesso grafico remoto), adicionado em 01/ago/2026
      # a pedido explicito. Isto REVERTE duas decisoes documentadas, e o arquivo
      # diz isso em vez de fingir que nao:
      #
      #  - docs/arquitetura-navegadores.md §4 registrava "Chrome nao instalado"
      #    como a zona de maior risco simplesmente nao existir. Agora existe. A
      #    regra que sobra e mais fraca porque depende de disciplina, nao do
      #    kernel: o Chrome e SO para o console do CRD. Vida pessoal continua no
      #    Safari (dentro do TCC); nenhuma outra conta, senha ou extensao aqui.
      #  - o inventario privado de acesso remoto §11 registrava "sem acesso grafico de
      #    emergencia" como decisao explicita. O SSH sobre Tailscale nao sai da
      #    LAN/tailnet; o CRD passa pela infra da Google, entao a superficie e
      #    outra e maior. Quem tiver a conta Google + o PIN entra com teclado e
      #    mouse nesta maquina. Por isso: 2FA na conta e PIN nao reutilizado.
      #
      # O cask e um .pkg que roda `installer` como root. `brew install` a mao
      # falha ("a terminal is required to read the password"); por aqui funciona
      # porque o rebuild.sh ja executa o darwin-rebuild inteiro sob sudo.
      #
      # O que o Nix NAO reproduz, e fica manual: (1) logout/login para o host
      # subir, (2) os grants de Gravacao de Tela e Acessibilidade para
      # "Chrome Remote Desktop Host" — sem eles a sessao abre em tela preta ou
      # ignora teclado/mouse, (3) o PIN em remotedesktop.google.com/access.
      # Nenhum dos tres e FDA nem Files & Folders, entao a regra 1 do §3 daquele
      # doc continua de pe.
      #
      # Para desfazer: apagar estas duas linhas e rodar ./rebuild.sh — com
      # onActivation.cleanup = "zap" isso desinstala de verdade. O PIN e a
      # autorizacao do host morem na conta Google e precisam ser revogados la
      # (remotedesktop.google.com → remover este computador).
      "google-chrome"
      "chrome-remote-desktop-host"
      # Ditado por voz local (https://opensuperwhisper.com), pedido em
      # 03/ago/2026. Vem do homebrew-cask oficial, nao de um tap de terceiro:
      # nixpkgs nao empacota este app (`nix search` vazio), e o cask hoje esta
      # na 0.1.0, que E o ultimo release do upstream (starmel/OpenSuperWhisper,
      # 03/mar/2026) — quando bumparem, onActivation.upgrade sobe sozinho.
      # Requisitos do cask: arm64 e macOS >= 14 (esta maquina: arm64, 26.5).
      #
      # A transcricao roda LOCAL (whisper.cpp / Parakeet), sem API key. A unica
      # rede e o download do modelo pelo proprio app, do Hugging Face, na
      # primeira execucao — nao e reproduzivel pelo Nix e nao esta versionado
      # aqui; se o objetivo for uma maquina que se reconstroi offline, o modelo
      # e um passo manual.
      #
      # O que o Nix NAO reproduz, e fica manual: (1) o grant de Microfone,
      # (2) o grant de Acessibilidade — o app le atalho global e escreve o texto
      # na janela em foco, e sem isso ele grava mas nao entrega nada, (3) a
      # escolha do modelo e do atalho global nas Preferencias.
      #
      # Nota de superficie, para nao passar batido: e um processo do host com o
      # microfone aberto e permissao de injetar/ler teclado. Isso e mais amplo
      # que qualquer app ja listado aqui, e o proxy default-deny dos itens
      # 7.2/7.3 nao cobre nada disso (o risco nao e egress, e captura local).
      # Aceito por ser ferramenta de ditado do usuario, em app open source.
      "opensuperwhisper"
      # Migrated from the pre-nix-homebrew installation.
      "unnaturalscrollwheels"
    ];
  };
}
