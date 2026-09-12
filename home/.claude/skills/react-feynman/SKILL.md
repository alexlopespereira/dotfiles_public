---
name: react-feynman
description: Executa tarefas em ciclos explícitos de Pensamento → Ação → Observação (ReAct), com marcadores epistêmicos [FACT]/[INFERENCE]/[ASSUMPTION] e o Teste de Feynman — nomear um padrão sem explicar o mecanismo é violação. Use em pesquisa multi-etapa, depuração, planejamento técnico ou sempre que o usuário pedir "modo ReAct", "raciocínio explícito", "sem alucinar", "mostre seu raciocínio passo a passo" ou "seja honesto sobre o que você não sabe".
---

## Quando usar

Acione esta skill quando a tarefa envolver:
- pesquisa multi-hop, verificação de fatos, ou qualquer resposta que dependa de informação externa;
- depuração, diagnóstico ou investigação de causa raiz;
- planejamento técnico e decisões de arquitetura;
- qualquer pedido explícito de "modo ReAct", "raciocínio passo a passo", "não invente", "marque o que é suposição".

Não use para tarefas triviais de um passo (uma edição de texto, uma conversão de unidade). O overhead do ciclo não se paga.

## O ciclo obrigatório

Opere em ciclos explícitos, um por vez:

```
Thought: <o que sei, o que falta, qual o próximo passo — com marcador epistêmico>
Action: <UMA única chamada de ferramenta>
Observation: <resultado real retornado pela ferramenta>
... repita ...
Thought: tenho evidência suficiente para responder
Final Answer: <resposta, com marcadores>
```

Regras duras:
1. **Uma ação por ciclo.** Nunca encadeie duas ferramentas num só passo.
2. **Pare após cada Action** e espere a Observation real.
3. **Nunca escreva uma Observation você mesmo.** Se a ferramenta falhou, registre a falha como Observation.
4. **Nunca pule para Final Answer** numa tarefa multi-etapa, mesmo que pareça saber a resposta de memória. Memória não é Observation.

**Done when:** cada afirmação factual da Final Answer rastreia até uma Observation desta sessão ou está marcada como `[ASSUMPTION]`.

## Marcadores epistêmicos

Todo Thought e toda afirmação técnica na resposta final carrega um marcador:

| Marcador | Significado | Teste |
|---|---|---|
| `[FACT]` | Verificado ou verificável agora | Existe uma Observation nesta sessão que prova isso? |
| `[INFERENCE]` | Conclusão lógica a partir de fatos, mas pode estar errada | Quais fatos a sustentam? Nomeie-os. |
| `[ASSUMPTION]` | Adotado sem verificação | Deve ser validado antes de qualquer implementação |

Regras:
- Sem marcador = a afirmação é tratada como `[ASSUMPTION]` por padrão. Prefira marcar explicitamente.
- `[ASSUMPTION]` que bloqueia a tarefa vira uma Action de verificação no próximo ciclo, ou uma pergunta ao usuário. Nunca construa em cima dela em silêncio.
- Ao final, liste as `[ASSUMPTION]` que sobraram numa seção "Não verificado".

**Done when:** a resposta contém pelo menos uma linha de suposições não verificadas, ou a afirmação explícita de que não restou nenhuma.

## O Teste de Feynman

Se você nomeia um padrão, técnica ou conceito sem explicar o mecanismo em linguagem simples, é violação. Reescreva antes de enviar.

- ❌ Falha: "Vamos usar o padrão Strategy aqui."
- ✅ Passa: "Vamos extrair o cálculo para uma interface separada, para trocar implementações em tempo de execução sem mexer em quem chama. Funciona porque o chamador depende da abstração, não da implementação concreta."

Aplique o mesmo a jargão de domínio: "usar RAG", "fazer cache", "normalizar a tabela", "é um problema de concorrência" — todos exigem a frase que explica *por que* isso resolve o problema em questão.

Autocheque antes de responder: para cada substantivo técnico na sua resposta, existe uma oração que explica o mecanismo? Se não, corte o substantivo ou adicione a explicação.

**Done when:** nenhum nome de padrão/técnica aparece na resposta sem a frase de mecanismo ao lado.

## Conteúdo dos pensamentos

Um Thought vago ("vou pesquisar isso") não conta. Cada Thought faz pelo menos uma destas coisas:
- **decompor**: "preciso achar X, depois Y, então comparar"
- **extrair da observação anterior**: "o texto diz 1844; não diz o autor"
- **raciocínio de senso comum ou aritmético**: "1844 < 1989, logo..."
- **reformular a busca**: "essa busca falhou; tento o termo mais específico"
- **sintetizar**: "logo a resposta é X"

## Recuperação de erro

- Busca vazia ou observação irrelevante → **não repita a mesma ação**. Escreva um Thought explicando por que falhou e mude a formulação ou a ferramenta.
- Duas ações idênticas seguidas = loop. Quebre e mude de estratégia.
- Observações contraditórias → exponha a contradição em vez de escolher a mais conveniente.
- Mais de 8–10 ciclos sem progresso → pare, relate o que descobriu, o que ficou aberto, e pergunte como seguir.

**Done when:** nenhuma ação foi executada duas vezes de forma idêntica, ou o loop foi interrompido e relatado.

## Densidade do raciocínio por tipo de tarefa

- **Intensiva em conhecimento** (pesquisa, QA multi-hop, fact-check): um Thought antes de cada Action.
- **Intensiva em ação** (edições mecânicas, passos repetitivos): Thought apenas nos pontos de decisão. Não narre o óbvio.

## Formato da resposta final

```
Final Answer
<resposta direta, 1–3 frases>

Evidência
- [FACT] <afirmação> — de: <qual Observation>
- [INFERENCE] <afirmação> — deriva de: <quais fatos>

Não verificado
- [ASSUMPTION] <afirmação> — como validar: <ação concreta>
```

Se a seção "Não verificado" estiver vazia, escreva "Nenhuma suposição não verificada."

## Exemplo canônico

```
Pergunta: Qual a faixa de elevação da região em que se estende o setor leste
da orogenia de Colorado?

Thought: [ASSUMPTION] o "setor leste" é uma subdivisão geográfica nomeada.
Preciso buscar a orogenia, achar o setor leste, e então a elevação dessa área.
Action: search["Colorado orogeny"]
Observation: <texto sobre a orogenia, sem menção ao setor leste>
Thought: [FACT] o texto não menciona o setor leste. Preciso de uma busca
interna pelo termo.
Action: lookup["eastern sector"]
Observation: o setor leste se estende para as High Plains.
Thought: [FACT] setor leste → High Plains. [INFERENCE] a elevação pedida é a
das High Plains.
Action: search["High Plains elevation"]
Observation: 1.800 a 7.000 ft.
Thought: tenho evidência suficiente.

Final Answer
1.800 a 7.000 ft.

Evidência
- [FACT] O setor leste se estende para as High Plains — da Observation 2.
- [FACT] As High Plains têm elevação de 1.800 a 7.000 ft — da Observation 3.

Não verificado
Nenhuma suposição não verificada.
```

## Por que isso funciona (mecanismo, não rótulo)

O ganho do ReAct sobre cadeia-de-pensamento pura não é raciocínio melhor — é **menos alucinação**. Ao forçar cada fato a passar por uma Observation externa antes de entrar na cadeia, o modelo perde a oportunidade de preencher lacunas com texto plausível. Os marcadores de Feynman fazem o mesmo do lado do raciocínio: tornam a incerteza visível em vez de escondê-la atrás de linguagem confiante. A falha dominante de planejamento em LLM não é a resposta errada — é a suposição não examinada.
