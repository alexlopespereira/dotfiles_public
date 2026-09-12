# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- Ao fazer um PR, faça o merge em seguida por padrão. Não faça o merge apenas se o usuario solicitar isso explicitamente
- quando o usuario pedir pra fazer o merge no github, obedeça
- `homebrew.onActivation.cleanup = "zap"` in `configuration.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- The `zap` cleanup collides with the no-Full-Disk-Access policy (checklist item
  2.2), and the collision is expected. Many cask `zap` stanzas target
  `~/Library/Application Support/com.apple.sharedfilelist`, which is TCC-protected,
  so `darwin-rebuild` prints *"Unable to remove some files. Please enable Full Disk
  Access for your terminal"* and **leaves the cask installed**. Never resolve it by
  granting FDA — that single grant defeats the entire security design. Fix it by
  hand instead: confirm the app is gone from `/Applications`, then
  `rm -rf /opt/homebrew/Caskroom/<cask>`. See `docs/arquitetura-navegadores.md`.
- **Este repo é PÚBLICO.** É a cópia sanitizada de um dotfiles privado: nada aqui
  pode carregar identificador de máquina, de rede privada, de conta em nuvem ou de
  organização. Onde o original tinha um valor real, aqui há um placeholder
  (`SEU-USUARIO`, `SUA-TAILNET`, `projeto-segredos`, …) — mantenha assim. Chave
  privada, token e PEM são proibidos, e a regra valia igual quando o repo era
  privado: privado é clonado para outras máquinas, entra em backup e vira público
  com um clique. Não presuma visibilidade: cheque antes de afirmar. Nunca commite
  evidência de validação de `.no-mistakes/` (que é gitignored); se um pipeline a
  preparar numa branch, remova antes do merge.
- **Runbooks operacionais NÃO moram aqui.** O inventário de acesso remoto, o
  runbook de Salesforce e o runbook da Fase 0 (segredos/canaries) ficam só no repo
  privado, porque descrevem a máquina real. Referências a eles no texto são
  ponteiros, não arquivos deste repo — não tente criá-los aqui.
- `.claude/settings.json` é config de segurança e mora em git, como o `shuru.json`
  (item 7.2). O `deny` codifica as proibições duras deste repo — `shuru upgrade`,
  `gcloud auth application-default login`, `claude auth login` — de modo que um
  agente **não consiga nem pedir**. Não afrouxe o `deny` para destravar uma tarefa;
  se ele bloqueou, a tarefa está errada. O `allow` cobre só inspeção e os gates
  (que são read-only). Cunhagem, rotação, commit, push, `darwin-rebuild` e
  escrita no Keychain ficam de fora **de propósito** — essas devem promptar.
- **Arquivo novo que o nix precisa ler tem que estar no índice do git ANTES de
  avaliar.** Este repo é um flake, e flake em árvore git só enxerga o que está
  rastreado: um `nix/foo.nix` ou `scripts/bar.sh` recém-criado e ainda não
  adicionado é **invisível** para `nix build`, `nix flake check` e `./rebuild.sh`.
  O erro que sai é `path does not exist`, que se lê como problema do arquivo e
  não do índice — ou, pior, a avaliação passa usando a versão antiga do que já
  estava rastreado. `git add` (sem commit basta) antes de qualquer medição.
  Corolário para path relativo: `builtins.readFile ./x` resolve contra o
  **arquivo .nix que escreve a linha**, não contra a raiz do repo — de `nix/` os
  scripts são `../scripts/...`. Ver o cabeçalho de `nix/claude-kit.nix`.
- **O PATH da ativação do home-manager NÃO tem `/usr/bin`.** Ele traz coreutils e
  companhia do Nix, então script chamado por `home.activation.*` que invoque
  binário do sistema pelo nome (`security`, `defaults`, `osascript`, `sw_vers`)
  morre com *command not found* — e, se a falha cair dentro de um `if`/`for`, o
  `set -e` não pega, o script sai 0 e a ativação **reporta sucesso**. Foi assim
  que `ensure-keychain-search-list.sh` passou dias sem garantir nada.
  Chame por caminho absoluto (`/usr/bin/security`, com override por env para o
  teste) e prefira expansão de shell a `grep`/`sed` nesses scripts. O corolário
  do teste: um PATH sem `/usr/bin` é a condição que expõe o defeito; com o PATH
  do shell interativo tudo passa.
- **`security`: duas armadilhas que já destruíram/expuseram chave nesta máquina.**
  (1) O `-T ""` que exige autorização a cada leitura **só vale na criação** — um
  `-U` sobre item existente troca o valor e mantém a ACL antiga, com exit 0 e sem
  aviso. Endurecer exige apagar e recriar, logo exige backup (dentro do Keychain,
  nunca em disco). (2) O `account` (`-a`) precisa ser **descoberto, não suposto**:
  `-U` com `-a` diferente cria um SEGUNDO item sob o mesmo serviço, e a leitura
  por serviço passa a devolver um dos dois sem ordem garantida. Ver
  `keychain_write_hardened()`/`keychain_account()` em `broker/bin/av-broker` e a
  seção "Estado" de `broker/README.md`. (Vale para os itens de gcp,
  salesforce e shopify; o de `github` saiu do broker em 18/ago/2026.)
- **`security -i`: o comentário do `-j` não pode conter aspas.** O parsing é por
  linha; uma aspa no meio encerra o argumento cedo e o erro que sai é um *Usage*
  genérico que não menciona nem aspas nem `-j`. Sintoma fácil de ler como "a
  chave é inválida" quando o problema é a legenda.
- **`PERMISSION_DENIED ... (or it may not exist)` do GCP quase sempre é conta
  errada, não papel faltando.** O GCP funde "sem permissão" e "não existe" numa
  mensagem só para não vazar existência de recurso. Rode `gcloud projects list`
  antes de sair concedendo IAM: se o projeto nem aparece, nenhum papel adicional
  na conta atual resolve. Nesta máquina há **duas** identidades com escopos
  disjuntos — o mapa delas fica no runbook privado de Salesforce.
- **Ser `organizationAdmin` não dá acesso aos projetos da org nem move projeto.**
  O papel tem `projects.get/list/setIamPolicy`, mas **não** `projects.create`,
  `.move` nem `.update`. Mover projeto para dentro da org exige `projectCreator`
  na org **e** direito de mover no projeto — dois lados, duas identidades.
- **Segredo do GitHub Actions é write-only: não serve para recuperar chave.** Não
  há revelar nem API de leitura; o valor só sai dentro de um runner. Se a única
  cópia estiver lá, ela está perdida na prática. Procure antes no GCP Secret
  Manager (`gcloud secrets versions access`), que é a fonte durável aqui.
- **`av bless` não atesta o `av-broker`.** Ele abençoa script cujo *shebang* é o
  próprio `av inject`, e `av save` exige `/dev/tty` (recusa pipe) — e nem por pty
  se deixa dirigir: emite **zero bytes** e trava, então é gesto humano num terminal
  de verdade, não algo que um agente automatize. Não recomende o par `av bless` +
  `av harden`: não existe hardener para script próprio, e o catálogo de hardeners é
  fixo (terceiros). Detalhe medido em `broker/README.md`, "Atestação pelo AV".
- **`av` travado ou `av-broker` falhando? Confira se o app do Automic Vault
  está no ar antes de qualquer outra hipótese.** O serviço de aprovação vem de
  um agente de login registrado só no **primeiro launch do app** — instalar o
  cask não basta, e o `cleanup = "zap"` pode derrubá-lo num rebuild. Sem ele,
  `av save` trava mudo e a cunhagem de gcp/salesforce/shopify falha. Sonda:
  `launchctl list | grep automic` — vazio significa fora do ar (era o caso em
  29/ago/2026); `av open` levanta. Item 3.4 de `docs/reinstall-checklist.md`.
  **Nada disso vale mais para o `gh`:** desde 18/ago/2026 ele é o wrapper
  `scripts/gh-token.sh`, que lê um PAT do login keychain e o injeta por
  ambiente a cada invocação — sem vault, sem gate, sem gravar no chaveiro.
- **A autenticação do `no-mistakes` é `gh auth status --hostname <host>`**
  (`internal/scm/github/github.go`, `Available()`): exit≠0 faz ele pular os
  passos `pr` e `ci` **em silêncio**, e o run termina `passed` parecendo
  completo. Quem os roda é o daemon, então o que importa é o `gh` do PATH
  **dele** ser o wrapper. E o comando sai 1 se QUALQUER conta daquele host
  tiver token inválido, mesmo com a boa ativa — `gh auth logout -h github.com
  -u '<conta>'` resolve.
- **Não redija segredo por regex de formato — descarte a linha.** Você não
  sabe o alfabeto do próximo segredo: `s/gh[oprsu]_[A-Za-z0-9]+/…/` parava no
  primeiro `.` de um JWT e deixou um token vivo vazar parcialmente para o
  contexto de um agente em 01/ago/2026. Use `grep -vi 'Token:'` e afins. Pelo
  mesmo motivo, para medir um segredo sem revelá-lo prefira `${#VAR}` e
  `cut -c1-4`, nunca um `echo` "só do começo" montado à mão.
- **Salesforce: o formulário de *New User* concatena Email e Username.** A tela
  deriva o Username do Email enquanto você digita e o handler do Email re-dispara
  depois, gravando `emailusername` **sem erro e com sucesso aparente** — foi assim
  que nasceram `bot@exemplo.combot@...` e a credencial de produção quebrada de
  31/jul/2026. Releia o Username no registro **salvo**, sempre; para corrigir,
  edite só esse campo — e note que o modal do Lightning **não tem** esse campo,
  só a tela clássica do Setup. (O da sandbox foi corrigido em 02/ago/2026 para
  `bot@exemplo.com.sandbox-etl`; renomear exige mudar o `integration_user` do
  config no mesmo trabalho, senão a cunhagem quebra.) Piora porque o sintoma mente: `sub` inexistente devolve
  `invalid_grant: user hasn't approved this consumer`, a **mesma** frase de falta
  de pré-autorização. Diante dela, confira o username **antes** de mexer em
  Permitted Users, profile ou permission set. Ver o runbook privado de Salesforce, §1.
- **External Client App não tem rotação de Consumer Key/Secret.** Procurado nos
  quatro lugares plausíveis em 31/jul/2026 e ausente em todos; a única saída é
  apagar e recriar o app. Antes de propor isso, note que o segredo costuma estar
  **inerte**: com só `Enable JWT Bearer Flow` marcado, nenhum fluxo o consome, e
  o Consumer Key é o `iss` — público por construção. Diante de suspeita de vazamento,
  revogue a pré-autorização; não cace um botão que não existe.
  Ver o runbook privado de Salesforce, §3.
- **Não use `/limits` para provar um token do Salesforce.** Ele exige *View Setup
  and Configuration* e devolve 403 `API_DISABLED_FOR_ORG` para usuário de
  permission set mínimo — reprovando credencial boa com uma mensagem que aponta
  para a org. A sonda que só pede sessão válida é `/services/data/v61.0/`.
- **O gate do `av-broker` não se aprova com um clique — exige DIGITAR a palavra.**
  `gui_challenge()` monta um `display dialog` com `default answer ""`: a palavra
  do desafio aparece no corpo da janela e tem de ser digitada no campo antes de
  aprovar. Ao pedir aprovação ao usuário, diga isso — "clique em Aprovar" faz a
  janela ficar parada até `expirou`. Custou três cunhagens perdidas em 31/jul/2026.
  Desde 31/jul/2026 o `default button` é **"Aprovar"** (era "Negar"), então o gesto
  é *digitar a palavra e apertar Enter*. Isso não afrouxa nada: quem decide é o
  `typed == word`, e Enter com campo vazio cai em `palavra-errada`, que o chamador
  nega **sem retry** — uma tentativa, falha fechada.
  **O agente NÃO deve ler a palavra e ditá-la**: o desafio é out-of-band
  exatamente para que quem controla o stdio do broker não responda por ele.
- **Diálogo de `osascript` disparado pelo agente APARECE, sim.** Medido em
  31/jul/2026 com `display dialog ... giving up after 25`: retornou
  `button returned:... gave up:false`. Uma versão anterior desta lista afirmava o
  contrário e usava isso para explicar timeouts do gate — era hipótese não medida,
  e estava errada. `sudo` é outra história: aí a falta de TTY é real e a mensagem
  é literal (`a terminal is required to read the password`).
- **O único canal host→guest do shuru é `secrets` do `shuru.json`.** Variável de
  ambiente comum **não** cruza (`shuru run` só tem `--secret NAME=ENV@HOSTS`), e
  com `--offline` nem o segredo declarado cruza — sem rede não sobe o proxy que
  injeta. Medido em 31/jul/2026. Corolário que já gerou receita quebrada: valor
  **não-secreto** que o guest precisa (uma instance URL, um endpoint) não pode
  viajar por env nem ser declarado em `secrets` — o guest receberia um placeholder
  onde precisa de um nome que resolva. Escreva-o literal no comando do guest.
  Ver o runbook privado de Salesforce, §8.
- **Crewmate do firstmate roda no HOST e usa a VM como ferramenta**, nunca dentro
  dela. Decisão do capitão em 01/ago/2026 (opção A). O agente fica onde `git`,
  `gh` e a supervisão do firstmate funcionam; a VM fica sendo runtime descartável
  e offline. Cinco pontos que o brief precisa carregar — comando exato, gate do
  sentinela antes de qualquer medição, `git` não funciona no guest a partir de um
  worktree, o mount é de mão única (tudo sai por stdout), e **meça com o mesmo
  invocador que o CI usa** (`python -m pytest` prepende o CWD ao `sys.path` e o
  console script `pytest` não — medido na #660 do meu-projeto; é a única das
  cinco que produz falso *verde*). Contrato completo e o que reabriria a decisão
  em `docs/plano-firstmate-shuru.md`, bloco no topo.
- **Agrupe medições numa única VM.** Cada boot via `shuru-vm`/`shuru-dev.sh` lê o
  setup-token do Keychain, e cada leitura é um diálogo. Um boot por sondagem
  transforma uma investigação em dezenas de prompts e produz exatamente a fadiga
  de consentimento que o ADR §6.5 tenta evitar — vários `sh -c` num boot só, não
  vários boots.

- **Skill com `disable-model-invocation: true` NAO entra no listing do modelo —
  custo de contexto zero.** Medido em 28/ago/2026 com um controle limpo: em
  `~/.claude/skills/`, `grill-me` e `grilling` diferem so nesse campo, e nesta
  sessao `grilling` aparece na lista de skills e `grill-me` nao. E a diferenca
  entre "instalar 7 skills globais custa ~326 tokens/sessao" e "custa ~124": das
  7 de `nix/kits-externos.nix`, as 5 do mattpocock trazem o campo e so `prd` e
  `ralph` pesam. Antes de recusar uma skill global por orcamento de contexto,
  leia o front-matter dela. Ela continua invocavel pelo usuario.
- **Script de terceiro ancorado em `SCRIPT_DIR` nao vira executavel do store.**
  O padrao `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` seguido
  de leitura/escrita em `$SCRIPT_DIR/...` assume um diretorio de trabalho
  gravavel com irmaos ao lado — e um `bin/` do store nao e nem uma coisa nem
  outra. Ja mordeu duas vezes: o graphify em `checkout-sync-all.sh` (contornado
  removendo os blocos) e o `ralph.sh`, onde e fatal e nao se contorna porque
  patchar codigo de terceiro esta fora de questao. O terceiro idioma para esse
  caso — `home.file` + `executable = true`, arquivo do store, sem
  `writeShellApplication` — e o motivo dele estao em `nix/kits-externos.nix`.
  Lembre tambem que `writeShellApplication` PREPENDA `set -o nounset -o
  pipefail`: para script de terceiro isso e patch, nao empacotamento.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
