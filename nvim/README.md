# Neovim — especificação de ambiente

Receita para reconstruir, numa máquina limpa, o Neovim que foi montado e depurado
na sessão de 09–10/set/2026.

**Este documento prescreve *o quê*, não *o como*.** Não há comando aqui de
propósito: gerenciador de pacote, caminho de config e nome de binário mudam entre
macOS, Linux e Windows, e comando fixado em documento envelhece mal. Um agente
(ou uma pessoa) lê o resultado esperado e escolhe o meio adequado à plataforma
que tem na frente.

Quem executa deve tratar cada seção como um requisito com critério de aceite, e
**verificar** o critério em vez de presumir que o passo funcionou.

> Já existe uma config de Neovim neste repo em `home/.config/nvim/`, gerenciada
> via nix/home-manager para macOS. Ela é **outra** — mais enxuta, com tema
> rose-pine. Esta pasta descreve a config baseada em NvChad e não substitui
> aquela; se as duas forem instaladas na mesma máquina, apenas uma pode ocupar o
> diretório de config padrão do Neovim por vez.

---

## 1. Resultado esperado

Ao final, o editor deve entregar:

- Interface pronta para uso, com tema, barra de status, abas e árvore de arquivos.
- Busca difusa de arquivos **por nome** e busca **por conteúdo** dentro do projeto.
- Destaque de sintaxe estrutural (treesitter) para as linguagens do dia a dia,
  incluindo blocos de código embutidos em Markdown.
- Autocompletar e navegação de código por servidor de linguagem (LSP).
- Formatação e diagnóstico via ferramentas externas.
- Operações de git de dentro do editor.
- Terminal embutido.
- Execução de teste sob o cursor / do arquivo / da suíte.

---

## 2. Pré-requisitos do sistema

Instale por **capacidade**, não por nome de pacote — o nome varia por plataforma.

| Capacidade | Por que é necessária | Critério de aceite |
|---|---|---|
| Neovim recente (0.11 ou maior) | A config usa a API de LSP moderna (`vim.lsp.config`/`enable`) | O editor abre e reporta versão ≥ 0.11 |
| Git | Gerenciador de plugins e integração de git | Disponível no PATH |
| Busca em texto de alta performance (ripgrep) | É o motor da busca por conteúdo; sem ela a busca fica lenta ou não funciona | Disponível no PATH |
| Fonte Nerd Font | Ícones da interface; sem ela aparecem quadrados | Instalada **e selecionada no terminal** |
| Compilador C | Compila os parsers de treesitter | Ver seção 5, que depende de decisão |
| Node.js | Vários servidores de linguagem e formatadores são distribuídos por npm | Disponível no PATH |

Dois pontos que costumam ser esquecidos:

- Instalar a Nerd Font **não basta** — o terminal precisa estar configurado para
  usá-la. É ajuste no terminal, não no editor.
- O terminal precisa entregar as teclas ao editor. Alguns terminais capturam
  combinações com `Ctrl` para si. Se um atalho não responder, suspeite do
  terminal antes da config.

---

## 3. Config base

Adote o **starter do NvChad** como ponto de partida, em vez de escrever config do
zero. Ele já resolve interface, tema, LSP, autocompletar, árvore de arquivos,
busca e formatação de forma coerente.

Requisitos:

- A config deve viver no diretório de config de usuário do Neovim da plataforma,
  e os plugins no diretório de dados — **não** presuma caminhos de Unix.
- O starter é um **template**, não uma dependência: depois de copiado, o vínculo
  com o repositório de origem deve ser cortado, para que a config passe a ser do
  usuário e possa ser versionada sem conflito.
- Na primeira execução os plugins são baixados. Confirme que terminou sem erro
  antes de seguir — instalação parcial produz sintoma confuso depois.

Critério de aceite: o editor abre com a interface do NvChad, sem mensagem de erro.

---

## 4. Funcionalidades a acrescentar

O NvChad não cobre tudo. Acrescente as capacidades abaixo, **verificando antes se
a config base já não resolve** — instalar plugin redundante é fonte de conflito de
atalho.

### Acrescente

| Capacidade | O que deve passar a ser possível |
|---|---|
| Diretório como buffer editável | Renomear/mover/apagar arquivo editando linhas de texto e salvando, em vez de menu |
| Camada de git completa | Status, diff, blame e histórico de dentro do editor |
| Menus nativos dentro do buscador | Listas de escolha do editor (ex.: ações de código do LSP) aparecem na interface de busca, não num prompt cru |
| Linters/formatadores externos como LSP | Ferramentas de linha de comando entregam diagnóstico e formatação como se fossem servidor de linguagem |
| Executor de testes | Rodar o teste sob o cursor, do arquivo ou da suíte, com o resultado num terminal do editor |

### Não acrescente (a base já resolve)

- Árvore de arquivos e tela inicial — já existem; instalar concorrente gera dois
  atalhos para a mesma coisa.
- Tema — a base traz uma coleção própria, incluindo equivalentes dos temas
  populares. Prefira selecionar um existente a instalar outro.
- Integração com multiplexador de terminal — só faz sentido onde o multiplexador
  existe. Em plataforma sem ele, é peso morto que ainda sequestra atalhos de
  navegação entre janelas.

### Decida caso a caso

- Visualizadores de nicho (ex.: preview de especificação de API) costumam exigir
  instalação **global** de pacote externo na etapa de build. Vale confirmar com o
  usuário antes; não é dependência de editor.

---

## 5. Treesitter: a decisão que define se funciona

Esta é a parte que mais consome tempo, e o erro comum é tratá-la como problema de
compilador quando é **decisão de qual linha do plugin usar**.

O plugin de treesitter tem duas linhas de desenvolvimento incompatíveis entre si:

| | Linha nova | Linha antiga |
|---|---|---|
| Como compila parser | Delega a um utilitário externo dedicado | Compila direto, com o compilador C que achar |
| Compilador aceito | Só o compilador nativo da plataforma (no Windows, o da Microsoft) | Vários, incluindo alternativas leves e portáveis |
| Queries de sintaxe | Mantidas para o Neovim atual | Congeladas em 2024 |
| API de configuração | Nova | É a que o starter do NvChad espera |

**Regra de decisão:**

1. Se o compilador nativo da plataforma já existir (comum em macOS e Linux),
   prefira a **linha nova** — as queries são mantidas e não exigem remendo.
2. Se ele **não** existir e instalá-lo for caro (no Windows são vários GB e
   instalação com privilégio administrativo), use a **linha antiga**, que aceita
   um compilador C leve e portátil. Aí a seção 6 passa a ser obrigatória.

Independentemente da escolha:

- Fixe explicitamente a linha usada. Não deixe implícito — o padrão do plugin
  mudou, e config escrita para uma linha falha em silêncio na outra.
- Declare a lista de linguagens desejadas e confirme que **todas** compilaram.
- Critério de aceite: abrir arquivo de cada linguagem declarada e ver destaque
  estrutural; e abrir um Markdown com bloco de código e ver o bloco destacado
  **na linguagem dele**, não como texto.

---

## 6. Se usar a linha antiga do treesitter: corrigir as diretivas

Obrigatório apenas no caminho 2 da seção anterior.

**Sintoma:** ao abrir ou pré-visualizar certos arquivos, o editor acusa tentativa
de chamar um método inexistente sobre valor nulo, vindo do módulo de treesitter do
próprio Neovim. Aparece com mais frequência em Markdown (pré-visualização na busca
de arquivos) e em shell script com *here-document*.

**Causa:** a linha antiga registra diretivas de query pedindo o formato antigo de
resultado — um nó por captura. O Neovim atual ignora esse pedido e passa a
entregar **lista** de nós. A diretiva então repassa uma lista onde se espera um
nó só.

**O que fazer:** re-registrar, na config do usuário, as diretivas afetadas, agora
desembrulhando a lista. São três, e cobrem estes casos:

| Diretiva | Serve para | Linguagens atingidas |
|---|---|---|
| Linguagem a partir da legenda do bloco | ` ```python ` injeta Python no bloco | Markdown |
| Nome de linguagem sem diferenciar maiúsculas | `<<PYTHON` injeta Python no here-document | Shell, Ruby, HCL, PHP |
| Linguagem a partir do tipo MIME | `<script type=...>` injeta a linguagem certa | HTML |

**Corrija a diretiva, não a query de cada linguagem.** Remendar o arquivo de query
de cada linguagem resolve um caso por vez e nunca termina; a diretiva é o ponto
único.

Critério de aceite: Markdown com bloco de código, e shell com here-document
nomeado, ambos abrem sem erro **e** com o trecho embutido destacado na linguagem
correta. "Parou de dar erro" não é suficiente — verifique que a injeção acontece.

---

## 7. Shell e terminal embutido

Requisito que só morde onde o caminho do interpretador de comandos tem **espaço**,
ou onde o terminal exporta um interpretador que não é o nativo da plataforma.
Na prática: Windows com Git Bash. Em macOS e Linux normalmente não há o que fazer.

**Sintoma:** abrir o terminal embutido falha dizendo que o programa não é
executável, e o caminho aparece **entre aspas** na mensagem.

**Causa:** o editor herda o interpretador do terminal que o lançou e, se o caminho
tem espaço, guarda o valor entre aspas — que é o correto para executar comando,
mas inválido para gerar processo, onde se espera nome de programa puro.

**Restrições que a solução precisa respeitar** (as duas ao mesmo tempo, e é isso
que torna o problema não-trivial):

- Executar comando externo tem que funcionar — a camada de git, o instalador de
  servidores de linguagem e o executor de testes dependem disso.
- Gerar o processo do terminal embutido tem que funcionar.

**Forma da solução:**

1. Fixe o interpretador na config, de modo **determinístico**, sem depender de
   como o editor foi aberto. Prefira o nativo da plataforma, que é contra o qual
   os plugins são testados.
2. Ao trocar o interpretador, troque **todo o conjunto de opções relacionadas**
   (flag de comando, redirecionamento, encadeamento, aspas). Mexer só no
   interpretador deixa a execução de comando externo quebrada **em silêncio** —
   ela passa a devolver vazio em vez de erro.
3. Se o usuário quiser o terminal embutido num interpretador diferente do fixado,
   troque o valor apenas **durante** a abertura do terminal e restaure em
   seguida. É seguro: o processo já nasceu.

**Cuidado ao localizar o interpretador:** buscar pelo nome no PATH pode encontrar
o lançador de um subsistema Linux em vez do programa nativo, e ele como
interpretador do editor quebra o tratamento de caminhos. Prefira caminhos
conhecidos e só aceite o resultado da busca se ele estiver onde se espera.

Critério de aceite: executar comando externo devolve saída **e** o terminal
embutido abre — os dois na mesma sessão, e com o editor aberto a partir de cada
terminal que o usuário usa.

---

## 8. Atalhos

Defina os atalhos descritos em `nvim-atalhos.sh`, nesta mesma pasta. O script é a
fonte da verdade: ele lista tecla e função de cada um, e serve tanto de
especificação para quem configura quanto de consulta para quem usa.

Princípios que a sessão fixou:

- **Preserve os atalhos da config base** e acrescente os novos ao lado. Vários
  atalhos populares de tutorial colidem com os da base; quando houver colisão,
  mantenha o da base e adote um apelido para o novo, em vez de sobrescrever.
- **Descreva todo atalho.** A base traz um menu que se abre ao segurar a tecla
  líder; atalho sem descrição não aparece nele e some da vista.
- Prefira convenções já difundidas na comunidade a invenções locais.

Critério de aceite: cada atalho listado no script existe de fato no editor e
aponta para a função descrita — verificável pelo próprio editor, que sabe listar
seus mapeamentos e dizer de qual arquivo cada um veio.

### O comando de consulta

`nvim-atalhos.sh` roda direto, sem argumento para ver tudo, ou com um termo para
filtrar (`telescope`, `git`, `teste`, `buffer`...). O filtro casa por palavra
inteira na linha e por pedaço no nome da seção, então um termo genérico traz a
seção inteira sem arrastar coincidência de substring junto.

É POSIX `sh` com `awk`: roda igual no zsh do macOS, no bash do Linux e no Git Bash
do Windows. Suprime cor sozinho quando a saída não é terminal, e respeita
`NO_COLOR`.

Ele precisa ser **um comando**, não um caminho de arquivo: digitar
`nvim-atalhos` de qualquer diretório tem que funcionar. Isso exige um nome
estável no `PATH`, sem a extensão `.sh` — a extensão é detalhe do arquivo, não
do comando.

Duas exigências que o mecanismo escolhido precisa satisfazer:

- **O arquivo do repo continua sendo o original.** O que vai para o `PATH`
  aponta para ele; não é cópia. Atalho é lista viva — muda junto com a config do
  editor — e cópia significa duas versões divergindo em silêncio.
- **Editar a lista não pode exigir reinstalar nada.** Acrescentar um atalho é
  uma linha; se custar um passo de build, para de acontecer.

O mecanismo em si varia: onde houver um gerenciador de configuração declarativo,
declare ali, do mesmo jeito que os outros comandos do repo já são declarados;
onde não houver, basta um lançador de uma linha num diretório que já esteja no
`PATH`. O critério não é qual mecanismo, é que as duas exigências acima
continuem valendo depois.

Critério de aceite: abrir um terminal novo, em um diretório qualquer, digitar o
nome do comando e ver a lista; acrescentar um atalho ao arquivo do repo e ver o
novo item na chamada seguinte, sem nenhum passo intermediário.

---

## 9. Verificação final

Não declare pronto sem verificar. Erro de config costuma se manifestar só quando
se abre um arquivo real de uma linguagem específica, não na abertura do editor.

- [ ] Editor abre sem nenhuma mensagem de erro
- [ ] Abre **arquivo real** de cada linguagem declarada, sem erro e com destaque
- [ ] Markdown com bloco de código: bloco destacado na linguagem dele
- [ ] Shell com here-document nomeado: trecho destacado
- [ ] Busca por nome de arquivo retorna resultado
- [ ] Busca por conteúdo retorna resultado (confirma que o buscador de texto está
      sendo encontrado)
- [ ] Terminal embutido abre
- [ ] Execução de comando externo devolve saída não-vazia
- [ ] Todos os atalhos do `nvim-atalhos.sh` existem e vêm do arquivo esperado
- [ ] `nvim-atalhos` roda **pelo nome**, de um terminal novo e de um diretório
      qualquer — e reflete o arquivo do repo sem passo intermediário
- [ ] Ícones aparecem como ícones — se vierem quadrados, é fonte do terminal

Vale repetir a verificação com o editor aberto a partir de **cada** terminal que o
usuário costuma usar. Parte dos problemas desta sessão só aparecia conforme o
terminal de origem, porque o ambiente herdado muda.

---

## 10. Método de diagnóstico

O que efetivamente resolveu os problemas desta sessão, na ordem em que vale tentar:

1. **Bissecção com o editor em modo limpo.** O editor sabe abrir ignorando toda
   config e plugin. Se o problema some assim, a causa está na config ou num
   plugin — nunca no editor. Isso separa metade do espaço de busca em um passo,
   e foi o que apontou a culpa para a query do plugin em vez do runtime.
2. **Leia o rastro de pilha até o fim.** Ele nomeia o arquivo e a linha. Numa
   ocasião o rastro apontava um atalho diferente do que o usuário achava ter
   apertado, e noutra apontava um arquivo de plugin que a config já deveria ter
   substituído — o que revelou que a sessão em execução era anterior à correção.
3. **Confirme que o que está rodando é o que está em disco.** Config só entra em
   vigor em processo iniciado depois da edição. Comparar o horário de início do
   processo com o de modificação dos arquivos transforma suspeita em fato.
4. **Meça a extensão antes de corrigir.** Antes de remendar, vale descobrir
   quantos casos o defeito atinge: às vezes é um arquivo (e o remendo cirúrgico
   se justifica), às vezes é uma camada inteira (e aí o remendo por caso é
   desperdício).
5. **Teste a matriz quando houver mais de uma restrição.** Duas exigências
   conflitantes sobre a mesma opção se resolvem enumerando as combinações e
   medindo cada uma, não escolhendo por intuição.
6. **Verifique a funcionalidade, não a ausência de erro.** "Parou de estourar"
   e "voltou a funcionar" são estados diferentes.
