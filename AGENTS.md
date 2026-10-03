# Instruções Gerais

Mantenha aqui decisões e armadilhas úteis à maioria das sessões. Procedimentos
específicos pertencem às skills e aos runbooks; consulte-os quando a tarefa exigir.

## Trabalho e entrega

- Para isolamento, use checkouts independentes, não Git worktrees. Nos slots,
  trabalhe na `main` local e crie a branch de publicação ao abrir o PR.
- Conclua tarefas autorizadas incluindo commit, push, acompanhamento do CI e
  merge rotineiro quando os checks obrigatórios passarem. Uma instrução explícita
  da sessão pode limitar essa entrega; respeite-a. Não use merge administrativo
  para contornar checks ou proteções.
- Preserve alterações alheias à tarefa. Use `gh` para operações no GitHub.
- Specs e tickets ficam em `.scratch/<feature>/`, com critérios de aceite e
  dependências explícitos. Publique-os somente quando solicitado.

## Segurança

- Este repositório é a cópia pública sanitizada, com histórico próprio.
  Preserve placeholders para usuários, máquinas, redes, contas e organizações.
  Nunca versione credenciais, chaves privadas ou evidências locais gitignored.
  Os runbooks de acesso remoto, Salesforce e Fase 0 ficam somente no repositório
  privado; não copie esses inventários operacionais para cá.
- Não reduza sandbox, remova hooks ou afrouxe o `deny` de
  `.claude/settings.json` para destravar tarefas. Essa configuração e `shuru.json`
  são políticas de segurança versionadas; os controles efetivos dependem do
  executor e do perfil selecionado.
- Uma credencial encontrada durante diagnóstico não autoriza seu uso em outra
  ação. Respeite o escopo autorizado e os gates humanos.
- Ao apresentar saída potencialmente sensível, descarte a linha inteira; regex
  de formato pode deixar partes do segredo visíveis. Para medir um segredo,
  informe apenas seu comprimento, sem imprimir prefixos.
- Para documentar comandos bloqueados pelo guard de Keychain, use um `cat`
  isolado com heredoc literal e destino `.md`. Contrato em
  `scripts/hooks/deny-keychain-read.py`.

## Nix e ativação

- `homebrew.onActivation.cleanup = "zap"` em `configuration.nix` é intencional:
  declare os pacotes na configuração. Não troque por `uninstall` ou `none`.
- Não conceda Full Disk Access para resolver falhas de limpeza de casks.
  Consulte `docs/arquitetura-navegadores.md` antes de qualquer remoção manual.
- Adicione arquivos novos ao índice Git antes de avaliar o flake. Paths relativos
  em Nix resolvem a partir do arquivo `.nix` que os referencia, não da raiz.
- A ativação do Home Manager tem PATH restrito. Use caminhos absolutos para
  binários do macOS e forneça o runtime de executáveis com shebang via `env`.
  Verifique falhas também em `if` e loops: `set -e` não cobre todos os casos.
  Teste scripts de ativação com PATH equivalente ao da ativação.
- Scripts de terceiros que dependem de `SCRIPT_DIR` e diretório gravável não
  devem virar executáveis isolados em `bin/` do store. `writeShellApplication`
  também acrescenta opções de shell; preserve a semântica upstream. Critérios
  de empacotamento em `nix/kits-externos.nix`.
- `runtimeInputs` de `writeShellApplication` precede os mocks no PATH. Se uma
  suíte passar no script fonte e falhar no wrapper, confira essa precedência.
  Preserve binários pinados de segurança e use seams explícitas para mocks.
- `rebuild.sh` usa `sudo` e exige autenticação humana. Avise antes de tentar
  uma ativação; builds e checks sem ativação podem ser executados pelo agente.
  Não presuma que GNU `timeout` esteja no PATH; use o timeout da ferramenta.

## Procedimentos sob demanda

- **Instruções globais:** edite as fontes versionadas em `home/AGENTS.md` e
  `home/.claude/CLAUDE.md`, conforme os links definidos em `home.nix`.
- **Keychain e broker:** consulte `broker/README.md` e `broker/bin/av-broker`
  antes de alterar itens. Descubra o account existente; atualizar um item não
  endurece sua ACL. Backup de chaves fica no Keychain, nunca em disco.
  O desafio de aprovação deve ser lido e digitado pelo usuário, nunca pelo agente.
- **MicroVMs:** consulte `shuru.json` e os scripts `scripts/shuru-*.sh`.
  Agrupe sondagens no mesmo boot para evitar prompts
  repetidos. Ambiente comum não cruza host/guest; segredos usam o proxy declarado
  em `shuru.json`, indisponível offline. Valores não secretos necessários ao guest
  devem ser literais no comando, não placeholders de segredo.

## Manutenção destas instruções

Prefira reescrever ou remover a acrescentar. Evite cronologias de incidentes,
comportamentos específicos de versões antigas e fatos já evidentes no código.
Preserve decisões deliberadas e aponte para a fonte do procedimento detalhado.
