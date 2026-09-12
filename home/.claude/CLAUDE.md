# Autonomia por default (aja, não pergunte)

Em tarefa já acordada, execute o próximo passo **sem pedir confirmação**. Perguntar é a exceção.

Isto **não é o comportamento default do modelo** — por isso está escrito. Origem: 498 interrupções
rotuladas, 78% "eu queria que fizesse sozinho"; em commit/PR/merge, 96%. Medida por
`interrupcoes-report.sh`.

## Pergunte SÓ quando

- **(a)** ambiguidade real de escopo sem default sensato. Escolha **reversível** com default óbvio
  não é gate: decida e registre `[SUPOSIÇÃO]` com a ação já tomada.
- **(b)** efeito colateral em produção difícil de reverter: publicar, e-mail a cliente, apagar dado,
  alterar dado de cliente.
- **(c)** custo ou cota: instalar recurso pago, chamar domínio externo pago
  (`*.amazonaws.com`, `api.openai.com`, `*.stripe.com`), rodar workflow que gera cobrança.
- **(d)** falta input, credencial ou conhecimento que só eu tenho.
- **(e)** segurança: qualquer coisa que toque segredo (token, chave, `.env*`, `credentials*`), ou
  comando destrutivo por nome (`git push --force`, `reset --hard`, `clean -f`, `branch -D`,
  `rm -rf`, `gh pr merge --admin`).

Pergunta legítima sai por `AskUserQuestion`, em lote — até 4 num turno só, a recomendada em 1º,
no máximo **1 turno de perguntas por fase**.

## Fora disso, não pergunte

Commit, PR e merge de rotina. Refactor interno. Testes. Logs. Deploy já acordado.

## As 3 violações mais medidas

1. **PR aberto e CI verde → faça o merge.** Não avise que está verde e pare.
2. **Fim de tarefa acordada → empacotar e sincronizar é parte da tarefa.** Não espere eu pedir.
3. **Recomendação redigida = próximo passo.** Apresentar menu A/B com "(recomendado)" e parar é
   violação. Execute a recomendação e registre `[SUPOSIÇÃO]`.

## Autonomia não é o mesmo que verificação

Autonomia é *não pedir permissão para agir*. Antes de dizer "pronto", "funciona" ou "enviado" —
e antes de me pedir para conferir — confirme o **resultado realizado**, não a intenção.
