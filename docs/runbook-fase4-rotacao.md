# Runbook — Fase 4: rotação e revisão periódicas

Higiene contínua de `plano-adocao-tokens.md`. O que dá para automatizar está em
`av-broker rotate` / `scripts/verify-hardening.sh`; este documento cobre o que
exige a UI ou o seu julgamento.

> ⚠️ **Emenda de 18/ago/2026 — o GitHub saiu do broker.** Não há mais chave de
> GitHub App para rotacionar por comando, nem `av-broker rotate --target github`,
> nem `av-broker review`. O acesso ao GitHub são **dois PATs fine-grained de
> vida longa** (`github-pat`, `github-pat-vm`), e a rotação deles é **manual, na
> UI do github.com** — seção 1. Isso não é melhoria de segurança: é troca de
> segurança por ergonomia, registrada no ADR `arquitetura-segredos.md` §6.6.
> **GCP, Salesforce e Shopify seguem no broker, sem mudança nenhuma.**

**Por que rotacionar algo que está no Keychain sob o AV.** Não é ritual: as
chaves-mãe do broker são a raiz de confiança de tudo que ele cunha, e não têm
expiração. Sem rotação, um comprometimento silencioso vale para sempre. A
rotação transforma "para sempre" em "no máximo um trimestre". Para os PATs do
GitHub o argumento é o **mesmo, e mais forte**: eles não expiram, não são
gateados e são legíveis por qualquer processo seu — se você não rotacionar, nada
rotaciona.

## Cadências

| O quê | Cadência | Comando |
| --- | --- | --- |
| **PATs do GitHub** (`github-pat`, `github-pat-vm`) | trimestral | **manual, na UI** — seção 1 |
| Chave da SA-broker (GCP) | trimestral | `av-broker rotate --target gcp` |
| `claude setup-token` | semestral | `av-broker rotate --target anthropic` |
| Revisão dos PATs (escopo, repos, expiração) | trimestral | **manual, na UI** — seção 4 |
| Revisão das SAs de projeto | trimestral | seção 4 |
| Hardening geral | mensal | `scripts/verify-hardening.sh` |

⚠️ A primeira e a quarta linhas são as únicas sem comando, e é exatamente por
isso que são as mais fáceis de esquecer. Ponha a data de expiração dos dois PATs
num lembrete de calendário no dia em que os criar; a máquina não vai avisar.

`av-broker rotate` **sem argumento** mostra a idade de cada credencial e o que
já venceu; `av-broker doctor` também acusa vencimento. A idade sai do log JSONL
(fonte de verdade) e cai para a data de criação do item do Keychain enquanto não
houver rotação registrada — `security -U` preserva o `cdat`, então o Keychain
sozinho mentiria dizendo que uma credencial rotada é antiga.

---

## 0. Preflight — 30 segundos que evitam diagnóstico errado

Faça **antes** de gerar chave nova. Nenhum destes passos é opcional.

```sh
launchctl list | grep automic     # esperado: com.automicvault.menubar-helper
av-broker doctor --deep           # um diálogo por chave; responda "Permitir"
```

⚠️ **Se o app do Automic Vault não estiver no ar, pare e suba antes**
(`open -a "Automic Vault"`). O serviço de aprovação vive num agente de login que
só é registrado no **primeiro launch do app**; instalar o cask não basta, e o
`cleanup = "zap"` pode derrubá-lo num rebuild. `av save` fica **travado sem
imprimir um byte** em vez de reclamar. Medido em 29/jul/2026; detalhe no item
3.4 de `docs/reinstall-checklist.md`.

*(Até 18/ago/2026 este aviso incluía o `gh`, que mentia dizendo "The token in  is
invalid" e mandava rodar `gh auth login`. O `gh` deixou de depender do AV: ele lê
o PAT direto do login keychain. O sintoma some junto — e o conselho de nunca
rodar `gh auth login` continua valendo, agora aplicado pelo próprio wrapper.)*

Rodar `doctor --deep` **antes** importa porque o `doctor` comum só checa presença
da chave. Entrar numa rotação sem saber se a chave atual ainda é válida é como
trocar o pneu sem conferir se o macaco funciona.

---

## 1. Rotação dos PATs do GitHub (trimestral) — **manual, na UI**

> **Reescrita em 18/ago/2026.** Esta seção descrevia a rotação da chave privada
> do GitHub App via `av-broker rotate --target github`, com verificação
> pré-troca (`GET /app`), folga de 25 chaves e zero downtime. **Nada disso
> existe.** O alvo `github` foi removido do broker junto com o App. Ficou o que
> um humano faz na UI, e ficou registrado que essa é uma **perda**: automação com
> verificação virou gesto que ninguém verifica.

Não há comando. São dois tokens, e cada um se rotaciona sozinho — de preferência
**um de cada vez**, para que um erro não deixe host e VM sem acesso ao mesmo
tempo.

Para cada token, nesta ordem (**crie o novo antes de revogar o velho**; o GitHub
permite vários PATs vivos, então não há motivo para ficar sem acesso no meio):

1. **<https://github.com/settings/personal-access-tokens>** → *Generate new
   token*, fine-grained, com o **mesmo escopo do que está sendo substituído** —
   ou menor. Rotação é hora boa para encolher: repo que saiu de trabalho ativo
   sai da seleção.
2. Grave por cima do item existente. O `set` usa `-U`, então **regravar é a
   rotação**; não apague antes:
   ```sh
   gh-pat set host     # ou: gh-pat set vm
   ```
3. Verifique **antes** de revogar o velho. Esta é a etapa que o broker fazia por
   você e agora é sua:
   ```sh
   gh-pat check                  # o item continua presente
   gh api user --jq .login       # 200 -> o token novo autentica
   gh api repos/<owner>/<repo> --jq .full_name   # 200 -> o escopo alcança
   ```
   Para o `github-pat-vm`, o teste equivalente é subir uma VM e deixá-la falar
   com o GitHub — o token dela não é usado por nenhum comando do host.
4. **Só então** volte à UI e **revogue o token antigo**. Enquanto ele existir,
   ele vale: a rotação não está completa até esse clique.

⚠️ **Não há verificação pré-troca, e não há log.** O `rotate` do broker assinava
um JWT com a chave nova e só gravava se ela autenticasse; e toda rotação saía no
`mints.jsonl`. Com PAT, se você colar o token errado, descobre no próximo comando
`gh` que falhar — e não haverá registro local de quando a troca aconteceu. Se
quiser rastro, anote na UI: o GitHub mostra data de criação e de último uso de
cada PAT.

⚠️ **O `av-broker rotate` sem argumento não lista mais os PATs.** Ele só conhece
o que está no seu log; GitHub saiu de lá. Não interprete "nada vencido" como "o
PAT está novo".

---

## 2. Rotação da chave da SA-broker (trimestral)

Depende da SA existir (`broker/gcp/setup-sa-broker.sh`). Exige sessão
administrativa — e ela existe justamente para não deixar refresh token de
usuário parado no disco:

```sh
gcloud-admin                      # login → subshell; sair revoga
gcloud iam service-accounts keys create /dev/stdout \
  --iam-account="$SA" | av-broker rotate --target gcp
exit                              # revoga a credencial administrativa
```

Depois liste as chaves da SA e **apague a antiga**:

```sh
gcloud iam service-accounts keys list --iam-account="$SA"
gcloud iam service-accounts keys delete <KEY_ID> --iam-account="$SA"
```

⚠️ Não redirecione a chave para arquivo em nenhum momento. O pipe acima existe
para que ela vá do `gcloud` ao Keychain sem tocar o disco (checklist 6.6).

---

## 3. Rotação do `claude setup-token` (semestral)

É a credencial de vida mais longa da máquina (~1 ano) e vale a assinatura
inteira dentro da janela — por isso a cadência é mais curta que a validade.

⚠️ **Sem pipe** — `claude setup-token` é interativo (imprime uma URL e espera um
código de volta), então mandar o stdout dele para um pipe trava o terminal em
silêncio, sem sequer chegar ao diálogo de aprovação. Dois passos:

```sh
claude setup-token
# conclua no navegador; o token aparece na tela

stty -echo; printf 'token: '; read -r T; stty echo; echo
printf '%s' "$T" | av-broker rotate --target anthropic
unset T
```

Revogue a anterior em claude.ai; ao contrário do
GitHub, aqui não há folga de 25 chaves — a antiga continua válida até ser
revogada de lá.

---

## 4. Revisão trimestral

### GitHub — os dois PATs (à mão, na UI)

> `av-broker review` **foi removido em 18/ago/2026**: ele só sabia auditar
> instalações de GitHub App, e não há mais App. A revisão passou a ser visual, e
> perdeu o `exit 1` em caso de achado — ninguém vai falhar um script por você.

Abra <https://github.com/settings/personal-access-tokens> e, para **cada um** dos
dois tokens, confira quatro coisas:

1. **Repository access** ainda é *Only select repositories* — nunca *All*.
2. A **lista de repositórios** ainda corresponde ao trabalho ativo.
3. As **permissões** ainda são o piso, não o que sobrou de alguma urgência
   antiga. O `github-pat-vm` deve continuar **estritamente menor** que o
   `github-pat`.
4. A **data de expiração** e o **last used**. Um PAT com meses sem uso é um PAT
   a revogar, não a renovar.

**A pergunta da revisão não é "isto está seguro?" e sim "isto ainda é
necessário?".** O escopo do PAT é a superfície de dano se ele vazar; ela deve
encolher com o tempo. E como o PAT não expira sozinho nem pede gesto para ser
lido, esta revisão é a única coisa entre um token esquecido e um token esquecido
**com acesso de escrita**.

### GCP — SAs de projeto e bindings órfãos

```sh
gcloud-admin
gcloud projects get-iam-policy "$PROJETO" --format=json \
  | jq '.bindings[] | select(.members[] | contains("serviceAccount"))'
gcloud iam service-accounts list
exit
```

Procure: SA sem uso recente, binding apontando para SA que não existe mais, e
qualquer papel amplo onde deveria haver papel específico. A SA-broker deve ter
**só** `serviceAccountTokenCreator`.

---

## 5. O que o log tem que mostrar

O JSONL é o log de cunhagem do broker. ⚠️ **Desde 18/ago/2026 ele não recebe
mais nada de GitHub** — o alvo saiu, e com ele o único registro local de quando
uma credencial de GitHub foi usada. O que o GitHub faz com os PATs só o GitHub
sabe (e, sem Enterprise, ele conta pouco: data de criação e último uso na página
de settings). Perda registrada no ADR §6.6. Depois de uma rodada de rotação dos
alvos que sobraram:

```sh
av-broker log -n 20
jq 'select(.event=="rotate")' ~/.local/state/av-broker/mints.jsonl
```

Vale olhar também o que **não** deu certo — o log registra recusas, e uma
tentativa de cunhagem de escrita não-interativa (`result: "no-prompt"`) é
precisamente o evento que se quer ver:

```sh
jq 'select(.result=="denied" or .result=="no-prompt")' ~/.local/state/av-broker/mints.jsonl
```

---

## 6. Por que a rotação prompta sempre

`rotate` é classificado como **escrita** (ADR §6.5): substitui a raiz de
confiança da máquina. Ele nunca é silencioso e nunca abre sessão — nem para o
segundo alvo da mesma rodada. *(Vale para GCP, Salesforce, Shopify e Anthropic.
Para o GitHub não vale mais nada disso: a rotação virou colar um token num
prompt, sem portão, sem log e sem falha-fechada. É o preço registrado em §6.6.)* Se você automatizar a rotação num cron, ela vai
falhar fechada com `result: "no-prompt"` no log, e isso é o comportamento
correto, não um defeito a contornar.
