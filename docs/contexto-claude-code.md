# Orçamento de contexto do Claude Code

Investigação medida em 31/jul e 1/ago/2026, a partir da pergunta "como ajusto
as partes do system prompt e das ferramentas que quero na janela de contexto".
Implementado em `home/.claude/settings.json` (commits `b5b145f` e `355bc34`);
o comentário longo no `home.nix`, junto do `home.activation.claudeSettings`, é
o resumo operacional — este documento é o registro do **método e das medições**.

## Resultado

Prompt de sessão vazia neste repo: **25.8k → 16.4k tokens**. Na sessão
interativa a categoria "System tools" do `/context` caiu de **19.2k para 6.2k**.

O ganho vem de três entradas em `permissions.deny`, e quase todo de uma só.

## O achado que destrava tudo

`permissions.deny` com nome de ferramenta **não apenas bloqueia a chamada: ele
remove o schema da ferramenta do system prompt**. O `--disallowedTools` produz
número idêntico (16419 nos dois), o que confirma que os dois caminhos batem no
mesmo lugar.

Isso é o oposto da intuição de que `deny` é só uma trava de permissão — e é o
que torna o corte possível sem tocar em nada mais.

## Método

```sh
claude -p "responda apenas: ok" --output-format json
```

somando `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
do campo `usage`. Para isolar uma ferramenta já negada:

```sh
claude -p ... --setting-sources project,local --settings '{"permissions":{"deny":["X"]}}'
```

**Piso de ruído: 308 tokens.** Duas rodadas idênticas de baseline diferiram
exatamente nisso, e negar um nome inventado (`NomeFalsoXYZ123`) deu o mesmo
número que negar `Artifact`. Qualquer delta ≤ 308 nesta bancada é ruído.

## Alavancas medidas

| configuração | prompt |
|---|---|
| baseline | 25.8k |
| `--exclude-dynamic-system-prompt-sections` | 25.5k |
| `--strict-mcp-config` (sem MCP) | 24.8k |
| `--disable-slash-commands` (sem skills) | 23.2k |
| **deny de 3 ferramentas (adotado)** | **16.4k** |
| `--tools` curado + `--strict-mcp-config` | 12.7k |
| `--tools ""` **sem** `--strict-mcp-config` | 31.6k ⚠️ |

## Custo individual das ferramentas

Isolado com `--setting-sources project,local`, base ~21.2k:

| ferramenta | custo | decisão |
|---|---|---|
| `Workflow` | **8208** | negada |
| `Agent` | 1818 | mantida |
| `ScheduleWakeup` | ~1500 | negada |
| `ReportFindings` | ~1000 | mantida |
| `Artifact` | ~3300 (só interativo) | negada |
| `SendUserFile` | não existe | removida do deny |

`Workflow` sozinha é a quase totalidade do ganho. As outras entram por serem
inúteis no fluxo daqui, não por serem caras.

## A regra que saiu disso

> **`deny` para o que nunca deve acontecer. `AGENTS.md` para o que deve
> acontecer só sob pedido.**

Foi ela que devolveu `Agent` e `ReportFindings` ao contexto. O `AGENTS.md` já
pedia para não usar subagente sem pedido explícito — mas com a ferramenta
negada o agente **não consegue nem quando pedido**, e o isolamento de contexto
de uma varredura ampla (o subagente lê 40 arquivos e devolve 10 linhas) vale o
preço em repo grande. `ReportFindings` é o que faz `/code-review` e
`/security-review` devolverem achados estruturados (arquivo, linha, veredito)
em vez de texto corrido: negá-la degradaria exatamente o output que se quer ler.

`Workflow` fica negada apesar de ter guardrail próprio. A descrição dela exige
opt-in explícito — a palavra "ultracode", o pedido em palavras suas ("use a
workflow", "fan out agents"), uma skill que mande chamá-la, ou uma workflow
nomeada — e proíbe disparo por decisão do modelo *mesmo em tarefa que se
beneficiaria de paralelismo*. Mas guardrail é texto; as 8.2k de schema são
cobradas em toda sessão, inclusive nas que nunca pediriam.

## Armadilhas medidas

**`--tools` piora.** Passar `--tools` desliga o carregamento sob demanda das
ferramentas MCP e elas entram inteiras no prompt: `--tools ""` deu 31.6k,
*acima* do baseline de 25.8k. Só compensa junto de `--strict-mcp-config`, e aí
se perde o Playwright na sessão.

**`--settings` soma, não substitui.** O bloco passado na flag é mesclado com o
`permissions.deny` do user settings. Foi isso que fez a primeira tentativa de
isolar o custo do `Agent` dar zero — os quatro testes rodaram com todas as
ferramentas negadas de qualquer jeito. Para medir, use `--setting-sources
project,local`.

**`-p` não é a sessão interativa.** `Artifact` e `SendUserFile` respondem
AUSENTE numa sessão `-p`, mas `Artifact` existe no modo interativo: o schema de
settings tem `disableArtifact`/`enableArtifact` e as descrições dos agentes a
citam. A conta fecha pelo `/context`: 13.0k de queda em "System tools", menos
`Workflow` (8.2k) e `ScheduleWakeup` (1.5k), deixa ~3.3k que só podem ser dela.
**Toda medição por script mede a superfície headless; a interativa é maior.**

## Uso sob demanda — hipótese levantada, medida e DESCARTADA

Registrado porque a medição é válida e a pergunta volta: *"dá para usar sob
demanda o que foi negado?"*

`deny` não tem resgate **dentro** da sessão: o schema some, e `ToolSearch` só
alcança ferramentas *diferidas* (as 50 MCP, que por isso custam ~0 — esse é o
mecanismo real de "sob demanda", mas quem decide o que é diferido é o harness).
Medido: `--allowedTools Workflow` **não** vence o `deny`, dá o número idêntico.

A saída seria abrir a sessão com outra fonte de settings. `--setting-sources
project,local` sozinho traz tudo de volta mas derruba junto modelo, hooks e
statusline; com uma cópia do settings sem o bloco `permissions`, preserva:

```sh
claude --setting-sources project,local --settings ~/.claude/settings-full.json
```

Medido: **25.2k tokens**, com o `fable-5[1m]` e os hooks `-axi` intactos.

**Descartado em 1/ago/2026.** Funciona, mas a escotilha custaria uma segunda
cópia do settings (drift silencioso na primeira vez que um hook mudasse, pelo
mesmo motivo do pin do no-mistakes) e um alias a mais para manter. O arquivo
que existia para medir foi apagado.

Consequência assumida: **o `deny` é definitivo dentro da sessão.** O argumento
"com escotilha, negar fica barato" não vale mais. Na prática, para a
`Workflow`: escrever "ultracode" ou "use a workflow" não produz erro — produz
uma ausência silenciosa, e o agente cai no plano B (usar a `Agent`, ou
perguntar). As 8.2k seguem justificando o deny, mas agora sem volta.

## Erros cometidos no caminho

Registrados porque os dois viraram alegação falsa antes de serem pegos, e o
segundo chegou a ser commitado.

1. **`SendUserFile` nunca existiu.** Propus o nome porque soava plausível, sem
   verificar. Negá-lo não muda um token.
2. **Os "308 tokens" do `Artifact` eram ruído.** Reportei como economia medida
   e commitei assim. Só apareceu quando o piso de ruído foi estabelecido — a
   ferramenta de fato custa ~3.3k, mas em outra superfície, e por outra razão.

Ambos vêm da mesma origem: medir sem estabelecer o piso de ruído e sem
confirmar que o alvo existe na superfície medida.

## Encerramento

Nada em aberto. As três pendências que este documento listou em 1/ago/2026
foram resolvidas no mesmo dia:

- **Escotilha sob demanda** (`settings-full.json` gerado na ativação + alias
  `ccfull`) — **descartada**, ver a seção acima. O arquivo órfão foi apagado.
- **Validação de JSON no `claudeSettings`** — **feita**. O
  `home.activation.claudeSettings` agora roda `jq -e .` no arquivo versionado
  antes do `cp` e **aborta o rebuild** se ele não for JSON válido, em vez de
  propagar um settings quebrado que o `claude -p` ignoraria em silêncio.
  Verificado nos três caminhos: JSON válido copia, vírgula sobrando aborta com
  o erro do `jq` na tela, fonte ausente continua só avisando "copia PULADA"
  (esse caso é legítimo, pós-wipe, e por isso não aborta).
