# Pedido upstream ao shuru: renovar um segredo numa VM em execução

Rota 3 do `plano-adocao-tokens.md`. **Enviado em 01/ago/2026** por gesto do
capitão: <https://github.com/superhq-ai/shuru/issues/40>.

O texto abaixo é o que foi colado, em inglês, que é a língua do projeto. A única
diferença é a seção Environment, que ganhou `shuru 0.6.5` — versão importa em
pedido de capacidade, e o rascunho tinha esquecido dela.

> ⚠️ **18/ago/2026 — a motivação do GitHub caiu; o pedido continua de pé.**
>
> O corpo da issue argumenta a partir de um **token de instalação de GitHub App
> com TTL de 1 h**. Essa credencial **não existe mais nesta máquina**: em
> 18/ago/2026 o GitHub passou a dois PATs fine-grained de vida longa, que não
> expiram no meio de um run e por isso não precisam de refresh nenhum. A decisão
> e o preço estão no ADR `arquitetura-segredos.md` §6.6 — e ela não é melhoria de
> segurança, é troca de segurança por ergonomia.
>
> O texto **não foi editado nem retirado do upstream**, por três razões:
>
> 1. **Ele ainda vale por outra credencial.** O `CLAUDE_CODE_OAUTH_TOKEN`
>    continua entrando na VM por placeholder resolvido no proxy (ADR §6.4), e um
>    caminho de refresh continua sendo útil para ele — hoje é ~1 ano de validade,
>    mas uma rotação a meio de sessão longa tem o mesmo problema de captura no
>    launch.
> 2. **O argumento estrutural é independente do GitHub.** "O host entrega valor
>    novo ao proxy sem reiniciar a VM" vale para qualquer segredo por placeholder,
>    e é a única forma de a credencial nunca cruzar a fronteira.
> 3. **Editar uma issue aberta para trocar o exemplo confunde quem já a leu.**
>    Se houver resposta upstream, o contexto novo entra em comentário datado, não
>    reescrevendo o corpo.
>
> ⚠️ **Ironia a registrar, porque um leitor honesto notaria sozinho:** a última
> seção do corpo (*"Why this is a security improvement, not just ergonomics"*)
> diz, palavra por palavra, que a alternativa a evitar é *"a long-lived personal
> access token with a wide scope"*. Foi exatamente isso que esta máquina adotou
> dezessete dias depois. O argumento da issue continua correto; o que mudou foi
> que o custo humano do lado certo da balança passou a ser insustentável — 582
> diálogos do Automic Vault em 24 h e 28 senhas do Keychain no mesmo dia
> (02/ago/2026). Não se pretende que a adoção do PAT contradiga a issue: ela
> **confirma** a issue, escolhendo o mal que a issue previu.

---

**Title:** Allow refreshing a proxy secret while the VM is running

**Body:**

## What I'm doing

I run coding agents inside `shuru` microVMs. Credentials never enter the guest:
`shuru.json` declares them as proxy secrets, so the guest only ever holds a
placeholder and the proxy substitutes the real value into the decrypted TLS
stream on the host. This has been working really well — thank you for building it
that way.

The credential is a GitHub App installation token, minted by a local broker that
requires a human approval gesture per mint.

## The problem

GitHub fixes installation tokens at **1 hour** and publishes no refresh endpoint,
so every renewal is a fresh mint. The value is read from the host environment at
`shuru run` time and captured for the life of the VM.

That makes the token's lifetime the *guest's* problem. A long agent run — code
review, tests, a validation pipeline — can exceed an hour. When it does, the
final steps (open PR, read CI) fail with 401 **after** all the expensive work is
done, and there is no way to get a fresh value into a VM that is already up.

Today my only workaround is to split the work into two boots
(`shuru checkpoint create` for the long half, then a second `shuru run --from`
with a freshly minted token for the short half). That works, and
`checkpoint create` is what makes it possible — but it forces a run to be
designed around the credential's clock.

## What would solve it

A way for the **host** to hand the proxy a new value for an already-declared
secret, without restarting the VM. The guest would never notice: the placeholder
is stable, only the substitution target changes.

Some shapes that would work, roughly in order of how much I'd like them:

1. **Re-read on use.** `shuru.json` gains something like
   `"refresh": {"command": ["av-broker", "github", "--emit", "token"]}` or
   `"reread": true` on the `from` env var, and the proxy resolves the value per
   substitution (or when the previous one is older than N seconds) instead of
   caching it from launch.
2. **A control command.** `shuru secret set <NAME> --from-env <VAR>` (or a
   control socket) that updates the running VM's proxy table. Reading from an
   env var rather than argv matters here — the value must not land in `ps`.
3. **A file the proxy watches.** Least favourite, because it puts the secret on
   disk, which is the thing this whole setup exists to avoid.

## Why this is a security improvement, not just ergonomics

With any of these, the credential never crosses into the VM *and* its lifetime
stops mattering to the guest. A compromised guest can **use** the proxy while the
VM lives; it can never **carry a token away**. That is strictly better than the
alternative people will otherwise reach for — a long-lived personal access token
with a wide scope, which is exactly what short-lived scoped tokens exist to
replace.

## Environment

- macOS (Apple Silicon), guest is Linux aarch64
- secrets declared in `shuru.json` as `secrets.<NAME>.from` + `hosts`
- happy to test a branch against a real workload

---

## Notas nossas (não vão na issue)

- O pedido descreve o problema e propõe formas, sem exigir uma. Issue que chega
  com a implementação escolhida costuma ser lida como exigência.
- A Rota 3 **não dispensa a Rota 2**: o proxy resolve *como entregar* o token
  novo, não *quem autoriza* cunhá-lo. Se o refresh existir e a cunhagem
  continuar pedindo diálogo, ganhamos robustez (o run não morre no meio) sem
  ganhar silêncio — o que já é um bom negócio.
- Se a resposta for não, a Rota 1 continua de pé. Nada aqui é bloqueante.
- **18/ago/2026:** a Rota 2 (mandato limitado) perdeu o uso que a motivava, já
  que não há mais cunhagem de GitHub a autorizar. Ela volta à mesa só se o gesto
  de Shopify, GCP ou Salesforce virar rotina. E a Rota 1 (`--stage1`) sobreviveu
  com outra justificativa: não é mais "o token de 1 h morre no meio", é que **a
  etapa longa, que roda código de terceiro com o agente solto, não precisa ver
  credencial nenhuma**.
- **O GitHub deixou de entrar na VM por placeholder.** O PAT da VM
  (`github-pat-vm`) entra por **mount read-only** em `/ghcred/token`, e portanto
  o valor real **existe dentro do guest** — precisamente o que este pedido
  argumenta que não deveria acontecer. Registrado como regressão consciente da
  fronteira host↔guest, não como detalhe. O `CLAUDE_CODE_OAUTH_TOKEN` segue no
  placeholder.
