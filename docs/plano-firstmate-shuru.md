# Plano: crewmate do firstmate dentro da VM shuru

Gerado em 2026-07-29. Objetivo: o firstmate delegar uma tarefa e o Claude Code
executá-la **dentro** da VM shuru do projeto, mantendo a supervisão do firstmate
no host e as regras de ouro do checklist (5.3: uma VM por projeto montando só o
repo; 5.6: offline por default; segredo nunca no guest).

Cada fato citado abaixo foi medido na máquina em 29/jul/2026, não inferido.

> ## ⚖️ DECISÃO DO CAPITÃO — 01/ago/2026: a VM é ferramenta, não hospedeiro
>
> **Este plano fica parado.** Perguntado como delegar ao firstmate uma tarefa que
> use a microVM, o capitão escolheu a **opção A**:
>
> **O crewmate roda no HOST**, em worktree do treehouse, e **chama a VM como
> ferramenta** para o que precisa de execução isolada. O crewmate **não** roda
> dentro da VM.
>
> A opção B — crewmate dentro do guest, que é o que este documento planeja — não
> é o caminho padrão.
>
> ### Por que
>
> O agente fica onde `git`, `gh` e o próprio firstmate funcionam, e a VM fica
> sendo o que ela é boa em ser: runtime descartável e offline. O isolamento que
> interessa (código de terceiro executando sem rede e sem credencial) já é obtido
> assim, **sem cegar a supervisão** — as tarefas rodadas no guest
> (`vm-scout-1`, `vm-etl-1`, as etapas da Fase 4) foram lançadas fora do
> `fm-spawn.sh`, sem estado em `state/`, sem watcher e sem turn-end.
>
> Medido: a `test-audit-1` (01/ago/2026) fez a auditoria inteira dos 2120 testes
> do meu-projeto por este caminho — worktree no host, toda medição executada
> dentro da microVM — e foi ponta a ponta pelo ciclo do firstmate
> (brief → spawn → scout → promoção → ship → PR #658 → merge → teardown).
>
> ### O contrato operacional da opção A
>
> O brief do crewmate precisa carregar estes quatro pontos. Os quatro foram
> aprendidos custando erro; sem eles o crewmate mede a coisa errada e não sabe:
>
> 1. **O comando exato**, a partir da raiz do worktree:
>
>        ~/Projects/dotfiles/scripts/shuru-vm.sh --offline --from <checkpoint> \
>          -- sh -c '<comando no guest>'
>
> 2. **Gate do sentinela, ANTES de qualquer medição.** `shuru-vm.sh:33` monta
>    `git rev-parse --show-toplevel`, que num worktree é o worktree — mas isso
>    precisa ser *confirmado*, não presumido. Escreva um arquivo no worktree e
>    verifique que ele aparece em `/workspace`. Sem esse gate, uma medição feita
>    contra o checkout principal do capitão passa por medição do worktree.
> 3. **`git` não funciona dentro do guest a partir de um worktree.** O `.git` do
>    worktree é um *arquivo* apontando para `<repo>/.git/worktrees/...`, caminho
>    que o mount não alcança. Trabalho de git no host, execução na VM.
> 4. **O mount é de mão única.** Arquivo escrito dentro do guest **não volta**
>    para o host. Toda medição sai por **stdout**. (Também não há `/usr/bin/time`
>    na VM.) Medido pela `test-audit-1` ao custo de uma rodada perdida.
> 5. **Meça com o MESMO invocador que o CI usa.** Esta é a única das cinco que
>    produz falso **verde** — as outras quatro produzem falso vermelho ou erro
>    barulhento, e falso verde é a direção que passa despercebida.
>
>    Medido na PR #660 do meu-projeto (01/ago/2026): o step do CI chamava o
>    console script `pytest` e a medição na VM usava `python -m pytest`. **`python
>    -m` prepende o CWD ao `sys.path`; o console script não.** Duas suítes que
>    importam os pacotes de topo `business` e `services` passavam na VM e morriam
>    na coleta no runner com `ModuleNotFoundError`. A VM era sistematicamente mais
>    permissiva que o CI, e a diferença não aparecia em lugar nenhum.
>
>    Corolário: o comando que o crewmate roda na VM deve ser **copiado do
>    workflow**, não reescrito de memória. Quando não der para copiar literal,
>    diga na entrega qual foi a diferença — `pytest` × `python -m pytest`,
>    `--cov` ligado ou não, versão de Python, variável de ambiente. Uma medição
>    verde num invocador diferente do de produção não é evidência de que o
>    portão passa.
>
> Vale junto o item de `AGENTS.md` sobre agrupar medições num boot só: cada boot
> lê o setup-token do Keychain e gera um diálogo.
>
> ### O que NÃO fica invalidado
>
> As Fases 0–2 estão feitas e medidas, e o `scripts/claude-shuru` existe e
> funciona — foi ele que rodou as etapas da Fase 4. Nada disso é lixo: continua
> sendo o caminho para rodar um agente headless dentro do guest quando a tarefa
> pedir isso explicitamente (`claude-shuru ... -- -p "<prompt>"`). O que a decisão
> diz é que **isso não é como se delega ao firstmate**, e que a Fase 3
> (adaptador de backend no `fm-spawn.sh`) não é trabalho a puxar agora.
>
> ### O que reabriria esta decisão
>
> Uma tarefa que precise de agente autônomo com rede negada por *default* e ainda
> assim de supervisão do firstmate — hoje a opção A dá isolamento só ao comando
> que o crewmate manda para a VM, não ao crewmate. Se isso virar requisito, o
> caminho é a Fase 3 deste plano, e antes dela as pendências que o
> `firstmate/data/projects.md` já lista (daemon do `no-mistakes` local ao guest,
> origin canônico, credencial pelo proxy).

## O que já está resolvido (não refazer)

- **Escape hatch do firstmate.** `fm-spawn.sh:483` trata string com espaço como
  launch command cru, e as linhas 1506-1513 substituem `__BRIEF__`,
  `__OPINPUT__`, `__MODELFLAG__` e `__TURNEND__` **também nesse caminho**. A
  expansão `"$(__OPINPUT__ encode launch-brief < __BRIEF__)"` acontece no pane
  do HOST, então o brief atravessa o `shuru run` como argv — o guest não precisa
  ver `FM_HOME/data/`.
- **TUI do Claude Code dentro do shuru já funciona** (gates das Fases 1-2;
  `shuru.json._network_platform` registra o preflight medido com a TUI).
- **Custódia do token.** `scripts/shuru-vm.sh` já lê `claude-setup-token` do
  Keychain e injeta `CLAUDE_CODE_OAUTH_TOKEN` só no processo do shuru; o proxy
  troca o placeholder no egress para `api.anthropic.com`.
- **Worktree dentro do repo.** `root = "./"` no config central do treehouse
  garante que o worktree que o `fm-spawn` entrega mora em `<repo>/.treehouse/`,
  então o mount do repo alcança o worktree.
- **Ordem no spawn.** O hook de Stop é escrito em
  `$WT/.claude/settings.local.json` (linha 1337) ANTES do launch no pane
  (~1549). Um wrapper que roda COMO launch command sempre encontra o hook já
  escrito — e como o wrapper roda a cada respawn, correções que ele faça no hook
  se re-aplicam sozinhas.

## Decisões de forma

1. **Um wrapper `claude-shuru` no dotfiles** (novo `scripts/claude-shuru`,
   symlink em `~/.local/bin` via home.nix), invocado pelo captain como launch
   cru:

   ```
   fm-spawn.sh <id> <proj> --harness \
     'claude-shuru --turnend __TURNEND__ -- --model <modelo> --effort <nivel> "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
   ```

   Modelo e effort vão LITERAIS, não por `__MODELFLAG____EFFORTFLAG__`: esses
   placeholders expandem para vazio quando o harness não é `claude` exato (ver
   Fase 3, item 2).

   O NOME importa e não é estético: `fm-spawn.sh:486-487` deriva `HARNESS` do
   basename da primeira palavra do launch cru, e o hook de Stop do claude só é
   instalado quando `case ... in claude*)` casa (linha 1335). `claude-shuru`
   casa; `shuru-claude` não casaria e o spawn silenciosamente não instalaria o
   hook.

2. **Turn-end por relay no host, não por mount do estado.** A alternativa
   (montar `~/Projects/firstmate/state` `:rw` no guest) funcionaria, mas fura o
   "monta só o repo" e expõe o estado de TODAS as tarefas a qualquer crewmate.
   O relay mantém o mount mínimo ao custo de ~1s de latência no sinal.

3. **Rede ligada com a allowlist do projeto.** Crewmate precisa de
   `api.anthropic.com`/`platform.claude.com`; o wrapper passa `--allow-net` e a
   allowlist continua vindo do `shuru.json` do projeto (recusa se ausente, como
   o `shuru-vm.sh` já faz).

## Fase 0 — medições (COMPLETA, 30/jul/2026)

- [x] **0.1 `--mount` da CLI SOMA** aos `mounts` do shuru.json. O guest mostrou
  `mount0` (da CLI) e `mount1` -> `/workspace` (do json) juntos. O wrapper passa
  só o mount adicional.
- [x] **0.2 Mount em caminho absoluto espelhado FUNCIONA** — é o resultado
  decisivo. Com `--mount ${P}:${P}:rw --allow-host-writes` o guest Linux
  materializou `/Users/alex/...` e o `.git` do worktree linked
  (`gitdir: <repo>/.git/worktrees/<n>`) resolveu lá dentro:
  `git status --short --branch` -> `## HEAD (no branch)`.
- [x] **0.3 cwd default do guest é `/`** — o wrapper precisa de `cd` explícito.
- [x] **0.4 Keychain lê sem diálogo** de shell não-interativo:
  `security find-generic-password -s claude-setup-token -w` -> rc=0 em <8s, sem
  prompt. A lacuna 3 é mais simples que o previsto: não precisa pré-autorizar
  ACL nem aprovação via automic-vault no spawn.
- [x] **0.5 Guest tem git 2.47.3 e claude 2.1.220, mas NÃO tem
  `user.name/user.email` globais** — o wrapper passa identidade por
  `GIT_AUTHOR_*`/`GIT_COMMITTER_*` (env, sem escrever no `.git` do host).
  A identidade é a do **agente** (`shuru-agent`), não a do humano: o
  `scripts/shuru-pr.sh:197` já estabelece essa convenção para commits feitos de
  dentro da VM, e como env tem precedência sobre `git config`, passar o
  `user.name` do host sobrescreveria a convenção em silêncio e faria trabalho de
  VM parecer commit do humano.
- [x] **0.6 Boot de checkpoint: ~0,5s**, 3 medições. Metodologia conferida com
  `sleep 2` no guest (total 2,5s), então o 0,5s é overhead real e não medição
  degenerada. Folga enorme para qualquer watchdog.

Duas descobertas que a Fase 0 NÃO previu e só apareceram no gate da Fase 1:

- **A imagem-base só tem root** (`id` -> uid=0; `/etc/passwd` sem outro usuário
  com shell) e o claude **recusa `--dangerously-skip-permissions` como root**.
  `IS_SANDBOX=1` é o escape, e aqui a premissa dele é verdadeira de fato: quem
  confina é a microVM, não o uid. Sem isso o launch morre no primeiro segundo.
  A 0.5 não pegou porque `claude --version` não passa por essa checagem.
- **O `shuru run` avisa "no stdin data received in 3s"** quando stdin não é tty.
  Irrelevante no uso real (o pane dá um tty), custa 3s em teste com `< /dev/null`.

## Fase 1 — wrapper `claude-shuru` (lacunas 2, 3 e 4)

`scripts/claude-shuru`, modelado no `shuru-vm.sh` (mesmas recusas):

1. Resolve `REPO` via `git rev-parse --show-toplevel` a partir do cwd (o pane
   já nasce no worktree; o toplevel do worktree linked é o próprio worktree —
   usar `--git-common-dir` para achar o repo principal).
2. Recusa sem `shuru.json` no repo principal (mesma mensagem do `shuru-vm.sh`).
3. Token: mesmo bloco do `shuru-vm.sh` (Keychain -> env do processo, nunca
   argv, nunca export em shell interativo).
4. Monta o repo principal no MESMO caminho absoluto, `:rw` +
   `--allow-host-writes` (conforme 0.1/0.2).
5. Comando do guest: `sh -c 'cd <worktree> && exec env
   CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude
   --dangerously-skip-permissions <model/effort> <brief-argv>'` — o `env` DENTRO
   do guest fecha a lacuna 4; o brief chega como argv já expandido pelo host.
6. `exec shuru run --from base --allow-net --config <repo>/shuru.json ...`.

**Estado: FEITA e com gate passado** (`scripts/claude-shuru`, commit
5308530). Medido num worktree do treehouse de um repo de prova:
`pwd` dentro do guest = o worktree no caminho espelhado;
`git status --short --branch` = `## HEAD (no branch)`; o arquivo escrito pelo
agente apareceu no worktree do HOST com dono `alex:staff` (não root, então o
`--allow-host-writes` mapeia ownership corretamente); e o token do Keychain
autenticou pelo proxy sem nada em argv.

## Fase 2 — relay de turn-end (lacuna 1)

No wrapper, antes do `exec`:

1. Lê `$WT/.claude/settings.local.json` (fm-spawn acabou de escrever) e troca o
   comando do hook por `touch $WT/.fm-vm-turnend` — caminho válido nos DOIS
   lados porque o mount é espelhado. Acrescenta `.fm-vm-turnend` ao
   `info/exclude` do worktree (mesmo mecanismo `exclude_path` do fm-spawn,
   linha 1327-1333 — é por-worktree, não polui o repo).
2. Sobe um relay em background no HOST: loop de 1s; quando o marker aparecer,
   `touch <turnend-do-host>` (recebido via `--turnend __TURNEND__`) e remove o
   marker. `trap` garante que o relay morre com o wrapper (e portanto com o
   pane — respawn não vaza processo).
3. Como o wrapper roda a cada respawn e o fm-spawn reescreve o hook a cada
   spawn, a ordem "fm escreve -> wrapper corrige" se mantém sozinha.

**Estado: FEITA e com gate passado** (mesmo commit). Verificado: hook reescrito
para o marker; `.fm-vm-turnend` no `info/exclude` do worktree; `turn-ended`
criado no host; marker consumido; nenhum relay órfão.

Um detalhe que o plano não previa e que o gate expôs — o **dreno final**. O hook
do ÚLTIMO turno dispara a milissegundos do claude sair, então o wrapper mataria
o relay antes do poll de 1s enxergar o marker, perdendo justamente o turn-end
que decide o autoarm. `drain_turnend` roda no loop E uma última vez depois do
run. Consequência de forma: com relay ativo o wrapper **não pode** dar `exec`
(um `exec` mataria o trap junto com o shell), então ele espera o filho.

Medições separadas, porque o dreno mascarava o loop:
- **loop**: com marker plantado no meio da sessão, pickup em <1s e wrapper vivo;
- **morte do relay sob SIGKILL** (caso em que o trap NÃO roda): morre pela guarda
  `kill -0 $WRAPPER_PID`. Conferido por PID (`ps -o pid,ppid,command`) e não por
  `pgrep -f claude-shuru` — esse padrão casa também o próprio `shuru run`, porque
  `claude-shuru` vai como `$0` no argv do guest, e duas leituras minhas
  acusaram vazamento que não existia.

Ressalva medida para a Fase 4: o processo filho **não** morre com o wrapper (o
stub sobreviveu reparentado ao init). Sob SIGKILL do pane, portanto, VM órfã é
plausível — é o critério de teardown da Fase 4, não uma suposição.

## Fase 3 — integração com o firstmate

Duas perguntas do plano já têm resposta medida, e ambas mudam o comando:

1. **`config/crew-harness` NÃO aceita launch cru — resposta definitiva NÃO.**
   `fm-harness.sh:82` faz `tr -d '[:space:]'` no arquivo, e `fm-backend.sh:232`
   documenta "a single word on its first non-empty line": um launch com espaços
   viraria uma palavra grudada. E `crew-harness=claude-shuru` (palavra única)
   também não serve, porque `launch_template()` é uma **função dentro do
   fm-spawn.sh** (linha 436), sem diretório extensível — um harness sem template
   aborta o spawn (linha 510). Logo: **o captain passa `--harness` em cada
   spawn**. Mudar isso exigiria patch no clone pinnado, que este plano proíbe.
2. **`--model`/`--effort` do fm-spawn são DESCARTADOS neste caminho.**
   `model_flag_for_harness`/`effort_flag_for_harness` casam `claude` **exato**,
   enquanto a instalação do hook casa `claude*` (prefixo). Essa assimetria é
   exatamente por que `claude-shuru` ganha o hook mas perde os flags: os
   placeholders `__MODELFLAG____EFFORTFLAG__` expandem para **vazio**. Deixá-los
   no template daria a impressão falsa de que os eixos do intake se aplicam —
   então o captain escreve modelo e effort **literalmente** no launch. (Pela
   mesma razão de match exato, `CLAUDE_CONFIG_DIR` não é encaminhado na linha
   1521; aqui é inócuo, porque o guest tem `~/.claude` próprio e o token vem do
   Keychain.)

Comando corrigido — caminho absoluto porque o `basename` é o que importa
(verificado sob bash: `HARNESS=claude-shuru`, casa `claude*`), o que também
dispensa o rebuild do home.nix para testar:

```
fm-spawn.sh <id> <proj> --harness \
  '/Users/alex/Projects/dotfiles/scripts/claude-shuru --turnend __TURNEND__ -- --model <modelo> --effort <nivel> "$(__OPINPUT__ encode launch-brief < __BRIEF__)"'
```

**O risco "quoting do pane" está medido e fechado.** O launch command completo
(com `__TURNEND__` e `__BRIEF__` substituídos como o fm-spawn faz) foi executado
por `eval` a partir do worktree, contra a VM real. O brief codificado chega ao
claude como **um único** argv, com o marcador U+2063, o header
`FIRSTMATE_OP: v1 launch-brief:` e as quebras de linha intactos — verificado das
duas formas: por dump de argv (sem VM) e pelo agente de fato obedecendo o brief
dentro da VM. Gate 5/5: brief recebido, edição no worktree do host
(`alex:staff`), `turn-ended` no state do firstmate, marker consumido, nenhum
relay órfão.

Revalidado contra a imagem-base RECONSTRUÍDA em 30/jul (o `--force` do
`shuru-base-image.sh` apagou e recriou o `base` no meio desta implementação):
guest continua só-root, sem identidade git global, cwd `/`, git 2.47.3,
claude 2.1.220. Todas as premissas do wrapper seguem valendo.

Passos restantes:

3. **Spawn manual** num projeto piloto com task de scout — menor raio de dano.
   Exige um captain: `BRIEF="$DATA/<id>/brief.md"` é artefato de intake, e este
   clone não tem `data/` nem `config/` (nenhum captain rodou aqui ainda).
   Tranquilizador para o pin do nix: `state/`, `data/`, `projects/` e
   `config/*` são todos gitignored, então spawn **não** suja o clone e a
   ativação do home.nix não vai pular o pin.
4. `config/crew-dispatch.json` NÃO participa: a whitelist de harness dele
   (`fm-bootstrap.sh:727`) não expressa o wrapper. Se um dia quiser dispatch por
   regra, é feature pra propor upstream, não pra contornar.
5. Registrar no `data/projects.md` do firstmate (nota do captain) que o projeto
   piloto usa `claude-shuru`.

## Fase 4 — validação de ponta a ponta (gate)

Uma task real de scout num repo de brinquedo, do `fm-spawn` ao teardown. O repo
de brinquedo já existe: `~/Projects/shuru-fm-probe`, com `shuru.json`,
`treehouse.toml` e um worktree do pool já alocado — mantido de propósito (o plano
original mandava descartá-lo, mas ele é justamente o repo desta fase). Os
artefatos dos gates anteriores foram limpos dele, e a task fantasma
`probe-scout-1` foi removida do firstmate home.

Critérios, todos observáveis:

- [ ] linha `spawned <id> harness=claude-shuru ... worktree=<path>` no spawn;
- [ ] VM de pé com a TUI visível no pane do herdr (captura do firstmate
  enxerga o composer — é o teste da "ressalva do adapter": as assinaturas de
  busy/idle do skill harness-adapters valem via serial da VM?);
- [ ] edição do agente aparece no worktree do host (**mecanismo já provado** na
  Fase 3; aqui é confirmar que sobrevive ao caminho do `fm-spawn`);
- [ ] `state/<id>.turn-ended` atualiza a cada turno (relay vivo — **mecanismo já
  provado**, inclusive o dreno do último turno);
- [ ] autoarm/turno seguinte do firstmate reage ao turn-end (a razão de ser da
  lacuna 1);
- [ ] teardown limpo: worktree devolvido ao pool, sem VM órfã (`shuru prune`
  zerado), sem relay órfão.

### Resultado do primeiro spawn real (30/jul/2026, task `vm-scout-1`)

Passaram, com evidência no host:

- `state/vm-scout-1.meta` traz `harness=claude-shuru`, `kind=scout`,
  `backend=herdr` — o basename casou e o hook foi instalado;
- o scout escreveu `relatorio.md` e `sonda.txt` no worktree do host;
- **commitou de dentro da VM**: `b5c3ff6`, autor
  `shuru-agent <shuru-agent@users.noreply.github.com>` — a convenção do
  `shuru-pr.sh` sobreviveu ao caminho do firstmate, e o relatório do próprio
  scout confirma que veio das env vars e não do `user.*` local (`Probe`);
- relay vivo em sessão real: wrapper, subshell do relay e `shuru run` os três de
  pé, e um marker plantado à mão foi relayado em ~1s.

Falta ainda captain para o critério de autoarm, e o teardown.

### Achado de isolamento (levantado pelo próprio scout)

**A guest enxerga o repositório inteiro, não só o worktree.** O scout subiu de
`..` até a raiz real do projeto e encontrou o `.git` completo, os arquivos não
versionados da raiz e **o worktree irmão `1/`, de outra sessão**. Ele podia ler e
escrever tudo isso.

Isso é consequência direta da geometria da Fase 1, não um bug: o `.git` do
worktree linked é um arquivo `gitdir: <repo>/.git/worktrees/<n>`, então sem
montar o repo o git não funcionaria dentro da VM. E satisfaz a regra 5.3 ao pé
da letra ("uma VM por projeto montando só aquele repo"). Mas o raio é maior do
que "o worktree desta task": um crewmate pode mexer no trabalho não commitado de
outro.

**Geometria mais apertada, se quiser fechar isso** — montar DOIS caminhos em vez
do repo inteiro:

- `<worktree>` — os arquivos de trabalho da task;
- `<repo>/.git` — porque o `gitdir:` e o `commondir` apontam para lá.

Esconde os worktrees irmãos, o checkout principal e os arquivos não versionados
da raiz. Não esconde objects/refs (isso é inerente ao git). Custo: se o projeto
guarda coisa ignorada mas necessária na raiz (`node_modules`, `.venv`, caches),
o crewmate perde. Decisão em aberto — muda geometria já testada, então exige
re-rodar os gates das Fases 1-2.

### Ruído conhecido do protocolo

O scout sinalizou o `U+2063` do `FIRSTMATE_OP:` como possível prompt injection
antes de prosseguir. É o marcador do próprio protocolo do firstmate funcionando
como projetado; um agente atento vai marcar isso. Custa um desvio de raciocínio
por spawn. Não é para "consertar" ensinando o agente a ignorar caractere
invisível — isso trocaria uma fricção barata por um risco real.

Se as assinaturas de busy/idle divergirem no serial, o resultado da fase é o
REGISTRO da divergência (que comportamento, em que estado) — é insumo pra
decidir entre ajustar o wrapper (ex.: TERM/dimensões do pane) ou propor um
adapter verificado upstream. Não improvisar heurística própria.

## Riscos e reversão

- **Upstream move o chão.** O acoplamento depende de internals medidos do
  fm-spawn (posição do hook, ordem spawn->launch, formato do settings.local).
  O firstmate está pinnado pelo flake.lock — a cada `nix flake update
  firstmate`, re-rodar a Fase 4 antes de confiar. Anotar isso no comentário do
  input no flake.nix quando a integração existir.
- **Quoting do pane.** O launch cru é digitado no pane pelo backend. A
  interface do wrapper é deliberadamente pequena (2 flags + argv) pra minimizar
  aspas aninhadas; qualquer coisa além disso vai pra DENTRO do wrapper, não do
  launch command.
- **Secondmate fica de fora.** O hook de Stop não é instalado para
  `kind=secondmate` (fm-spawn linha 1335: `[ "$KIND" != secondmate ]`), e
  secondmate roda num firstmate home, não num worktree de projeto. Escopo deste
  plano: ship e scout.
- **Reversão barata em qualquer fase**: nada muda no clone do firstmate (o
  wrapper é dotfiles; o hook editado é por-worktree e refeito a cada spawn) —
  voltar ao harness `claude` normal é só trocar o argumento do spawn.
