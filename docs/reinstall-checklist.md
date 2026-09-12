# Checklist de reinstalação segura — macOS (Mac M4, 24 GB)

Gerado em 2026-07-27. Desenho-alvo: **sem VMs UTM**, agentes em **microVMs shuru**
(revisão de 29/jul/2026 — antes: containers Apple), segredos mestres no
**automic-vault** no host, navegação pessoal isolada por TCC.

Cada item foi derivado de uma medição feita na máquina atual, não de um template.

---

## ⚠️ FASE 0 — Antes de apagar (irreversível depois)

Ordenado por "perde dado se pular".

- [x] **0.1 — FEITO em 2026-07-27: commit `f73780d` salvo.**
  `~/Projects/dotfiles` é clone de `kunchenguid/dotfiles` (upstream do Kun Chen), e o
  commit da migração nix-homebrew existia **só no disco**. Agora há um remote próprio:
  - `meu`    → `github.com/SEU-USUARIO/dotfiles` (privado) — **empurre aqui**
  - `origin` → `github.com/kunchenguid/dotfiles` — mantido só para puxar upstream

  Antes do wipe, reconfirme que nada ficou para trás (tem que sair vazio):
  ```sh
  git -C ~/Projects/dotfiles log meu/main..HEAD --oneline
  ```
  Na máquina nova, clone de `meu`, não de `origin`.

- [ ] **0.2 — Revogar o PAT `GH_PAT_TOKEN_ALEX`.** Vazou em transcript e está em
  `~/Projects/.env`. Revogar em github.com/settings/tokens.

  ⚠️ **Corrigido em 18/ago/2026.** A versão anterior deste item dizia "**não
  gere substituto** — o acesso vem de token de instalação do GitHub App" e que
  "isto vale para todo token pessoal do GitHub". **Isso é falso desde
  18/ago/2026.** A máquina voltou a ter token pessoal do GitHub: **dois PATs
  fine-grained de vida longa** (`github-pat` e `github-pat-vm`), item 3.2. A
  troca não foi ganho de segurança — foi ergonomia comprada com segurança, e o
  ADR §6.6 registra o preço.

  O que **continua** valendo deste item, e é o ponto que importa:
  - o token vazado é revogado, não reciclado;
  - o novo PAT **nasce na UI do GitHub e vai direto para o keychain**, nunca
    para `~/Projects/.env`, nunca para `~/.config/gh/hosts.yml`, nunca para
    variável em arquivo versionado. Uma cópia, um lugar;
  - o token que o `av harden gh` guardou no vault até 02/ago/2026 **não** tem
    substituto: aquele era um token de OAuth device flow do `gh auth login`, e
    `gh auth login` continua proibido nesta máquina (3.2).

- [ ] **0.3 — Auditar todos os repos por trabalho não-pushado:**
  ```sh
  for d in ~/Projects/*/ ~/Projects/checkouts/*/; do
    [ -d "$d/.git" ] || continue
    n=$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
    s=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" != 0 ] || [ "$s" != 0 ] && printf "%-42s %3s nao-pushados  %3s sujos\n" "$(basename "$d")" "$n" "$s"
  done
  ```

- [ ] **0.4 — Segredos dos 30 `.env` → gerenciador de senhas** (não para outro arquivo):
  ```sh
  find ~/Projects -maxdepth 3 -name ".env" ! -name "*.example" 2>/dev/null
  ```
  Inclui `google-contacts-sf-sync/.secrets/sf_jwt_private.pem`.

- [ ] **0.5 — Revogar as credenciais da máquina velha.** As 5 chaves SSH estão **sem
  passphrase**; remova as públicas de GitHub, GCP (`google_compute_engine`), locaweb,
  e outros vaults de projeto. **Não migre nenhuma delas.**

- [ ] **0.6 — OneDrive (Ministério da Gestão): confirmar sync completo** pela interface
  do OneDrive antes do wipe. Dado de terceiro — trate como não-negociável.

- [ ] **0.7 — Google Drive: mesma verificação.**

- [ ] **0.8 — Exportar favoritos do navegador.** Senhas vão para o gerenciador,
  **nunca** para um arquivo exportado.

- [ ] **0.9 — NÃO fazer backup de:** `~/.claude/projects` (263 MB, 664 transcripts com
  segredos ecoados), `~/.zsh_history`, `~/.config/gcloud`, `~/.codex`, os ~20 perfis
  Chrome. A quebra de continuidade é o objetivo, não um efeito colateral.

- [ ] **0.10 — Anotar quais das 17 LaunchAgents recriar** (`ls ~/Library/LaunchAgents`).
  Várias são órfãs: VirtualBox, auto-morning, utm-autostart.

---

## 🔥 FASE 1 — Instalação

- [ ] **1.1 — NÃO usar o Assistente de Migração.** Ele recria exatamente o acúmulo que
  você quer deixar para trás: grants de TCC, chaveiro, perfis, históricos.
- [ ] **1.2 — Apagar Todo o Conteúdo e Ajustes**, ou Recuperação → apagar disco → reinstalar.
- [ ] **1.3 — Primeira conta = `admin`.** Senha forte e única. **Não é a conta de uso diário.**
- [ ] **1.4 — FileVault ligado.** Chave de recuperação no gerenciador de senhas.
- [ ] **1.5 — Criar `alex` como usuário Padrão (não-administrador).** É o que impede um
  agente ou instalador de escalar privilégio sozinho.
- [ ] **1.6 — Fechar os homes:**
  ```sh
  sudo chmod 700 /Users/alex /Users/admin
  ```
  O padrão do macOS é `750` grupo `staff`, e **todo usuário local nasce em `staff`** —
  sem isso, as contas se leem e a separação é decorativa.

---

## 🛡️ FASE 2 — Base de segurança (antes de qualquer ferramenta de dev)

- [ ] **2.1 — Firewall + stealth:**
  ```sh
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
  ```

- [ ] **2.2 — A regra que mais se paga: nunca conceder Full Disk Access a terminal nenhum.**
  Nem Terminal, nem iTerm2, nem wezterm, nem VS Code. Se um app pedir, negue.
  ⚠️ **O pedido mais convincente vem de dentro do seu próprio fluxo:** o
  `darwin-rebuild` imprime *"Unable to remove some files. Please enable Full Disk
  Access for your terminal"* toda vez que o `zap` de um cask mira
  `~/Library/Application Support/com.apple.sharedfilelist` (protegido por TCC).
  A mensagem é do Homebrew, não do macOS, e **a resposta é não** — o conserto é
  manual: apague o app de `/Applications` e depois
  `rm -rf /opt/homebrew/Caskroom/<cask>`. Ver `AGENTS.md`.
  Na máquina atual isso estava concedido e anulava sozinho a proteção de Safari, Mail
  e Messages. É um clique que você simplesmente não dá.
  📌 Correção de 28/jul/2026: `~/Library/CloudStorage` **não** entra nessa lista —
  medindo com o Drive montado, não há proteção de TCC ali para o FDA anular
  (ver 6.7).

- [x] **2.3 — Touch ID para `sudo`: DECLARATIVO desde 29/jul/2026** (Fase 0 do
  `docs/plano-adocao-tokens.md`). Vem de
  `security.pam.services.sudo_local.touchIdAuth = true` no `configuration.nix` —
  o `darwin-rebuild switch` da FASE 4 já o aplica. **Não** copie
  `/etc/pam.d/sudo_local.template` na mão: o nix-darwin é dono desse arquivo e
  aborta a ativação se encontrar conteúdo que não gerou. Verificar:
  ```sh
  grep pam_tid.so /etc/pam.d/sudo_local   # deve existir após o rebuild
  ```
  ⚠️ **Inócuo neste hardware, medido em 29/jul/2026.** O Mac mini M4 não tem
  sensor biométrico e a decisão foi **não** comprar um Magic Keyboard: o
  `pam_tid.so` fica declarado e nunca dispara. Mantido porque passa a valer
  sozinho no dia em que um teclado biométrico chegar — e porque o custo de
  declarar é zero. O portão de aprovação que **de fato** protege as cunhagens do
  broker é o **diálogo nativo do macOS** (`gui`), não a biometria; a tabela de
  resistência dos três portões está no ADR `arquitetura-segredos.md` §6.5.

- [ ] **2.4 — Atualizações automáticas ligadas.**
- [ ] **2.5 — Não desabilitar SIP nem Gatekeeper.** Nada neste plano exige.

---

## 🔑 FASE 3 — Identidade

- [ ] **3.1 — Chaves SSH novas, com passphrase**, uma por destino:
  ```sh
  ssh-keygen -t ed25519 -C "alex@mac-2026" -f ~/.ssh/id_ed25519
  ssh-add --apple-use-keychain ~/.ssh/id_ed25519
  ```
  E no `~/.ssh/config`:
  ```
  Host *
    UseKeychain yes
    AddKeysToAgent yes
  ```

- [ ] **3.2 — Dois PATs fine-grained no keychain; `gh auth login` continua
  proibido.** Reescrito em **18/ago/2026**. Este item já teve três versões: (1)
  device flow com o token no vault, (2) token de instalação de GitHub App
  cunhado pelo `av-broker` com TTL de 1 h — decidida em 02/ago/2026 —, e (3) a
  atual. As duas primeiras estão registradas no ADR (`arquitetura-segredos.md`
  §6.1 e §6.6) e no plano de adoção; aqui fica só o que você faz na máquina
  nova.

  ⚠️ **Diga-se sem eufemismo:** a versão (3) é **menos segura** que a (2). Ela
  troca credencial efêmera, escopada por repositório e gateada por um gesto
  humano por **dois tokens de vida longa que qualquer processo seu lê sem
  diálogo**. O motivo foi custo humano medido — 582 diálogos do Automic Vault em
  24 h e 28 senhas do Keychain no mesmo dia (02/ago/2026), somados a um token que
  morria em 1 h no meio do trabalho. Não reintroduza a (2) sem reler §6.6.

  **São dois tokens, de propósito:**

  | Item do keychain | Vive | Quem lê | Escopo |
  | --- | --- | --- | --- |
  | `github-pat` | login keychain do Mac | `scripts/gh-token.sh` (o `gh` do PATH) via `scripts/gh-pat.sh` | o que o seu trabalho no host exigir |
  | `github-pat-vm` | login keychain do Mac | `scripts/claude-shuru`, que o monta em `/ghcred/token` dentro do guest | **o menor dos dois** — qualquer código que rode na VM o lê |

  Um token por lugar é a única forma de saber **qual cópia vazou** e revogar só
  ela. Não unifique.

  **Roteiro, na máquina nova:**

  1. Criar os dois tokens em
     <https://github.com/settings/personal-access-tokens> → *Generate new token*
     (fine-grained, não o clássico). Para cada um:
     - **Resource owner**: sua conta.
     - **Repository access**: *Only select repositories* — nunca *All*, que
       concede também aos repos que ainda não existem.
     - **Permissions**: o piso que o trabalho exige. O teto que o App tinha era
       `contents`, `pull_requests`, `metadata` (e, na prática, `checks`,
       `actions`, `issues`); use isso como referência, não como obrigação.
       O de VM deve ser **estritamente menor**: se a VM só abre PR, ela não
       precisa de `administration`.
     - **Expiration**: escolha uma data e **anote-a**. Nada nesta máquina vai
       lembrar por você (o `av-broker rotate --target github` não existe mais).
     - Nomeie de forma que a lista da UI diga onde cada um vive — p.ex.
       `mac-host` e `shuru-vm`. Você vai reler essa lista na revisão trimestral.
  2. Gravar cada um no keychain, colando no prompt (o token **não** aparece na
     tela e **não** vai para o histórico do shell, porque não é argumento):
     ```sh
     gh-pat set host    # cole o PAT do Mac      -> item github-pat
     gh-pat set vm      # cole o PAT da VM       -> item github-pat-vm
     ```
     O `gh-pat` valida o prefixo (`github_pat_` / `ghp_`) antes de gravar, e usa
     `-U`, então regravar em cima é a forma normal de rotacionar.
  3. Conferir, sem imprimir valor nenhum:
     ```sh
     gh-pat check       # as duas linhas devem dizer "presente"
     ```
  4. Fechar o laço com um comando de verdade:
     ```sh
     gh api user --jq .login        # deve responder seu login
     gh repo list --limit 3         # só funciona porque agora é token de conta
     ```

  **Por que os itens ficam no `login` keychain, e não no `av-broker.keychain`.**
  Porque o portão não existiria de qualquer jeito. A ACL vazia (`-T ""`) que
  protege as chaves do broker **não funciona com o chaveiro destrancado**, e o
  Automic Vault destranca o chaveiro (medido). Pôr o PAT num chaveiro dedicado
  com `-T ""` daria a *aparência* de portão sem o portão — pior do que assumir,
  como aqui se assume, que **qualquer processo seu lê o PAT sem diálogo**.

  **O wrapper.** `scripts/gh-token.sh` é instalado como `~/.local/bin/gh` pelo
  `home.nix` e posto **à frente** do Homebrew no PATH pelo `initContent` do zsh.
  O prepend tem que ficar ali e não em `home.sessionPath`: aquilo escreve no
  `~/.zshenv`, e o `/etc/zshrc` roda depois com `eval "$(brew shellenv)"`, que
  reprepende `/opt/homebrew/bin` incondicionalmente. O wrapper lê o PAT a cada
  invocação e o injeta por **ambiente** (`GH_TOKEN`/`GITHUB_TOKEN`), nunca por
  `argv`, que o `ps` de qualquer processo seu leria. `scripts/gh-pat.sh` é
  symlinkado como `~/.local/bin/gh-pat` pelo mesmo `home.nix`.

  **`gh auth login|refresh|logout|switch|setup-git` continua bloqueado pelo
  wrapper**, e vale entender por quê, porque o motivo mudou: antes o problema era
  *criar* um token pessoal de longa duração; agora o token pessoal **é** o
  arranjo, e o problema virou a **segunda cópia**. O login grava `oauth_token`
  em texto puro em `~/.config/gh/hosts.yml`, e a partir daí existem dois segredos
  vivos com o mesmo poder: um no keychain, que você sabe rotacionar, e um em
  disco, que você vai esquecer.

  **O que a versão (2) fazia e não existe mais** — anotado para você não procurar:
  `scripts/gh-broker.sh` (descoberta de repo, classificação read/write, permissão
  por comando, cache de leitura de 45 min, cache negativo de 24 h), o alvo
  `github` do `av-broker`, o agente launchd `av-broker-agent` que segurava a
  chave em RAM, `av-broker review`, `av-broker rotate --target github`,
  `scripts/finish-github-app.sh` e `broker/dev/make-dev-key.sh`. **Shopify, GCP e
  Salesforce continuam no broker, com credencial efêmera e portão** — o `av-broker
  --help` lista `gcp`, `salesforce`, `session`, `log`, `doctor`, `rotate`.

  **Por que o `gh` saiu do Secret Gate do automic-vault (02/ago/2026), e por que
  a saída continua valendo.** O Secret Gate do `gh` cobrava **um diálogo
  por invocação**: 582 em 24 h, medidos no unified log do `AutomicVaultMenubar`,
  chegando de 20 em 20 s em horário de trabalho. Não é questão de ajustar o
  nível — o gate já estava em *Trusted Access*. O AV atribui o pedido ao primeiro
  app **verificado** subindo a árvore de processos, e em todo caminho real desta
  máquina esse app é o **Claude Code**, que é **inelegível por assinatura**:
  `com.apple.security.cs.disable-library-validation` (mais
  `allow-unsigned-executable-memory` e `allow-jit`). A recusa do AV é correta e
  não tem contorno do nosso lado. Override de *Trusted Access* no **WezTerm**
  também não resolve, e foi tentado: o `herdr server` tem **PPID 1**, então o
  WezTerm sai da árvore de processos de toda shell.

  **Pré-requisito deste item:** só os dois PATs do roteiro acima. Não há mais
  GitHub App, nem chave privada, nem item `av-broker-github` no Keychain.

  **A segunda fricção, resolvida por remoção (histórico de 02–18/ago/2026).**
  Matar os diálogos do AV fez a senha do **Keychain** virar o gargalo: o item
  `av-broker-github` tinha ACL vazia (`-T ""`) num chaveiro dedicado, e o macOS
  autorizava a **cada leitura** da chave (~4,7 s) — **28 senhas em 02/ago/2026**,
  contadas no `mints.jsonl`. Três camadas foram construídas para derrubar isso
  (cache de leitura de 45 min, cache negativo de 24 h e o LaunchAgent
  `av-broker-agent` segurando a chave em RAM). **As três foram removidas em
  18/ago/2026 junto com o que elas serviam.** Um PAT no login keychain não pede
  senha nenhuma — e é exatamente por isso que ele é menos seguro. Se um dia o
  GitHub App voltar, essa engenharia volta com ele; até lá, não a procure no
  `configuration.nix`.

  **O guard-rail contra impressão de segredo.** O hook
  `scripts/hooks/deny-keychain-read.py` barra comandos de shell cujo produto é um
  segredo: `security find-*-password ... -w` e `security dump-keychain -d`. Ele
  existe porque em 02/ago/2026 um agente rodou `... -w 2>&1 >/dev/null | head`
  achando que descartava a saída — a ordem faz o oposto, e a chave privada do App
  foi impressa inteira no transcript (revogada e rotacionada no mesmo dia).

  **A segunda regra, `av-broker --emit`.** Na noite do mesmo dia o mesmo agente
  mandou `av-broker salesforce --emit json | tail -25` e imprimiu um access token
  vivo da sandbox — a regra anterior não pegava, porque ali imprimir o segredo é o
  propósito declarado do comando. O critério, então, não é o comando: é o
  **destino** da saída. Capturada (`$(...)`, crase, `> arquivo`) vai para quem vai
  usar e passa; solta ou canalizada vai para o stdout da ferramenta, ou seja, para
  o transcript, e é bloqueada. Os fluxos legítimos — o
  `av-broker shopify --emit token` capturado em variável e
  os `shuru.json` dos projetos — continuam intactos, e há teste para cada um. Para
  só *testar* se a cunhagem funciona, sem tocar no segredo:
  ```sh
  av-broker salesforce --emit json >/dev/null && av-broker log --tail 1
  ```

  **Nada aqui é manual.** O registro do hook mora em
  `home/.claude/settings.json`, que a ativação (`home.activation.claudeSettings`)
  copia por cima de `~/.claude/settings.json` a cada switch — editar só o arquivo
  vivo é perder a edição no switch seguinte, o que aconteceu no dia em que o hook
  nasceu. Confira com `python3 scripts/hooks/test-deny-keychain-read.py` (31 casos)
  e depois ao vivo, sempre com um alvo que **não existe** — assim, se o hook
  estiver morto, o pior que acontece é um erro de item/arquivo inexistente em vez
  de um segundo vazamento:
  ```sh
  security find-generic-password -s NAO-EXISTE-teste-do-hook -w
  ./scripts/nao-existe/av-broker salesforce --emit json | tail -25
  ```
  Ler segredo continua permitido pelo caminho certo, de dentro de um processo que
  captura em memória (`subprocess.run(..., capture_output=True)`) — os testes
  cobrem isso, porque um guard-rail que atrapalha o trabalho legítimo é desligado
  na primeira semana.

  **Emenda de 18/ago/2026 — o hook também cobre os PATs.** O
  `deny-keychain-read.py` barra comandos de shell cujo produto seja
  `github-pat` ou `github-pat-vm`. Isso ficou **mais** importante, não menos: o
  PAT é de vida longa, então um vazamento em transcript não expira sozinho como
  o `ghs_…` de 1 h expirava. Para ler o PAT legitimamente, use o `gh-pat` de
  dentro de um processo que capture em memória; para só saber se ele existe, use
  o subcomando `check`, que não imprime valor.

  **A tentação a recusar:** o diálogo do Keychain oferece *"Sempre Permitir"*.
  Nunca clique. Aquilo põe `/usr/bin/security` na ACL do item e o entrega a
  **qualquer** processo, para sempre. Isso continua valendo para as chaves de
  Shopify, GCP e Salesforce, que seguem em chaveiro dedicado com ACL vazia.

  **A search list do Keychain, hoje declarada.** Desde
  02/ago/2026 nenhuma credencial do broker fica no `login` — lá a ACL vazia **não
  era cobrada** (o `partition_id` é aberto e o chaveiro nunca tranca), e o
  endurecimento era decorativo.

  ⚠️ **18/ago/2026: eram cinco, são quatro.** O `av-broker-github` saiu com o
  GitHub App. E os dois PATs (`github-pat`, `github-pat-vm`) **ficam mesmo no
  `login`**, deliberadamente: como o argumento acima explica, ACL vazia com
  chaveiro destrancado é decoração, e decoração de segurança engana o dono.
  Assuma que o PAT é legível por qualquer processo seu e escolha o escopo dele
  com isso em mente.

  As quatro do broker vivem em `av-broker.keychain`, e o
  broker só as enxerga se esse chaveiro estiver na *search list*, que é
  preferência de usuário e **se perde no wipe**. Isso é reposto sozinho:
  `home.activation.avKeychainSearchList` roda
  `scripts/ensure-keychain-search-list.sh` a cada switch, que é idempotente, lê a
  lista antes de escrever (um `-s` cego derrubaria o `login.keychain` e com ele
  Wi-Fi e Safari) e **não** cria o chaveiro — `create-keychain` pede senha, e
  ativação não é lugar de diálogo. Se o chaveiro não existir ainda, crie-o você:
  ```sh
  security create-keychain ~/Library/Keychains/av-broker.keychain-db
  sh scripts/ensure-keychain-search-list.sh    # ou simplesmente o próximo switch
  for s in av-broker-gcp av-broker-salesforce \
           av-broker-salesforce-prod claude-setup-token; do
    printf '%-28s %s\n' "$s" \
      "$(security find-generic-password -s $s 2>&1 | sed -n 's/^keychain: //p')"
  done
  #   -> as quatro devem dizer av-broker.keychain-db, NUNCA login.keychain-db
  #   github-pat e github-pat-vm NAO entram nesta lista: eles vivem no login,
  #   por decisao de 18/ago/2026 (ver acima). Confira-os com: gh-pat check
  ```
  Se alguma disser `login.keychain-db`, ela está no chaveiro fraco: regrave-a no
  dedicado antes de seguir. `av-broker doctor` avisa quando o item some por causa
  da search list, e diz o comando de reposição.

  **O que isso custa:** cada cunhagem de GCP ou Salesforce abre um diálogo de
  senha (~4 s, medido). É pouco porque são raras — 1 e 5 cunhagens em cinco dias
  de log, contra 39 de GitHub num dia. Foi essa assimetria que matou o arranjo do
  GitHub e deixou os outros de pé: o gesto por cunhagem é aceitável em alvo raro
  e insuportável em alvo de rotina.
  O `claude-setup-token` cobra o mesmo gesto quando o `shuru-vm.sh` o lê para
  injetar na VM: **subir VM passou a exigir sessão gráfica.** De `ssh` ou `cron`
  o script falha, dizendo exatamente isso.

  Verificar, nesta ordem:
  ```sh
  command -v gh                                      # ~/.local/bin/gh (o wrapper)
  command -v gh-pat                                  # ~/.local/bin/gh-pat
  command -v av-broker                               # ~/.local/bin/av-broker
  gh-pat check                                       # host e vm: "presente"
  gh --version                                       # deve dizer "(nixpkgs)"
  echo "$GH_REAL"                                    # /nix/store/...-gh-<ver>/bin/gh
  gh api user --jq .login                            # 200, e zero diálogo
  gh pr list -R <owner>/<repo>                       # 200
  gh repo list --limit 3                             # 200 (era impossível antes)
  gh auth login                                      # deve ser RECUSADO pelo wrapper
  security find-generic-password -s gh:github.com    # exit 44 (not found)
  ```
  ⚠️ Mudanças de 18/ago/2026 nesta lista: `av-broker agent status` **não existe
  mais** (o subsistema de agente saiu inteiro); `gh auth status` **passa a
  responder autenticado**, o que antes seria sinal de erro; e o
  `security ... -s gh:github.com` continua tendo que dar *not found* — o PAT
  mora em `github-pat`, não no item do `gh auth login`. A checagem foi trocada
  para não usar `-w`, que imprimiria o segredo.
  Duas armadilhas de shell velha, as duas já pagas em 02/ago/2026:
  o `command -v` dando outro caminho significa que a aba é anterior ao
  `darwin-rebuild switch` (o prepend do PATH só vale em shell nova); e o
  `GH_REAL` vazio numa aba velha **não** é bug — o home-manager pula o re-source
  quando `__HM_SESS_VARS_SOURCED=1` já está no ambiente herdado. Confira com
  `env -u __HM_SESS_VARS_SOURCED zsh -lic 'echo $GH_REAL'` antes de investigar.
  Mesmo sem `GH_REAL` o wrapper funciona: ele varre o PATH comparando **inode**
  do alvo final e pula a si mesmo.

  **O que passou a funcionar em 18/ago/2026, e vale registrar porque era o
  parágrafo oposto:** operações de **conta** — `gh repo list` da conta inteira,
  `gh search`, criar repositório. A versão (2) deste item dizia, corretamente,
  que isso "nunca vai funcionar, e não é defeito": token de instalação é **por
  repositório** e carrega só as permissões da instalação; não existe "token da
  conta", e a orientação era usar a web. Com um PAT, existe — dentro do que o
  escopo do token alcançar.

  **O que agora só você controla:** o alcance do token. Antes, alargar exigia dois
  gestos na UI do App e um `422` avisava alto quando a permissão faltava. Agora o
  escopo é escolhido uma vez em
  `github.com/settings/personal-access-tokens`, e nada nesta máquina o audita, o
  reduz por comando nem o expira. Revisão trimestral: abra essa lista, confira
  escopo, repositórios selecionados e data de expiração dos dois tokens.
- [ ] **3.3 — Gerenciador de senhas** como única origem de segredo.
- [ ] **3.4 — automic-vault.** Instalado **declarativamente** pelo tap oficial
  (`automic-vault/isotopes/automic-vault` em `homebrew.casks`), não pelo `install.sh`
  via curl — o script não é reproduzível nem sobrevive a um wipe.
  Papel dele neste desenho: guardar os **segredos mestres no host** e ser o gate onde
  você autoriza *derivar* credencial efêmera. Ele **não** protege as VMs —
  é macOS-only e elas são Linux.

  **Passos pós-instalação (imperativos — o flake NÃO os reproduz):**
  1. Abrir o app e clicar **Install av CLI** (instala `av` + stub root em
     `/usr/local/bin`). Exige admin: faça enquanto `alex` ainda é admin.
  2. ~~`av harden gh`~~ — **não faça.** Removido em 02/ago/2026 e **ainda fora
     em 18/ago/2026**, pelas duas razões que sobreviveram à troca de arranjo:
     (a) o gate cobrava 582 diálogos/dia e nenhum nível nem override do AV o
     silencia, porque o app que ele enxerga é o Claude Code, inelegível por
     assinatura; (b) `av harden gh` endurece o item `gh:github.com` que o
     `gh auth login` cria, e `gh auth login` continua proibido (3.2) — não há o
     que endurecer. O PAT de hoje mora em `github-pat`, que o `av harden gh` não
     conhece; e mesmo que conhecesse, o argumento (a) o mataria de novo.
  3. Verificar que não há **segunda cópia** de credencial de `gh` na máquina:
     `security find-generic-password -s gh:github.com` deve dar **exit 44 (not
     found)**, e `~/.config/gh/hosts.yml` não deve ter chave `oauth_token`.

     ⚠️ **Corrigido em 18/ago/2026.** A redação anterior era *"verificar que não
     há token pessoal de `gh` na máquina"* — **falsa hoje**: há dois PATs
     pessoais, em `github-pat` e `github-pat-vm` (item 3.2). O que se verifica
     aqui é outra coisa, e continua valendo: que **não existe uma cópia em disco**
     criada por `gh auth login`. Uma cópia, um lugar. E não use `-w` nessa
     checagem — ele imprimiria o segredo se por acaso existisse.

  **O que sobra para o vault neste desenho.** `av doctor` deve listar só o
  `claude` — é o token do Claude Code que ele protege. A credencial do GitHub
  nunca esteve no vault: até 18/ago/2026 era a chave privada do App, no
  **Keychain** com ACL própria; de 18/ago/2026 em diante são os dois PATs, no
  **login keychain**, sem gate nenhum e assumidamente assim (3.2 explica por
  quê). Não reintroduza `av harden gh` "por segurança": o `gh` desta máquina não
  faz `auth login`, então não há item `gh:github.com` para endurecer — o gate
  ficaria protegendo o vazio e ressuscitaria os 582 diálogos.

  ⚠️ Depois de um wipe, o flake reinstala o app, mas o **gate some** até você
  repetir o passo 1. Nas aprovações, **nunca** use "Always Approve" para o
  terminal (WezTerm) — isso libera todo comando que o terminal roda e anula o
  gate. Use sempre "Approve Once". A exceção de 01/ago/2026 (um override de
  *Trusted Access* para o WezTerm no gate do `gh`) **não** revoga esta regra: ela
  foi criada, medida e provou-se **letra morta**, porque o WezTerm não está na
  árvore de processos de nenhum caminho real. Se ela ainda existir na máquina
  velha, apague junto com o gate do `gh`.

  ✅ **Resolvido em 02/ago/2026 — `automic-vault/isotopes/gh-cli` saiu.** O único
  motivo daquele formulário era o `av harden gh` do passo 2. Com o token pessoal
  revogado e o harden aposentado, sobrava só o custo, que é mensurável:

  > Ressalva de 18/ago/2026: "token pessoal revogado" já não descreve a máquina.
  > Aquele token — o do `gh auth login`, gravado em `~/.config/gh/hosts.yml` —
  > segue revogado e não volta. Mas existem agora **dois PATs fine-grained** no
  > login keychain (item 3.2), que são token pessoal por qualquer definição
  > honesta. A conclusão deste bloco não muda: o isotope continua sem motivo,
  > porque o `gh` não passa mais pelo vault de jeito nenhum.

  ```
  oficial   Developer ID Application: GitHub (VEKTX9H2N7)
  isotope   Developer ID Application: Max Howell (ZU76A67LGU)
  ```

  Era um rebuild de 53 MB do `gh`, assinado por **uma pessoa física**, sem versão
  presa a lock nenhum, no caminho de credencial da máquina. O `gh` passou para o
  **nixpkgs** (`home.packages`), e o `GH_REAL` do wrapper vem do
  `home.sessionVariables` com o caminho exato do store.

  Por que nixpkgs e não o release oficial do `cli/cli`, que tem os bytes
  assinados pelo GitHub e duas attestations de proveniência: o nixpkgs **não
  amplia a superfície de confiança** — o sistema inteiro já vem dele, inclusive o
  Python que roda o broker — e prende a versão no `flake.lock`, o que importa
  porque o `gh` agora *é* o caminho de credencial. Verificado: o nixpkgs fixado
  compila de `github.com/cli/cli/archive/refs/tags/v2.96.0.tar.gz`, a mesma tag
  do release. Se um dia quiser os bytes do GitHub **com** pin, o caminho é uma
  derivação `fetchurl` do zip assinado, não baixar o `.pkg` na mão.

  ⚠️ Achado que contraria a intuição, verificado e não presumido: o `.pkg` oficial
  de macOS **não tem assinatura nenhuma** (`pkgutil --check-signature` responde
  `Status: no signature`). Quem é assinado é o binário dentro dele.

  🔴 **4. Abrir o app UMA vez depois de instalar o cask — não é opcional.**
  Instalar o cask **não** registra o serviço de aprovação. O agente de login
  (`~/Library/LaunchAgents/com.automicvault.menubar-helper.plist`, que publica o
  Mach service `com.automicvault.av2.approval`) só nasce no **primeiro launch do
  app**. Medido em 29/jul/2026: cask instalado 22:18, app nunca aberto, agente
  inexistente às 23:16 — e nesse intervalo `gh auth status` respondia
  **"The token in  is invalid"**, mandando rodar `gh auth login`. Seguir esse
  conselho cunharia token novo para consertar um app que só precisava subir. Um
  `open -a "Automic Vault"` às 23:17 criou o agente e o `gh` voltou na hora.

  Como isto colide com o `cleanup = "zap"` (item 2.2 e AGENTS.md): **todo
  `darwin-rebuild` que reinstale este cask pode derrubar o agente de novo**, e o
  sintoma vai ser "meu token expirou", não "faltou abrir um app". Confira com:

  ```sh
  launchctl list | grep automic     # esperado: com.automicvault.menubar-helper
  ps -axo comm | grep -i "Automic Vault"
  ```

  O agente tem `RunAtLoad` e `MachServices` (logo, launchd o sobe sozinho por
  demanda depois de registrado), mas **não tem `KeepAlive`** — e o `av` não
  degrada de forma legível quando ele falta: `av save` fica **travado sem imprimir
  um byte**, em vez de dizer "approval service is not running", que é uma string
  que existe na binária mas não apareceu. Não interprete `av` travado como rede ou
  Keychain; confira o agente primeiro.

---

## ❄️ FASE 4 — Nix

- [ ] **4.1 —** Instalar Nix, clonar **o seu** dotfiles (o da 0.1), `darwin-rebuild switch --flake .#mac`
- [ ] **4.2 — Remover do `home.nix` a ponte `GH_TOKEN` que lê `~/Projects/.env`.**
  O wrapper `gh` da 3.2 substitui. Continua valendo mesmo depois de 18/ago/2026,
  e o motivo ficou mais estreito: não é mais "token de vida longa é o
  anti-padrão" — o arranjo atual **é** de vida longa. É que segredo em arquivo
  de projeto é a **segunda cópia**, versionável por acidente, legível por
  qualquer coisa que faça `cat ~/Projects/.env`, e que ninguém revoga porque
  ninguém lembra que existe. Uma cópia, um lugar: o keychain.
- [ ] **4.3 —** Tirar `Library/Python/3.9/bin` do `sessionPath` se não usar mais.

---

## 📦 FASE 5 — Agentes em microVMs (shuru)

> **Revisada em 29/jul/2026:** o runtime deixou de ser o Apple `container` e
> passou a ser o **shuru** (microVM no Virtualization.framework,
> offline-by-default, `network.allow` por projeto, secrets por placeholder).
> Racional no ADR `arquitetura-segredos.md` §6.3; fases e gates em
> `docs/plano-adocao-tokens.md`. O Apple `container` fica como plano B se o
> shuru reprovar no teste adversarial (7.4).

- [x] **5.1 — Instalar `shuru` com versão pinada** — `scripts/install-shuru.sh`,
  feito em 29/jul/2026. Pina a **v0.6.5** e confere SHA-256 do CLI **e** da
  imagem de SO. Nem o tap do brew (o `onActivation.upgrade = true` desta casa
  segue o latest e quebraria o pin) nem o `install.sh` deles (não confere hash);
  a imagem vem do script pelo mesmo motivo — o download do `shuru init` não
  verifica nada. **Nunca rode `shuru upgrade`**: subir de versão exige re-rodar
  o teste adversarial 7.4.
- [x] **5.2 — Imagem-base da VM com higiene de supply chain:** pnpm v10
  (lifecycle scripts off por default, cooldown de versões) e
  `ignore-scripts=true` no npm. Todo install roda DENTRO da VM.
  `scripts/shuru/provision-base.sh`, com `minimum-release-age=4320` (cooldown de
  3 dias — cobre as duas janelas do Shai-Hulud). O Claude Code entra pelo
  instalador nativo: o pacote npm depende de um postinstall que o
  `ignore-scripts` justamente impede de rodar.
  A imagem também **pré-marca `hasCompletedOnboarding`** em `$HOME/.claude.json`
  (`HOME=/` no guest, medido) e desliga `autoUpdates`. Não é conforto: sem
  estado de first-run a TUI abre em "Select login method" — o `/login` que o ADR
  §6.4 proíbe — e um binário que se troca sozinho pela rede a cada sessão é
  superfície de supply chain dentro da própria VM e quebra a reprodutibilidade
  da imagem. Protegido pelo teste 9 do gate da Fase 1.
- [ ] **5.3 — Regra de ouro: uma VM por projeto, montando só aquele repo.**
  A segurança real vem daqui, não do kernel separado.
- [ ] **5.4 — O agente roda DENTRO da VM, não no host.** Se o Claude Code rodar
  no host e só o build for isolado, o isolamento é decorativo — o agente
  continua lendo seu home inteiro.
- [x] **5.5 — Credencial por VM: escopada, curta, revogável — e só por
  placeholder.** Nunca a mestra; o proxy do shuru troca o placeholder no egress
  (FASE 7). Nenhum segredo real entra na VM.
  **Verificado em 29/jul/2026** por `scripts/shuru-verify-gate.sh` (8 testes,
  passou). A troca acontece no **header `Authorization`** — é substituição de
  bytes no fluxo TLS interceptado, não expansão de env var, então cobre header,
  corpo e query igualmente. E é **escopada por host**: um destino que está na
  allowlist de rede mas fora da lista de hosts do secret recebe só o placeholder.
  O gate roda com um sentinela descartável, nunca com o `setup-token`.
- [x] **5.6 — Offline por default.** `allow_net` só no projeto que exige, com
  `network.allow` mínima versionada no `shuru.json`. Feito: `shuru.json` na raiz
  deste repo, `allow_net: false`, mount read-only do repo, allowlist com
  api.anthropic.com / platform.claude.com / registry.npmjs.org / pypi.org —
  **github.com está deliberadamente ausente** (quem fala com o GitHub é o
  broker, no host). `platform.claude.com` entrou em 29/jul/2026: o Claude Code
  **interativo** faz preflight contra ele e se recusa a subir se não resolver
  (`Failed to connect to platform.claude.com: ENOTFOUND` — que era o allowlist
  agindo, não falta de rede). `claude -p` não faz esse preflight, então um teste
  em modo print não detecta o problema. Não afrouxa o segredo: a lista de hosts
  do secret é independente e continua só com `api.anthropic.com` — medido, esse
  host recebe apenas o placeholder.
- [x] **5.7 — Canary tokens plantados na imagem-base:** chave AWS falsa da
  Thinkst em `~/.aws/credentials` isca + arquivos-isca. Qualquer uso dispara
  alerta — detecção de exfiltração com zero falso-positivo.
  Plantada em `/root/.aws/credentials`, `.backup` e `/.aws/credentials`; o valor
  vem do Keychain (`canary-vm-aws`) na hora do build e **não é versionado**. Há
  uma segunda isca no host (`canary-host-aws`, `~/.aws/credentials`) — ⚠️ esse
  arquivo é isca, **não** configuração: se um dia usar AWS de verdade aqui, use
  perfil nomeado e deixe o `[default]` como está.
- [ ] **5.8 — Memória:** o Virtualization.framework devolve mal a memória
  liberada. Com 24 GB, reinicie VMs pesadas em vez de acumular.

---

## 🌐 FASE 6 — Navegadores e nuvem

Desenho completo em `arquitetura-navegadores.md`; pesquisa de base em
`research/seguranca_navegadores.md`. Resumo: **três zonas** — Safari (pessoal,
dentro do TCC), navegador de trabalho (fora do TCC, sem conta), Chromium do
agente (dentro da VM, perfil descartável). Estado medido em 28/jul/2026
anotado item a item.

- [x] **6.1 — Safari = pessoal, e é o único navegador com conta pessoal.**
  Os dados dele ficam sob TCC; sem FDA no terminal (2.2), nenhum processo seu os
  lê. É a fronteira barata que o SO aplica sozinho. **Verificado nesta máquina:**
  `~/Library/Safari`, `~/Library/Mail`, `~/Library/Messages`, `~/Desktop`,
  `~/Documents`, `~/Downloads` e `~/Library/Mobile Documents` respondem
  *Operation not permitted* ao terminal.
  ⚠️ Corolário do 2.2: **também nunca conceda "Arquivos e Pastas"** a terminal ou
  editor — Desktop/Documents/Downloads/CloudStorage têm grant próprio, separado do
  FDA. É o FDA parcelado.

- [x] **6.2 — Chrome: não instalar.** No macOS ele **não** tem App-Bound
  Encryption (Windows-only) nem DBSC ainda; a proteção é o item de chaveiro
  `Chrome Safe Storage`, que decripta `Cookies` e `Login Data` e é alvo padrão dos
  stealers ativos de 2026 (AMOS, ClickLock). Com `onActivation.cleanup = "zap"`
  basta **não declarar** em `homebrew.casks` — um `brew install` manual some no
  próximo `darwin-rebuild`. **Estado:** não instalado, sem item no chaveiro.

- [x] **6.3 — Firefox: removido (decisão de 28/jul/2026).** Nunca chegou a ser
  aberto — não havia perfil. O diretório dele não é protegido pelo TCC e
  `logins.json` + `key4.db` juntos decifram as senhas offline, então superfície
  que não se usa é superfície que não se defende. Fora de `homebrew.casks`, o
  `cleanup = "zap"` o desinstala. **Resultado: não há navegador de trabalho — só
  Safari (pessoal) e o Chromium do agente dentro da VM.**
  ⚠️ A remoção só vale **depois do `darwin-rebuild switch`**: o registro do cask
  continua no Homebrew até lá.

- [ ] **6.4 — Automação de browser dos agentes: alvo é a VM** (Chromium
  Linux), nunca o navegador do host. Perfil **isolated/descartável** — perfil
  persistente e arquivo de `storageState` **são credenciais em disco**. Mantenha o
  sandbox interno do Chromium ligado (não caia no `--no-sandbox` para contornar
  syscall bloqueada) e roteie o egress pelo proxy do shuru (FASE 7).

  **Exceção declarada em 29/jul/2026: o `@playwright/mcp` fica no host.** O
  `nodejs_22` do `home.nix` está lá para ele e **permanece** — é a mesma decisão
  de 6.7, e o mesmo envelope: tarefa curta, supervisionada, no host. As condições
  que a delimitam, e sem as quais ela não vale:
  - **Chromium próprio do Playwright, sempre.** Nunca `channel: "chrome"`,
    `executablePath` apontando para um browser pessoal, nem CDP anexado a uma
    instância já aberta. O navegador do 6.1 não é dirigível por agente.
  - **Perfil isolado por sessão, descartado no fim.** Nada de
    `--user-data-dir` persistente, nada de `storageState` gravado em disco: esse
    arquivo é cookie de sessão em texto, e a lição do 6.1 é justamente que sessão
    é a credencial que ninguém governa. Login que exija cookie real → VM.
  - **Sem modo extensão** (`--extension`/`connect over CDP` ao browser do dia a
    dia). Isso cairia direto no 6.5.
  - O processo roda como `alex`: ele alcança `~/Library/CloudStorage` e o resto
    do home. É o custo já aceito em 6.7, não uma exceção nova — mas significa que
    **trabalho de browser não supervisionado continua indo para a VM**.
  - Traces, vídeos e `downloadsPath` do Playwright saem em disco com o que a
    página mostrou; mantenha fora de `~/Library/CloudStorage` e limpe.

- [ ] **6.5 — Extensão de agente no navegador pessoal: não.** A fronteira do 6.1
  é contra processos de fora; extensão roda **dentro** do processo autorizado e o
  TCC não a vê. Em 2026 isso não é teórico: ShadowPrompt (site qualquer injetando
  instrução) e ClaudeBleed (extensão com zero permissões dirigindo o agente para
  ler Gmail/Docs/Calendar, contornando o diálogo de aprovação por spam) — este
  último reverificado em 7/jul/2026 ainda aberto na v1.0.80. Regra: **agente e
  vida pessoal são apps diferentes, não perfis diferentes.**

- [ ] **6.6 — Nuvem: nenhuma credencial de longa vida no disco.**
  **Estado:** `gcloud` instalado, **sem** `application_default_credentials.json`,
  `gcloud auth list` → *No credentialed accounts*. (`credentials.db` existe mas
  tem **0 linhas** — o arquivo nasce vazio no primeiro `gcloud` que roda; não é
  credencial.) **Revisado em 29/jul/2026** — a versão anterior recomendava
  `gcloud auth login` permanente + impersonation, mas o próprio `auth login`
  grava **refresh token de usuário em texto plano** em
  `~/.config/gcloud/credentials.db`, fora do TCC — o mesmo anti-padrão do `.env`.
  Regras atuais (ADR `arquitetura-segredos.md` §6.2):
  - **Host deslogado por default.** Sessão administrativa rara:
    `gcloud auth login` → trabalha → `gcloud auth revoke` (alias no zsh faz o
    par). Administração cotidiana pelo Console no browser.
  - **Broker**: chave RSA de uma **SA-broker** (papel único:
    `serviceAccountTokenCreator` sobre SAs de baixo privilégio, uma por projeto)
    no **Keychain sob o AV** — cunha token de ≤1 h down-scoped para a VM.
  - **Nunca** `gcloud auth application-default login` no host (grava refresh
    token de longa vida em texto, fora do TCC — é o `.env` do item 0.2 outra vez).
  - **Nunca** chave JSON de service account **em arquivo** (no Keychain sob o
    AV é onde ela vive).
  - Dentro da VM: nada de ADC — o token curto vem do broker do host via
    placeholder (FASE 5). *(Até 18/ago/2026 esta linha dizia "mesma fiação do
    GitHub App"; o GitHub saiu dessa fiação — hoje ele entra na VM como PAT em
    mount read-only, ADR §6.6. GCP segue no placeholder.)*

- [ ] **6.7 — Google Drive: declarado no Nix, configurado à mão.** Decisão de
  28/jul/2026: o Drive **vai ser montado**. Instalado declarativamente pelo cask
  `google-drive` em `homebrew.casks` (não pelo instalador baixado do site — com
  `cleanup = "zap"`, o que não está declarado não sobrevive ao próximo rebuild).
  ⚠️ **REVISADO em 28/jul/2026 — a premissa original estava errada.** Assumia-se
  que o conteúdo de `~/Library/CloudStorage` caía sob "Arquivos e Pastas" e que,
  sem o grant, o agente não leria o Drive. **Medido depois de montar: é falso.**
  O terminal — sem FDA e sem "Arquivos e Pastas", com `~/Documents` ainda
  bloqueado como controle — lista `Meu Drive`, os `Drives compartilhados` e **lê
  conteúdo de arquivo**. O TCC **não protege a montagem do Drive**.
  Consequência: **o Drive está ao alcance de qualquer processo que rode como
  `alex`** — inclusive de um agente rodando no host, para **ler e para escrever**
  (escrever em pasta sincronizada é publicar). O que separa os dois deixa de ser o
  TCC e passa a ser a regra 5.4 (**o agente roda dentro da VM**, montando
  só o repo).

  **Risco aceito — decisão de 29/jul/2026.** O Claude Code continua rodando no
  host, e o acesso dele ao Drive é assumido como custo consciente. As condições
  que delimitam a aceitação, e que são o que a torna defensável:
  - **tarefas curtas e sob supervisão** — você acompanhando, não trabalho longo
    rodando sozinho;
  - **trabalho não supervisionado vai para a VM** (FASE 5), que passa a
    ser o único mecanismo de separação — o que eleva a prioridade dela;
  - **a perna de saída continua aberta, e o LuLu não a fecha bem**: um firewall
    por-processo *vê* o agente no host (ao contrário do que ocorre com
    a VM), mas o tráfego dele para `api.anthropic.com` é legítimo e
    constante — não há regra por-app que distinga trabalho de exfiltração. O
    controle mais direto para este risco é o **Santa** (item 7.5), que restringe
    *quais processos leem* `~/Library/CloudStorage`;
  - se o padrão de uso mudar (sessão longa, agente sem supervisão, mais de um
    agente), **a aceitação não acompanha automaticamente** — é reavaliar.

  **Passos pós-instalação (imperativos — o flake NÃO os reproduz):**
  - **Só a conta pessoal** logada no Drive para desktop. Conta de trabalho
    (Ministério da Gestão / OneDrive) fica fora desta máquina ou noutra conta de
    usuário.
  - **Modo "stream", não "mirror"** — mirror baixa o Drive inteiro para o disco;
    stream mantém sob demanda. Menos dado em repouso, mesma usabilidade.
  - **NÃO ativar "pastas do computador"** (backup de Mesa/Documentos/Downloads
    para o Drive). Isso publicaria justamente as pastas que o TCC protege — e
    qualquer coisa que um agente escrevesse ali subiria para a nuvem.
  - **Nenhum repositório dentro do Drive**, e o Drive nunca montado dentro de
    `~/Projects`. Escrever em pasta sincronizada é publicar, com histórico de
    versão do provedor. Hoje `~/Projects` é `/Users/alex/Projects` — fora de
    qualquer caminho sincronizado. Mantenha assim.
  - **Nunca montar o caminho do Drive dentro de uma VM** (regra 5.3: só o
    repo daquele projeto).
  - Na primeira execução ele pede aprovações próprias (extensão de File Provider,
    item de início de sessão, notificações). **Aprove para o app Google Drive —
    e só para ele.** Isso não tem relação com dar "Arquivos e Pastas" a um
    terminal, que continua sendo não.
  - Não haverá firewall de host perguntando sobre o processo do Google Drive: o
    item 7.1 tirou LuLu e Little Snitch do plano. O egress do Drive fica sem
    filtro por-app **de propósito** — o que ataca este risco é o item 7.5.
  - A verificação da FASE 8 **não** espera bloqueio aqui (ele não existe): ela
    reporta a montagem como exposição conhecida, para não virar um ✅ falso.

- [x] **6.8 — iCloud: Chaveiro sim, Mesa & Documentos não.** Conferido na GUI em
  28/jul/2026: **não há sync de Mesa e Documentos** — nenhum código vai para o
  iCloud Drive. `KEYCHAIN_SYNC` segue ligado, e é desejado: passkey em Secure
  Enclave é a única credencial da casa que um agente comprometido **não consegue
  copiar**. (Não é verificável pelo terminal — o espelho local é TCC-protegido, e
  isso é a proteção funcionando; a conferência é na GUI mesmo.)

---

## 🚧 FASE 7 — Egress

Pesquisa de base: `research/egress.md`. **A fase foi reescrita em 29/jul/2026 —
a versão anterior estava errada no ponto principal.** Ela dizia que o LuLu era
"a única camada que ataca o enviar remotamente". Não é: o LuLu filtra **fluxos de
socket de processos do host** (`NEFilterDataProvider`), e a NAT do vmnet acontece
**no kernel**. Um agente dentro de container/microVM não aparece para ele como
processo — no melhor caso ele veria o runtime do host como um único processo com
egress amplo, o que é inútil para regra fina.

O ponto de controle correto é a **fronteira da VM**: rota única para um proxy
default-deny, sem rota direta para a internet.

> **Convergência com a FASE 5 (revisão de 29/jul/2026):** com o shuru como
> runtime, esse proxy **é o proxy embutido do shuru** — allowlist default-deny
> (`network.allow`), injeção de credencial por placeholder e log, num ponto só
> no host. **Não construa dois**: nada de Squid/tinyproxy paralelo. O `pf`
> deixou de ser incondicional e virou contingência do teste 7.4.

- [x] **7.1 — Firewall de host por-app: fora do plano.** Decisão de 29/jul/2026.
  O LuLu saiu de `homebrew.casks` e o Little Snitch 6 foi descartado junto.
  Motivo: ambos são `NEFilterDataProvider` (fluxo de socket, por processo do
  host) e a NAT do vmnet é **em kernel** — nenhum dos dois vê o tráfego que sai
  de dentro da microVM, que é exatamente o que precisa ser controlado. Manter um
  deles só compraria fadiga de alarme e a ilusão de cobertura. O LuLu nunca
  chegou a ser ativado (sem processo, sem extensão de sistema registrada), então
  não há estado a desfazer além do cask.
  - **Remoção efetiva:** `cleanup = "zap"` desinstala no próximo
    `darwin-rebuild switch`. O cask **não tem stanza `uninstall` nem `zap`**
    (verificado na API do Homebrew em 29/jul/2026) — o único artefato é
    `LuLu.app`, então a remoção não deve esbarrar em caminho TCC-protegido nem
    disparar o pedido de FDA do item 2.2. Se disparar mesmo assim, a resposta
    continua sendo **não** (ver `AGENTS.md`).
  - **Estado antes de remover** (medido em 29/jul/2026): cask instalado
    (4.4.3), `systemextensionsctl list` sem nenhuma extensão da Objective-See.
    Confirmar o mesmo depois do rebuild — nada registrado, `/Applications`
    limpo.
  - **O que se perde, explicitamente:** visibilidade de egress dos processos do
    *host* (Claude Code, updaters, o próprio Google Drive). É consistente com
    6.7 — o que ataca aquele risco é o Santa (7.5), por acesso a arquivo, não um
    firewall que veria só tráfego legítimo para `api.anthropic.com`.
  - Reabrir esta decisão exige fato novo: evidência publicada de um NEFilter
    atribuindo corretamente fluxos de VM do Virtualization.framework.

- [ ] **7.2 — Proxy do shuru como ponto único de enforcement + injeção.** É a
  peça que de fato controla: `network.allow` mínima por projeto, versionada no
  `shuru.json` em git (`api.anthropic.com`, `platform.claude.com`,
  `registry.npmjs.org`, `pypi.org` — **sem `github.com`**, que este item listava
  por engano até 29/jul/2026); secrets só por placeholder (5.5). Sem MITM próprio — decide
  pelo destino, não quebra certificate pinning, gRPC nem mTLS. MITM
  (`mitmproxy`) só seletivo e futuro, para domínio onde inspeção de conteúdo
  agregue e não haja pinning.

- [x] **7.3 — `pf` condicional ao resultado do 7.4: DECIDIDO em 29/jul/2026 —
  `pf` NÃO será usado.** O 7.4 rodou e caiu no **primeiro ramo**. Três medições
  independentes sustentam a decisão: (a) com a VM no ar, `ifconfig -l` do host
  não ganha `bridge1XX` nem `vmenet` — não existe bridge NAT; (b) o processo do
  shuru não abre porta de escuta para a VM; (c) o guest não tem **nenhuma**
  variável `HTTP(S)_PROXY` e mesmo assim o egress permitido funciona e o
  proibido não. Ou seja: o shuru faz rede **em modo usuário**, terminando os
  pacotes do guest dentro do próprio processo. O `pf` filtra interfaces do host,
  e o tráfego do guest nunca aparece lá como tráfego do guest — não haveria onde
  agir. Este é o caso em que a ausência de uma camada é a resposta certa, não uma
  pendência. **Gatilho de reabertura:** se um `ifconfig -l` futuro mostrar
  bridge/vmenet com a VM rodando, volte ao segundo ramo abaixo.

  <details><summary>Racional original (mantido para o dia da reabertura)</summary>

  Variável `HTTP(S)_PROXY`
  é **cooperação**, não controle: código malicioso ignora e abre socket direto.
  O enforcement precisa estar fora do alcance do código convidado. O mecanismo
  do `--allow-net` do shuru é **não verificado** (caveat do research) — o teste
  7.4 decide o caminho:
  - se o guest **não tem interface externa** (egress só por vsock/socket até o
    proxy): enforcement estrutural, `pf` desnecessário — apagar as variáveis de
    proxy não tem efeito porque não há outro caminho;
  - se `--allow-net` criar **bridge NAT com rota direta**: anchor de `pf`
    permitindo da subnet **somente** o IP:porta do proxy, e bloqueando **DNS
    direto (53)**, **DoT (853)** e **UDP/443** — sem isso, IP literal, DoH e
    QUIC com ECH contornam qualquer allowlist de domínio. Snippet pronto em
    `research/egress.md` §4.3(a); persistir via LaunchDaemon versionado.
    ⚠️ A Apple declara em TN3165 que *"Packet Filter is not API"* — funciona,
    mas revalide a cada atualização do macOS.

  </details>

  📌 **Correção de uma leitura anterior.** Em 29/jul/2026 a Fase 1 anotou que o
  guest ganha `eth0` real em 10.0.0.2/24 e concluiu que isso apontava para o
  segundo ramo. O `eth0` existe mesmo — mas ter interface não é ter rota: os
  quadros vão para a pilha em modo usuário do shuru, não para uma NAT do kernel.
  A conclusão correta é a do 7.3 acima.

- [x] **7.4 — Validação adversarial antes de confiar: RODADA em 29/jul/2026,
  PASSOU.** `scripts/shuru-verify-fase2.sh` — os 8 testes de
  `research/egress.md` §4.4 mais 4 específicos desta arquitetura (SNI forjado
  sobre IP proibido, QUIC/UDP 443, o resolver do shuru como canal encoberto, e
  pivot para o host e para a LAN). Nenhum caminho de egress fora da allowlist.
  O único item que passa é o 8 — exfiltração **dentro** de domínio permitido —
  que é o risco residual conhecido, não uma falha.

  ⚠️ **A armadilha desta medição, registrada porque quase produziu o veredito
  oposto:** a primeira versão do gate acusou **13 vazamentos inexistentes**. A
  pilha em modo usuário do shuru **aceita o handshake TCP localmente** antes de
  decidir se abre a saída, então `connect()` "tem sucesso" até para
  `192.0.2.1` — TEST-NET-1, inalcançável por definição. Sucesso de `connect()`
  não prova alcance nenhum. O critério honesto é **byte de volta**: só o outro
  lado real pode enviá-lo. Por isso o gate hoje tem **dois** controles
  obrigatórios que abortam com INCONCLUSIVO se falharem — um positivo (o host
  permitido responde, senão a VM está sem rede e "tudo bloqueado" não prova
  nada) e um negativo (TEST-NET-1 não devolve dados, senão a sonda está medindo
  ficção). Quem for reescrever este gate: mantenha os dois.

- [ ] **7.5 — Santa como complemento de host (avaliar).** Não é egress — é
  autorização de binário + **File Access Authorization**. Entra aqui porque
  ataca diretamente o risco aceito em 6.7: dá para restringir **quais processos
  leem `~/Library/CloudStorage`**, que é a barreira que o TCC não fornece.
  Grátis, open source, validado em Tahoe 26.0, config versionável.

### Risco residual que nenhuma dessas camadas remove

**Exfiltração por domínio permitido.** Allowlist por SNI não vê conteúdo: dado
sai embutido em requisição legítima a `github.com` (gist, issue, push) ou a
`api.anthropic.com`. É o mesmo "egress que parece legítimo" da FASE 5 — só MITM
seletivo mitiga, ao custo de quebrar pinning. Documentado, não resolvido.

---

## ✅ FASE 8 — Verificação

**Atalho: `sh scripts/verify-hardening.sh`** cobre os itens 3, 9, 10 e 11 desta
lista mais o que é da Fase 4 do plano de tokens (idade das credenciais, canaries
ainda *armados*, pin do shuru, higiene da imagem-base). Rode-o **mensalmente** —
não só na reinstalação. Os checks abaixo continuam valendo para o que ele não
cobre (FileVault, SSH, TCC).

Ele distingue **alerta** de **falha**, e checa coisas que passam num gate e
apodrecem depois: canary substituído por credencial AWS real (a detecção de
exfiltração morre em silêncio), `shuru upgrade` rodado sem re-testar o egress
(o gate da Fase 2 vale para *uma* versão), `allow_net` ligado "só por um minuto"
no `shuru.json`, credencial vencida.

```sh
# 1. FDA NÃO concedido ao terminal — este comando DEVE falhar
ls ~/Library/Application\ Support/com.apple.TCC/ 2>&1 | head -1

# 2. FileVault
fdesetup status

# 3. Firewall
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# 4. Homes fechados (esperado: drwx------)
ls -ld /Users/*

# 5. Toda chave SSH com passphrase
for f in ~/.ssh/id_*; do
  case "$f" in *.pub) continue;; esac
  ssh-keygen -y -P "" -f "$f" >/dev/null 2>&1 \
    && echo "❌ $f SEM passphrase" || echo "✅ $f protegida"
done

# 6. Conta diária NÃO é admin (alex não deve aparecer)
dscl . -read /Groups/admin GroupMembership

# 7. Nenhum .env com segredo real
find ~/Projects -maxdepth 3 -name ".env" ! -name "*.example" 2>/dev/null

# 8. FASE 6 — a fronteira do TCC de pé (TODOS devem dar "Operation not permitted").
#    Rode do terminal que você usa no dia a dia; re-rode depois de cada
#    darwin-rebuild que atualize o terminal (grant morre quando o binario muda).
# ATENCAO: nao use `[ -e "$p" ]` como guarda — caminho protegido as vezes nega o
# proprio stat e responde "No such file" (visto em ~/Library/Mobile Documents).
# Um guarda de existencia transformaria a checagem num skip silencioso.
chk() {
  err=$(ls "$1" 2>&1 >/dev/null)
  case "$err" in
    *"Operation not permitted"*) echo "✅ TCC bloqueia $1" ;;
    "")                          echo "❌ LEGIVEL $1 — algum grant de FDA/Arquivos e Pastas foi concedido" ;;
    *"No such file"*)            echo "•  $1 — nao existe OU o TCC esconde; nao conclui nada" ;;
    *)                           echo "…  $1: $err" ;;
  esac
}
for p in ~/Library/Safari ~/Library/Mail ~/Library/Messages \
         ~/Desktop ~/Documents ~/Downloads ~/Library/Mobile\ Documents; do
  chk "$p"
done
# Montagens de nuvem: NAO sao protegidas pelo TCC (medido em 26.5.2 com o Google
# Drive — o terminal le "Meu Drive" e o conteudo dos arquivos, com ~/Documents
# ainda bloqueado como controle). Aqui a saida e um inventario de exposicao, nao
# um teste de bloqueio: tudo que aparecer esta ao alcance de agente no host.
find ~/Library/CloudStorage -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r m; do
  n=$(find "$m" -maxdepth 2 2>/dev/null | wc -l | tr -d ' ')
  echo "⚠️  EXPOSTO ao host ($n itens ate nivel 2): $m"
done

# 9. Chrome ausente e sem chave de sessão no chaveiro (esperado: nada + exit 44)
ls -d /Applications/Google\ Chrome.app 2>/dev/null && echo "❌ Chrome instalado"
security find-generic-password -s "Chrome Safe Storage" >/dev/null 2>&1 \
  && echo "❌ Chrome Safe Storage no chaveiro" || echo "✅ sem Chrome Safe Storage"

# 10. Nenhuma credencial de nuvem de longa vida no disco
ls ~/.config/gcloud/application_default_credentials.json 2>/dev/null && echo "❌ ADC presente"
# credentials.db nasce vazio no primeiro `gcloud` que rodar — o que importa e a
# contagem de linhas, nao a existencia do arquivo.
[ -f ~/.config/gcloud/credentials.db ] && \
  echo "contas gcloud persistidas: $(sqlite3 ~/.config/gcloud/credentials.db 'select count(*) from credentials;' 2>/dev/null)"
gcloud auth list 2>&1 | grep -q "No credentialed accounts" && echo "✅ gcloud sem conta ativa"

# 11. Egress — RESOLVIDO em 29/jul/2026 pelo item 7.4: o pf NÃO é usado nesta
#     máquina, e a ausência dele não é falha. O shuru faz rede em modo usuário
#     (sem bridge/vmenet no host), então não há tráfego de guest numa interface
#     do host para o pf filtrar. O check que vale é o adversarial:
sh scripts/shuru-verify-fase2.sh   # 12 testes de dentro do guest; tem que PASSAR
# Se um dia o shuru passar a criar bridge NAT (verificável: `ifconfig -l` ganha
# bridge1XX/vmenet com a VM no ar), reabra o item 7.3 e volte a exigir o anchor.
# No modo bridge-NAT a anchor tem que BLOQUEAR 53/853/UDP-443 vindos da subnet
# da VM; conferir na listagem acima, nao so a existencia dela.
```

---

## 🚢 APÊNDICE A — Instalar a stack do Kun Chen (prompt para o Claude Code)

Cole o bloco abaixo num Claude Code recém-aberto na máquina nova, **depois** das
fases 0–7. Ele é auto-contido e verificável.

````text
Instale a stack de agentes do Kun Chen nesta máquina (macOS 26, Apple Silicon).
Contexto de segurança que NÃO deve ser violado:
- Nenhum terminal tem Full Disk Access, e não deve ganhar.
- Segredos vêm do automic-vault / gh keyring. Nunca escreva segredo em .env.
- O agente de trabalho roda DENTRO da VM shuru, uma por projeto, montando só o repo.

Fatos já verificados (não re-pesquise):
- firstmate NÃO tem binário e NÃO tem releases. O repo clonado É a distro:
  AGENTS.md + skills + scripts que qualquer agente de terminal segue.
- Plataforma declarada: macOS | Linux.
- Backend de referência é o tmux. herdr, zellij, Orca e cmux são EXPERIMENTAIS.
- herdr é um binário separado (repo ogulcancelik/herdr, v0.7.5), no homebrew-core
  com bottle arm64 de macOS. Também publica herdr-linux-aarch64 para as VMs.

Passos:
1. Pré-requisitos: git, herdr, e o `gh` do item 3.2 — que é o wrapper
   ~/.local/bin/gh (scripts/gh-token.sh), NÃO `gh auth login`. Não rode device
   flow: o wrapper recusa `gh auth login` de propósito, para não criar uma
   SEGUNDA cópia do token em ~/.config/gh/hosts.yml.
   ⚠️ Corrigido em 18/ago/2026: a redação anterior dizia "não crie PAT: não há
   token pessoal do GitHub nesta máquina, por decisão" — FALSO desde 18/ago/2026.
   Há dois PATs (github-pat, github-pat-vm), criados pelo roteiro do item 3.2.
   O que continua proibido é criá-los pelo `gh auth login` ou guardá-los fora do
   keychain.
   Verifique com: command -v gh && gh-pat check && gh pr list -R <owner>/<repo> && herdr --version
   herdr JÁ vem instalado pelo flake (declarado em homebrew.brews do
   configuration.nix). NÃO rode `brew install herdr` — com
   onActivation.cleanup = "zap" o que vale é o que está declarado.
2. Clone a distro:
   git clone https://github.com/kunchenguid/firstmate ~/Projects/firstmate
3. Leia ~/Projects/firstmate/README.md e ~/Projects/firstmate/AGENTS.md ANTES
   de configurar qualquer coisa. Siga o que estiver lá, não o que você presume.
4. Use herdr como backend. Decisão consciente: o firstmate ainda o marca como
   EXPERIMENTAL (ver Fatos acima). A config já existe versionada em
   home/.config/herdr/config.toml e é symlinkada pelo home.nix.
   Se o herdr travar ou o firstmate não suportar algo, o tmux está instalado
   (home.packages) como caminho de fallback — não precisa de rebuild para usar.
5. Dentro da VM Linux aarch64 (shuru), use o asset herdr-linux-aarch64 da release
   do repo ogulcancelik/herdr. O brew do host não serve para a VM.
6. NÃO instale nem configure: automic-vault dentro da VM (é macOS-only),
   nem qualquer ponte que leia ~/Projects/.env.
7. Reaplique as alterações locais. O firstmate é CLONADO, não forkado: o que
   fizemos nele não está em lugar nenhum do histórico do upstream e some no
   clone novo. Siga docs/firstmate-local.md — são os patches em
   docs/firstmate-patches/ (git am) mais o data/projects.md, que é gitignorado.

Critério de conclusão (me mostre a saída de cada um):
- command -v gh   -> ~/.local/bin/gh (o wrapper), nao /opt/homebrew/bin/gh
- gh pr list -R <owner>/<repo>  -> lista, sem diálogo do Automic Vault
- ls ~/Projects/firstmate/AGENTS.md  -> existe
- herdr --version  -> versão impressa
- grep -rc "GH_PAT" ~/  2>/dev/null | grep -v ':0'  -> sem resultado
- grep -cF -- '--vm)' ~/Projects/firstmate/bin/fm-brief.sh  -> 1 (patch aplicado)
- cat ~/Projects/firstmate/data/projects.md  -> lista meu-projeto

Não declare pronto sem ter rodado os quatro comandos acima e colado a saída.
````

**Por que herdr e não tmux (decisão revista em 2026-07-28):** o firstmate segue
marcando herdr/zellij/Orca/cmux como experimentais e tratando tmux como referência —
esse fato não mudou. O que pesa contra ele aqui é que este dotfiles já adotou herdr:
`herdr` está declarado em `homebrew.brews` e `home/.config/herdr/config.toml` existe
versionado, com keymap completo. Rodar tmux significaria manter uma config viva no
repo para um backend não usado.

O risco assumido é real: um backend experimental pode quebrar num upgrade do
firstmate. A mitigação é o tmux continuar em `home.packages` — trocar de volta é
editar uma linha de config, não um rebuild.

---

## O que este plano NÃO resolve

- Um agente comprometido dentro da VM ainda exfiltra **o que você montou e
  injetou nela**. Isolamento protege o host; não protege o dado entregue ao agente.
- `shuru` é jovem (research-preview): pin de versão + vendor do source + teste
  adversarial (7.4) são a mitigação; Apple `container` é o plano B.
- automic-vault e a VM **não protegem o mesmo processo** (macOS-only vs
  Linux-only). Por desenho, operam em camadas diferentes.
- Nada aqui substitui rotação periódica de credencial (cronograma em
  `docs/plano-adocao-tokens.md`, Fase 4).
