# Arquitetura de segredos: host macOS + container Linux

Documento de design da custódia de credenciais desta máquina. Descreve o
problema, a arquitetura escolhida (opção A — tokens efêmeros do GitHub App),
o ponto que ainda não tem solução apropriada (efêmeros para ferramentas que
não o GitHub) e os pontos de segurança que a solução atual **não** cobre.

Complementa `reinstall-checklist.md` (FASE 5 — microVMs; item 3.4 —
Automic Vault). Serve também de base para pesquisa mais aprofundada — ver a
seção final "Leituras e questões em aberto".

> **Nota de terminologia (29/jul/2026):** as seções 1–5 foram escritas quando o
> sandbox era um container Apple e usam "container" como sinônimo genérico de
> sandbox Linux. A decisão vigente (§6.3) trocou o runtime pela **microVM
> shuru**; a arquitetura descrita continua válida — a fronteira host↔Linux é a
> mesma, o runtime é que mudou.

> ⚠️ **Emenda de 18/ago/2026 — leia §6.6 antes das seções 1–5.** O GitHub saiu
> do padrão descrito neste documento: não há mais GitHub App, chave privada,
> cunhagem nem token de instalação de 1 h. O acesso ao GitHub passou a **dois
> PATs fine-grained de vida longa** no login keychain. **Isto não é melhoria de
> segurança; é troca de segurança por ergonomia**, e §6.6 registra o preço.
> Todo o resto — **Shopify, GCP e Salesforce** — segue exatamente como descrito,
> com credencial efêmera e portão. As seções 1–5 e §6.1 ficam **inalteradas**:
> um ADR não se reescreve, se emenda.

---

## 1. O problema

Numa máquina de desenvolvimento moderna você executa código semiconfiável —
agentes de IA, dependências com scripts de instalação, extensões — e por padrão
ele roda **com a sua identidade** e lê **tudo que você lê**. Ao mesmo tempo, para
trabalhar de verdade você precisa de credenciais (GitHub, nuvem, APIs).

A tensão central: **como fazer trabalho real sem que um agente comprometido
consiga (a) ler seus segredos mestres, ou (b) usá-los/exfiltrá-los além de um
raio mínimo.**

O modelo de ameaça não é "um invasor externo remoto". É **um processo que você
mesmo convidou** (o agente, uma dependência) rodando como `alex` e, por padrão,
podendo ler o Keychain destravado, o `~/.env`, os tokens do `gh`, tudo.

---

## 2. A arquitetura (opção A)

A confiança **decresce** a cada fronteira — raiz no host → chave mestra atrás do
portão → token efêmero e escopado no container — e o humano entra no loop
exatamente no instante em que a chave mestra é usada.

```
┌─ HOST macOS (raiz de confiança) ──────────────────────────────┐
│                                                                │
│   Keychain (local, sem iCloud) ── guarda ──► CHAVE PRIVADA     │
│        │                                     do GitHub App     │
│        │  acesso federado + prompt por uso                     │
│        ▼                                                       │
│   Automic Vault (stub root, atestação por hash)                │
│        │                                                       │
│        │  script "blessed" lê a chave (VOCÊ aprova no desktop) │
│        ▼                                                       │
│   cunha token de instalação do GitHub App                      │
│        · validade 1h  · escopo: só aquele repo · permissão mín │
│        │                                                       │
│  ══════╪═══════════ fronteira macOS → Linux ═══════════════    │
│        │  injeta em runtime (o container nunca vê a chave)     │
│        ▼                                                       │
│   ┌─ CONTAINER Linux (1 por projeto) ──────────────────┐       │
│   │   monta só aquele repo · agente roda AQUI dentro    │       │
│   │   só possui: um token de 1h, de 1 repo             │       │
│   └────────────────────────────────────────────────────┘       │
└────────────────────────────────────────────────────────────────┘
```

### Papel de cada peça — e por que nenhuma sozinha basta

| Peça | Responde | Sozinha, falta |
| --- | --- | --- |
| **Keychain do Mac** | *guardar cifrado em repouso*, nativo do SO | uma vez destravado no login, não controla bem *quem* lê |
| **Automic Vault** | *quem está pedindo, e eu aprovo ESTE acesso?* — prompt por uso + atestação por hash | não cunha nada; só gateia/injeta segredo estático |
| **GitHub App** | *me dê o menor token que resolve isto, e faça-o expirar* | é específico do GitHub |
| **Container Linux** | *se der errado, o estrago fica contido aqui* | não protege o dado/poder que você injeta nele |

A propriedade elegante: se o agente for comprometido, o que vaza é um token que
**expira em 1h e toca 1 repo**. Não a chave-mãe, não os outros repos, não os
outros serviços.

### A fronteira macOS → Linux

O container Linux **não consegue ler o Keychain do macOS** — são dois mundos.
Por isso um **helper blessed do lado do host** lê a chave privada do App (com o
prompt do AV), cunha o token de 1h escopado e o **injeta em runtime** no
container. A chave privada nunca cruza a fronteira; só o token efêmero cruza.

---

## 3. O ponto que ainda falta solução: efêmeros para o que não é GitHub

**O padrão JIT só é tão bom quanto o serviço de destino permite.** Ele funciona
para o GitHub porque o GitHub App *nativamente* cunha tokens de 1h escopados.
Para os outros serviços, o cenário se divide:

### Onde existe mecanismo nativo (dá para replicar a opção A)
- **Nuvem** — AWS **STS** (`AssumeRole` → credencial temporária), GCP
  **short-lived tokens** / workload identity, Azure **managed identities**.
  Resolvido, mas exige fiação por provedor.
- **Bancos de dados** — o **HashiCorp Vault** (dynamic secrets) cunha usuário de
  BD efêmero com TTL. Sem Vault, o normal é senha estática.
- **SSH** — **certificados SSH com TTL** assinados por uma CA própria (step-ca,
  Vault, Teleport). Efêmero, mas requer rodar a CA.

### Onde NÃO existe — o buraco de verdade
A **cauda longa de APIs de terceiros** (Stripe, Twilio, SendGrid, a própria API
da Anthropic/OpenAI, a maioria dos SaaS) emite **apenas chave estática e
longeva**. Não há cunhagem efêmera, não há TTL. Alguns oferecem chave *restrita
de escopo*, mas nunca *expira em 1h*.

Para esses, o melhor que a arquitetura atual entrega é: guardar a chave estática
no Keychain, **gatilhar com o AV** (prompt por uso) e **injetar em runtime**.
Isso dá o prompt e mantém a chave *fora da imagem* — mas **não** dá auto-expiração
nem escopo. Se a chave vazar do container durante a janela de uso, ela vale até
você rotacionar na mão.

**Não existe um "shim" universal** que transforme chave estática em efêmera. A
direção para fechar isso, quando importar, é um **proxy que injeta credencial**:
o container fala com um proxy no host que adiciona o header de autorização na
requisição de saída — a chave **nunca entra no container**. Limita a exposição
sem depender do provedor suportar TTL, mas é infra custom, um proxy por API.

---

## 4. O que a solução atual ainda NÃO cobre

**Raio de dano dentro da janela.** Um token de 1h, enquanto vive, faz *tudo* que
o escopo permite. O isolamento limita *qual* repo e *por quanto tempo* — não *o
que* acontece dentro do escopo durante a janela. E tudo que você **monta ou
injeta** (o repo, o token, env vars) o agente lê. A fronteira protege o host *do*
agente; não protege o que você *entrega* ao agente.

**As joias da coroa mudaram de lugar e se concentraram.** O alvo agora é (a) a
**chave privada do GitHub App** (cunha tokens para *todos* os repos onde o App
está instalado), (b) o **script de cunhagem** blessed, e (c) o **stub root** do
próprio AV. Você moveu o risco para um ponto único, gated e atestado — melhora
real — mas ele continua existindo. Mitigações: instalar o App no *mínimo* de
repos, permissões do App no piso (são o teto de qualquer token), rotacionar a
chave.

**O prompt vale o quanto você presta atenção nele.** **Fadiga de alarme** é modo
de falha real: se tudo pede aprovação, você vira reflexo de clicar "Approve" e o
portão degrada. Já vimos nesta sessão — o Claude Code sondando o token a cada
startup gera prompts que *convidam* ao clique automático.

**Egress do container é o eixo mais fraco.** O LuLu (FASE 7) ataca "enviar
remotamente", mas é *por app, no host*. O tráfego de saída de dentro do container
é grosso para as regras dele. Um agente comprometido com token válido pode
empurrar dados para o repo escopado (egress que *parece* legítimo). **Filtragem
de saída de dentro do container não está resolvida.**

**Cadeia de suprimentos dentro do container.** O agente instala dependências
(npm, pip) lá dentro; uma dep maliciosa roda com o token do container durante a
sessão. O isolamento contém o estrago ao container + seu token, mas *dentro*
disso a dep tem o mesmo acesso do agente. Nada aqui audita dependências.

**Sem trilha de auditoria nem detecção de anomalia.** O AV pergunta no momento (a
aba "Secret Usage" é cobertura parcial), mas não há log/alerta de "token cunhado
às 3h" ou "volume anômalo de chamadas". É aprovar-ou-negar no instante.

**Dois mundos, um plano de política ausente.** O AV governa o host; **nada
equivalente governa dentro do container**. A de dentro não tem AV, não tem
Keychain, não tem portão. A política para no `══` da fronteira.

**Ciclo de vida manual.** Cunhagem é automática, mas rotacionar a chave do App,
o estado do `av harden`, revisar instalações do App — tudo na mão. *Nada
substitui rotação periódica.*

### Resumo em uma frase
A opção A resolve bem **"o agente não lê meu segredo mestre e o que vaza expira
rápido e é minúsculo"** — mas deixa em aberto **efêmeros para APIs de chave
estática**, **egress de dentro do container**, **auditoria/anomalia**, e depende
da sua **atenção ao prompt** não erodir.

---

## 5. Leituras e questões em aberto (base da pesquisa)

**Para o buraco dos efêmeros não-GitHub:**
- **OAuth 2.0 Token Exchange (RFC 8693)** e **Workload Identity Federation** — a
  generalização do que o GitHub App faz: trocar uma identidade por um token de
  curta duração escopado.
- **SPIFFE/SPIRE** — identidade de workload sem segredo estático; o mais próximo
  de um "plano de política" que cruzaria a fronteira host↔container.
- **HashiCorp Vault dynamic secrets** vs. **cloud-native STS** (AWS AssumeRole,
  GCP IAM Credentials `generateAccessToken`, Azure Managed Identities) — mapear
  quais serviços têm cunhador nativo e quais só têm chave estática. Esse mapa é o
  contorno do buraco.
- **Credential-injecting proxy** — termos: *egress proxy credential injection*,
  *mitmproxy addon auth*, *Smallstep*, *Pomerium*, *Cloudflare Access service
  tokens*. A única via para "efemerizar" API de chave estática mantendo a chave
  fora do container.
- **SSH certificates com TTL** (step-ca, Vault SSH engine, Teleport).

**Para os buracos de arquitetura:**
- **Confused deputy / prompt-injection em agentes** — agente comprometido usando
  credencial legítima dentro da janela.
- **Alert fatigue / consent fatigue** — usable security; justifica *reduzir* a
  frequência de prompts, não aumentar.
- **Egress de container** — *microVM egress filtering*; políticas de rede no
  Virtualization.framework/vmnet, onde o LuLu (por-app, no host) não alcança.

**Bases conceituais que amarram tudo:**
- **Least privilege + short-lived credentials** — NIST SP 800-207 (Zero Trust);
  BeyondCorp / BeyondProd (Google).
- **Secret zero problem** — quem guarda a chave que destrava as outras chaves.
  Aqui, a chave privada do GitHub App *é* o secret zero, e AV+Keychain são a
  resposta a ele.

---

## 6. Decisão (ADR): mecanismo por serviço + runtime de sandbox

Baseado em `research/seguranca_containers.md` e no complemento sobre Salesforce.

### 6.1 Os três tokens são UMA solução, não três

> **Emenda 18/ago/2026:** desde esta data o GitHub saiu do padrão (§6.6). O
> texto original segue abaixo, intacto, porque continua descrevendo corretamente
> GCP, Salesforce e Shopify — todos com credencial efêmera e portão.

GitHub, GCP e Salesforce convergem no mesmo padrão — **RFC 7523 (JWT-bearer) /
RFC 8693 (token exchange)**. Em todos: o **secret zero é uma chave privada
assimétrica** no Keychain (local, sem iCloud), gateada pelo Automic Vault; o
**broker no host** assina uma asserção curta, troca no endpoint do provedor por
um **access token curto e escopado**, e injeta esse token na VM. **A chave
privada nunca cruza a fronteira host→VM.** Os plugins de GCP e Salesforce são
assinadores diferentes do *mesmo* broker que já cunha o token do GitHub App.

⚠️ **Correção de 29/jul/2026: o Secure Enclave não entra no armazenamento.**
O SE só guarda chaves ECC P-256, e GitHub App e SAs do GCP exigem RSA (RS256).
As chaves vivem no Keychain como item comum; o hardware entra pelo **gesto**
(Touch ID) no portão do AV, não pelo armazenamento da chave.

| Serviço | Secret zero (Keychain, sob AV) | O broker faz | Entra na VM | TTL |
| --- | --- | --- | --- | --- |
| ~~**GitHub**~~ *(revogado em 18/ago/2026 — ver §6.6)* | ~~Chave privada do GitHub App (PEM)~~ | ~~JWT RS256 (iss=App ID, exp≤10min) → `POST /app/installations/{id}/access_tokens` com `repositories`+`permissions` reduzidos~~ | ~~Token `ghs_…` de 1 repo~~ | ~~**1 h** (teto rígido)~~ |
| **GCP** | Chave RSA da **SA-broker** | `iamcredentials.generateAccessToken` **impersonando SA de menor privilégio**, `scope` reduzido, `lifetime≤3600s` | Access token down-scoped | **≤1 h** |
| **Salesforce** | Chave RSA X.509 (cert do **External Client App**) | JWT RS256 (iss=consumer key, sub=usuário de integração, aud=login URL, exp curto) → `POST /services/oauth2/token` grant `jwt-bearer` | Access token + instance URL | **por política** (ver 6.2) |

### 6.2 Notas de adoção específicas

**GCP** (revisado em 29/jul/2026) — o ideal (WIF, sem chave estática) exige um
IdP para emitir a asserção OIDC, que uma máquina individual não tem. Caminho
adotado: **chave RSA de uma SA-broker no Keychain, gateada pelo AV** (não no
Secure Enclave — ver correção em 6.1). A SA-broker tem papel único:
`roles/iam.serviceAccountTokenCreator` sobre SAs de baixo privilégio, **uma por
projeto**. O broker assina JWT com essa chave e chama
`iamcredentials.generateAccessToken`; a VM só vê token de ≤1 h down-scoped. A
chave poderosa nunca sai do host — e não é "chave JSON em arquivo": vive no
Keychain, que é o que o princípio do checklist 6.6 realmente quer dizer.

Higiene do `gcloud` humano no host (mesma decisão): vive **deslogado**
(`gcloud auth list` vazio), porque `gcloud auth login` grava refresh token de
usuário **em texto plano** em `~/.config/gcloud/credentials.db`, fora do TCC.
Sessão administrativa rara = `login` → trabalho → `revoke` (alias no zsh);
administração cotidiana pelo Console no browser.

**Salesforce** — degrau abaixo do GitHub App e com armadilhas próprias:
- **Escopo NÃO é por token.** O JWT Bearer não aceita escopos na cunhagem — os
  escopos vêm da política de *Permitted Users* do app / *API Access Control* da
  org. → menor privilégio mora **na config do app**: **um app por
  projeto/finalidade** (nunca app compartilhado de escopo amplo) + permission set
  mínimo no **usuário de integração dedicado**.
- **External Client App, não Connected App.** Spring '26 restringiu a criação de
  novos Connected Apps; tutoriais pré-2026 mandam no caminho errado. O ECA ainda
  dá controle mais limpo: o *timeout* do próprio app prevalece e ignora o perfil.
- **TTL por política, não por chamada** (precedência: app → perfil → Session
  Settings da org; com ECA o timeout do app vence).
- **Expiração opaca:** a resposta não traz `expires_in` (~2 h típico, não
  garantido). Introspecção devolve o `exp` (bom p/ renovação proativa), mas
  **401 é o sinal autoritativo** de token morto — o broker trata o 401 como
  gatilho de re-cunhagem.
- **Sem refresh token** é *desejável*: nada de longa duração cruza a fronteira; o
  broker só re-cunha sob demanda (JIT puro).
- **Token Exchange (RFC 8693)** existe (ECA + Token Exchange Handler em Apex),
  mas é overkill para máquina→API. Não adotar por ora.

**Rotação** — as três chaves-raiz rotacionam **na mão** (trimestral, checklist).
Só a *cunhagem* é automática. GitHub App: sem endpoint REST, só UI, mas 25-key
headroom p/ zero downtime.

### 6.3 Runtime de sandbox: shuru (revisto em 29/jul/2026)

**Decisão:** o **shuru substitui o Apple `container`** como runtime de
isolamento dos agentes (FASE 5). A versão anterior deste ADR ("manter Apple
`container` e usar Bromure/shuru como broker/proxy no boundary") caiu por erro
técnico: o proxy/stub-and-swap do shuru só cobre **as VMs dele** — não é
acoplável às VMs do Apple `container`. Manter os dois seria operar dois
boundaries de egress, duas allowlists e duas validações adversariais.

O que o shuru entrega num componente só: microVM (Virtualization.framework),
**offline-by-default** (guest sem device de rede), `network.allow` por projeto,
e **secrets por placeholder** trocados no proxy do host — o segredo nunca
escreve em disco/env/memória da VM. É o "broker de egress no host" que o
research recomenda (Problema 6): allowlist default-deny + injeção de credencial
+ log num ponto só. **Não construa dois** (FASE 7).

**Não** adotar o Anthropic sandbox-runtime como isolamento (inalterado):
Seatbelt é sandbox de processo com kernel compartilhado — rebaixaria o
boundary. Fica como referência de design do proxy.

**Mitigação da juventude do projeto:** pin de versão + vendor do source; o gate
de aceitação é o **checklist adversarial** (`research/egress.md` §4.4) rodado
de dentro do guest — em particular para descobrir se `--allow-net` cria rota
NAT direta (aí entra anchor de `pf`, FASE 7.3) ou se o egress é vsock-only
(enforcement estrutural, `pf` desnecessário). O Apple `container` permanece
como plano B se o shuru reprovar no teste e não houver correção.

### 6.4 Anthropic: setup-token da assinatura + placeholder (29/jul/2026)

O Claude Code na VM autentica com a **assinatura**, não com API key:
`claude setup-token` gera um token OAuth de ~1 ano (`CLAUDE_CODE_OAUTH_TOKEN`),
guardado no Keychain sob o AV; a VM recebe **placeholder** e o proxy do shuru
injeta o valor real só no egress para `api.anthropic.com`.

- **ToS**: a proibição de fev/2026 atinge OAuth de assinatura em ferramentas de
  *terceiros*; aqui o consumidor é o próprio Claude Code — o proxy é transporte.
- **`/login` dentro da VM é proibido**: gravaria a credencial real (access +
  refresh) em `~/.claude/.credentials.json` no guest.
- Rotação **semestral**; revogável no claude.ai. Limitação: setup-token só faz
  model requests (sem Remote Control/conectores).
- **WIF da Anthropic** (token de 1 h, SA do GCP como IdP) fica como evolução
  futura: hoje tira o uso do pool da assinatura e fatura como API.
- Plano B, se o proxy não injetar em header `Authorization`: `apiKeyHelper`
  buscando o token do broker via vsock.

### 6.5 Política de aprovação do broker (29/jul/2026)

Anti-fadiga de alarme (Problema 4 do research — habituação começa na 2ª
exposição):

- **Touch ID no 1º token de cada sessão de projeto** (gesto físico, resistente
  ao clique-reflexo).

  ⚠️ **Revisado em 29/jul/2026 — esta máquina não tem Touch ID, e a decisão
  foi não comprar.** É um **Mac mini M4 (Mac16,10)**: sem sensor interno
  (`AppleBiometricSensor`: 0) e sem Magic Keyboard biométrico pareado; o
  `LocalAuthentication` responde *"Biometric accessory is not paired"*. A
  premissa de biometria veio do research sem checar o hardware.

  **Portão adotado: diálogo nativo do macOS** (`osascript display dialog`)
  exigindo digitar uma palavra que muda a cada prompt. O critério de escolha
  não foi conveniência, foi **resistência a um chamador hostil**:

  | Portão | Resiste a quem controla o stdio do broker? | Por quê |
  | --- | --- | --- |
  | Touch ID | sim | exige presença física; indisponível aqui |
  | **diálogo do macOS** | **sim** | a palavra nunca passa pelo stdio; dirigir o diálogo por software exige TCC de Acessibilidade, que o checklist recusa |
  | desafio no terminal | **não** | quem lê a palavra no stdout a digita de volta |

  A linha de baixo não é teórica: foi **demonstrada** em 29/jul/2026 — um
  harness com pty leu a palavra e aprovou sozinho uma cunhagem de *escrita*.
  Por isso o desafio de terminal ficou restrito a sessões sem GUI (SSH), e o
  `av-broker doctor` o reporta como fraco. O componente anti-habituação (a
  palavra polimórfica de Anderson et al., CHI 2015) é o mesmo nos três; o que
  muda é o canal.

  📌 Corolário: o item 2.3 do checklist (Touch ID para `sudo` via
  `pam_tid.so`/`touchIdAuth`) é **inócuo neste hardware**. Manter declarado não
  faz mal — passa a valer se um teclado biométrico chegar — mas não conte com
  ele como gesto de aprovação.
- Enquanto a sessão vive (VM rodando, teto de **8 h**), renovações
  **read-only** re-cunham em silêncio.
- **Qualquer cunhagem com permissão de write prompta SEMPRE**, exibindo
  repo + permissões + TTL — o human-in-the-loop fica exatamente na ação que o
  "egress que parece legítimo" explora.
- Toda cunhagem sai em **log JSONL append-only** (timestamp, projeto, repo,
  permissões, TTL, solicitante).
- "Always Approve" continua proibido (item 3.4 do checklist).

---

### 6.6 GitHub: PAT de vida longa no lugar do token de instalação (18/ago/2026)

> **Emenda ao ADR.** Não substitui §6.1–§6.5; revoga a linha do **GitHub** na
> tabela de §6.1 e retira o GitHub do escopo da política de aprovação de §6.5.
> As decisões anteriores ficam registradas onde estão — é assim que um ADR
> funciona.

#### Contexto

Entre 29/jul/2026 e 18/ago/2026 esta máquina não teve token pessoal do GitHub.
Todo acesso vinha de um **token de instalação de GitHub App**
(`alex-agent-broker`, App ID 4426468), cunhado sob demanda pelo `av-broker` a
partir de uma chave privada RSA no Keychain, com TTL de 1 h, escopo de um
repositório e permissões mínimas por comando. Era o arranjo mais bem resolvido
deste documento inteiro, e funcionou como desenhado.

O que não funcionou foi o **custo humano**, e ele foi medido:

- **Um gesto por cunhagem de escrita.** §6.5 manda promptar SEMPRE em cunhagem
  com permissão de write, sem cache. Como todo run de `no-mistakes` pede
  `contents=write` e `pull_requests=write`, o gesto era de rotina, não de
  exceção.
- **A atenção já estava gasta quando o gesto chegava.** Em 02/ago/2026 o Automic
  Vault gerou **582 diálogos num dia**; o Keychain pediu **28 senhas** no mesmo
  dia. Um portão que aparece nesse volume não é lido — é clicado. É o Problema 4
  (fadiga de alarme) que §6.5 diz atacar, entrando pela porta dos fundos.
- **O TTL de 1 h é teto rígido do GitHub**, sem endpoint de refresh. Custou três
  desenhos inteiros de contorno (`docs/plano-adocao-tokens.md`, Rotas 1–3):
  pipeline de duas etapas, mandato limitado e pedido upstream ao shuru. A Rota 1,
  quando medida, **abortava** no `git fetch` do gate do `no-mistakes`; a Rota 3
  depende de capacidade que o shuru não expõe.

#### Decisão

O GitHub sai do broker. O acesso passa a **dois Personal Access Tokens
fine-grained de vida longa**, guardados no **login keychain** do Mac:

| Item | Onde vive | Quem lê | Por que separado |
| --- | --- | --- | --- |
| `github-pat` | login keychain do Mac | `scripts/gh-token.sh`, que é o `gh` do PATH (`~/.local/bin/gh`), via `scripts/gh-pat.sh` | é o token do host; nunca cruza a fronteira |
| `github-pat-vm` | login keychain do Mac | `scripts/claude-shuru`, que o escreve num diretório temporário 0700/0600 e o monta em `/ghcred/token` **read-only** no guest | é o que **entra na VM**, legível por qualquer código que rode lá; deve ter o menor escopo dos dois |

São dois **para que um vazamento seja diagnosticável**: dá para saber qual cópia
vazou e revogar só ela. É a única mitigação que sobrou, e ela não devolve nem
efemeridade nem escopo — só torna a resposta a incidente possível em vez de cega.

Ferramental: `gh-pat` com `get|set|check <host|vm>`, symlinkado como
`~/.local/bin/gh-pat`. O subcomando de gravação lê o token do **stdin com
`stty -echo`** (nunca de argumento, que `ps` leria) e valida o prefixo
(`github_pat_` ou `ghp_`). O `gh-token.sh` injeta o valor por **ambiente**,
nunca por `argv`, e continua **proibindo `gh auth login|refresh|logout|switch|setup-git`**
— a proibição sobreviveu, por outro motivo: antes o problema era *criar* um
token pessoal; agora o token pessoal *é* o arranjo, e o problema virou a
**segunda cópia** em texto puro em `~/.config/gh/hosts.yml`. Uma cópia, um lugar.

O que foi removido do código, para o registro: `scripts/gh-broker.sh` (~300
linhas: descoberta de repo, classificação read/write, permissões por comando,
cache de leitura de 45 min, cache negativo de 24 h), o alvo `github` inteiro do
`broker/bin/av-broker`, o subsistema de agente (`av-broker agent start|stop|status`,
socket unix, chave em RAM), o subcomando `av-broker review`, os alvos de rotação
`github` e `github-dev`, o check de `github.app_id` no `doctor`,
`broker/dev/make-dev-key.sh`, `scripts/finish-github-app.sh` e o LaunchAgent
`av-broker-agent` do `configuration.nix` — que existia só para o GitHub. O
`av-broker --help` agora lista: `gcp`, `salesforce`, `session`, `log`, `doctor`,
`rotate`.

#### Consequências

**Isto não é melhoria de segurança. É troca de segurança por ergonomia, feita de
olhos abertos.** Escrito com estas letras para que nenhuma leitura futura
confunda simplificação com endurecimento.

**Perdido:**

- **Credencial efêmera.** O `ghs_…` valia 1 h; o PAT vale até você revogá-lo na
  UI. A janela de um vazamento passou de "≤45 min, um repo, só leitura" para
  "indefinida, com o escopo que o PAT tiver".
- **Escopo por repositório.** Cada cunhagem entregava um repo. Agora o alcance é
  o que a UI do GitHub deu ao PAT, e ninguém o reduz por comando.
- **Menor privilégio por operação.** O broker pedia `contents:read` por default e
  write só quando a tarefa exigia. Não existe mais essa distinção.
- **O portão humano.** O item fica no login keychain com ACL normal: qualquer
  processo seu o lê sem diálogo enquanto o chaveiro estiver destrancado. E não
  adianta criar com `-T ""` — o Automic Vault destranca o chaveiro, e chaveiro
  destrancado anula a ACL (medido). Um `-T ""` daria a aparência de portão sem o
  portão, que é pior do que assumir que não há portão.
- **Log de auditoria de cunhagem.** `~/.local/state/av-broker/mints.jsonl` não
  recebe mais nada de GitHub. Quem quiser saber o que o token fez pergunta ao
  GitHub, não à máquina.
- **Rotação automatizável.** `av-broker rotate --target github` não existe. A
  rotação do GitHub virou lembrete humano em
  `github.com/settings/personal-access-tokens`.
- **A propriedade que §2 chamava de elegante** — "se o agente for comprometido, o
  que vaza é um token que expira em 1 h e toca 1 repo" — deixou de valer para o
  GitHub. Continua valendo para GCP, Salesforce e Shopify.

**Ganho:**

- **Zero gesto.** Nenhum diálogo por comando `gh`, nenhum por run de pipeline.
- **Token que não morre no meio do trabalho.** Some a classe inteira de falha "o
  run gastou 1 h e os passos `pr`/`ci` morreram com 401 depois do trabalho caro".
- **`gh` de conta, que o token de instalação nunca permitiu por definição.**
  `gh repo list`, `gh search`, criar repositório: um token de instalação é
  escopado a uma instalação, não à conta — não era limitação de configuração, era
  o que ele é.
- **Simplificação verificável:** ~300 linhas viraram ~70; some a exigência de
  cada projeto declarar `secrets.GITHUB_TOKEN` no seu `shuru.json`, e some a
  pré-codificação de `GITHUB_BASIC` no host.

**Consequência de fronteira, dita por extenso:** o PAT agora **entra na VM como
valor real**, por mount read-only em `/ghcred/token`. O desenho de placeholder de
§6.3 evitava exatamente isso — o segredo ficava no host e o proxy o injetava no
egress. Não deu para reusá-lo: o `shuru run` não tem `--env`, e o único canal
declarado (`--secret NAME=ENV@HOSTS`) é justamente o mecanismo de placeholder
cuja fiação por projeto se quis eliminar. Fica registrado como regressão
consciente da fronteira host↔guest, não como detalhe de implementação. O
`CLAUDE_CODE_OAUTH_TOKEN` continua pelo placeholder (§6.4), inalterado.

**O que sobrevive, e por outro motivo:** `claude-shuru --stage1` fica. A
justificativa mudou — não é mais "o token de 1 h morre no meio do run", é **a
etapa longa, que roda código de terceiro com o agente solto, não precisa ver
credencial nenhuma**. Segregação de privilégio, não contorno de relógio. O host
recusa `--stage1` junto com token, e o guest zera
`GH_TOKEN`/`GITHUB_TOKEN`/`GITHUB_BASIC` na etapa 1.

**Ordem invertida, registrada:** a Rota 2 do plano de adoção diz que política de
segurança não muda sem emenda escrita ao ADR **antes** do código. Desta vez o
código veio primeiro, em 18/ago/2026, e esta emenda depois. Atenuante real, que
não apaga o fato: a mudança **removeu** um portão em vez de enfraquecê-lo em
silêncio — `av-broker github` some da `--help`, então não há como usar o gate sem
notar que ele não existe mais. Para os alvos que sobraram, a regra continua:
emenda primeiro.

#### Gatilhos de reavaliação

- Um dos dois PATs vazar → revogar só ele, e reabrir esta decisão.
- O GitHub passar a oferecer credencial de **conta** escopada e de curta duração
  sem gesto por cunhagem → voltar ao padrão de §6.1.
- O gesto do Automic Vault deixar de custar 582 diálogos/dia → o argumento de
  custo humano perde força e o App volta à mesa.
