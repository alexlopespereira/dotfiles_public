# Arquitetura de navegadores e nuvem: três zonas, uma fronteira que o SO aplica

Documento de design da FASE 6 do `reinstall-checklist.md`. Irmão de
`arquitetura-segredos.md`: lá o ativo protegido é o **segredo mestre**; aqui é a
**sessão** — cookie autenticado, perfil de navegador, grant de TCC, credencial de
nuvem no disco.

Base de pesquisa: `research/seguranca_navegadores.md`. Todas as afirmações sobre
o estado da máquina foram **medidas em 28/jul/2026** (macOS 26.5.2, `alex`,
terminal WezTerm sem FDA), não presumidas.

---

## 1. O problema

O doc de segredos resolve "o agente não lê minha chave mestra". Ele não diz nada
sobre o outro ativo da máquina, que é **igualmente monetizável e mais fácil de
levar**: a sessão já autenticada.

Um cookie de sessão do Gmail vale sem senha, sem MFA e **sem prazo**. É uma
credencial bearer de longa vida — exatamente o buraco que o doc de segredos
descreve para "APIs de chave estática", só que o cofre é o perfil do navegador e
a rotação é você deslogar de tudo, à mão.

A tensão: **você precisa navegar logado (é a máquina pessoal) e precisa rodar
agentes na mesma máquina.** O modelo de ameaça é o mesmo — um processo que você
convidou, rodando como `alex`.

A boa notícia é que aqui, ao contrário da FASE 5, **o SO já traz uma fronteira de
graça**. A questão de desenho é só uma: *o que fica de que lado dela.*

---

## 2. A fronteira que existe de graça — e onde ela passa

O TCC do macOS protege **caminhos**, não dados. Ele cobre o que é da Apple e as
pastas do usuário; o que um app de terceiro grava em `Application Support` fica
de fora. Medido nesta máquina:

```
        ┌──────────── DENTRO DO TCC (bloqueado p/ o terminal) ────────────┐
        │  ~/Library/Safari          ~/Desktop                            │
        │  ~/Library/Mail            ~/Documents                          │
        │  ~/Library/Messages        ~/Downloads                          │
        │  ~/Library/Cookies         ~/Library/Mobile Documents (iCloud)  │
        │  ~/Library/Application Support/com.apple.TCC                    │
        └─────────────────────────────────────────────────────────────────┘
   ══════════════════ um único grant de FDA apaga a linha acima ══════════════
        ┌──────────── FORA (qualquer processo seu lê) ────────────────────┐
        │  ~/Library/Application Support/Google|Firefox|BraveSoftware…    │
        │      └─ cookies, Login Data, logins.json + key4.db              │
        │  ~/.config/gcloud, ~/.aws, ~/.ssh, ~/Projects                   │
        └─────────────────────────────────────────────────────────────────┘
```

Consequência direta, e é a decisão central desta fase: **Safari está dentro da
fronteira; Chrome e Firefox estão fora.** Não é preferência de navegador — é onde
o SO aplica proteção sozinho, sem você manter nada.

---

## 3. A arquitetura: três zonas

```
┌─ ZONA PESSOAL ── Safari ───────────────────────────────────────┐
│   contas pessoais, banco, e-mail, iCloud                       │
│   protegido por TCC · senhas/passkeys no Passwords + Secure     │
│   Enclave (passkey não é extraível — nem por você)             │
│   REGRA: nenhum agente, nenhuma extensão de agente             │
└────────────────────────────────────────────────────────────────┘
   ══════ fronteira aplicada pelo SO (vale enquanto NINGUÉM tem FDA) ══════
┌─ ZONA DE TRABALHO ── VAZIA por decisão (28/jul/2026) ──────────┐
│   o Firefox saiu do casks sem nunca ter sido aberto            │
│   se um dia voltar: sem conta, sem Sync, sem senha salva,      │
│   e a premissa é que TUDO ali já vazou                         │
└────────────────────────────────────────────────────────────────┘
   ══════════════════ fronteira macOS → Linux ═══════════════════
┌─ ZONA DO AGENTE ── Chromium DENTRO do container (padrão) ──────┐
│   perfil isolated (descartado a cada run) · sem storageState   │
│   de conta real · sandbox interno do Chromium LIGADO           │
│   egress pelo mesmo proxy default-deny da FASE 5               │
└────────────────────────────────────────────────────────────────┘
   ┌─ EXCEÇÃO: @playwright/mcp no HOST (decisão 29/jul/2026) ────┐
   │   Chromium PRÓPRIO do Playwright, nunca o Safari/Chrome     │
   │   pessoal · perfil isolado e descartado · sem storageState  │
   │   em disco · sem modo extensão · sem CDP no browser pessoal │
   │   ⚠️ roda como alex: mesmo alcance de home/Drive do item 6.7 │
   │   ⚠️ só supervisionado e curto — o resto vai para o container│
   └─────────────────────────────────────────────────────────────┘

NUVEM (atravessa as três):
   host: gcloud SEM ADC — user login + impersonation (token curto)
   container: nunca ADC, nunca SA key — recebe efêmero do broker do host
   Google Drive: montado, conta pessoal, modo stream, SEM backup de pastas
     └─ ⚠️ NÃO está protegido pelo TCC (medido 28/jul/2026). A montagem é
        legível por qualquer processo que rode como alex. O que separa o
        agente do Drive é a regra 5.4 — agente DENTRO do container — e
        nada mais. Agente no host ⇒ Drive exposto.
   repo NUNCA dentro de pasta sincronizada · Drive NUNCA montado em container
```

### Papel de cada peça — e o que falta a cada uma sozinha

| Peça | Responde | Sozinha, falta |
| --- | --- | --- |
| **TCC (Safari)** | *processo de fora não lê a sessão pessoal* — de graça, sem manutenção | não vê o que roda **dentro** do navegador (extensão) e cai inteiro com um grant de FDA |
| **Separação por app** (não por perfil) | *o agente e a vida pessoal não compartilham processo* | não protege o que existe no navegador de trabalho |
| **Perfil isolated no container** | *a sessão do agente morre com o run* | não impede o agente de usar mal a sessão durante o run |
| **Sem ADC no disco** | *não há credencial de nuvem de longa vida para roubar* | exige a fiação de impersonation/WIF por provedor |
| **Playwright no host, browser separado** | *o agente não toca a sessão pessoal* — o Chromium dele é outro binário, outro perfil, outro estado | não é sandbox: o processo roda como `alex` e alcança home e Drive. Só a supervisão limita o dano |

A propriedade elegante, análoga à da opção A: **o que um agente comprometido
alcança é uma sessão descartável de um perfil vazio.** A vida pessoal está atrás
de uma fronteira que o kernel aplica, não atrás de disciplina.

### As duas regras que sustentam tudo

1. **Nenhum FDA, nunca** (item 2.2) — e, igualmente, **nenhum Files & Folders**
   para terminal ou editor. Files & Folders é o FDA parcelado: concede
   Desktop/Documents/Downloads/CloudStorage sem o nome assustador.
2. **Agente e navegador pessoal são apps diferentes, não perfis diferentes.**
   Perfil não é fronteira de segurança contra extensão.

---

## 4. Estado medido desta máquina (28/jul/2026)

| Fato medido | Leitura |
| --- | --- |
| Terminal **sem FDA**: Safari/Mail/Messages/Desktop/Documents/Downloads/iCloud Drive bloqueados | ✅ a fronteira do §2 está de pé |
| **Chrome não instalado**, sem `Chrome Safe Storage` no chaveiro | ⚠️ **deixou de valer em 01/ago/2026** — ver emenda abaixo |
| **Firefox removido** do `casks` sem nunca ter sido aberto (aplica no próximo `darwin-rebuild`) | ✅ a zona de trabalho deixa de existir |
| `gcloud` instalado, **sem ADC**, `gcloud auth list` → *No credentialed accounts* (o `credentials.db` existe com **0 linhas**: nasce vazio no primeiro `gcloud`) | ✅ ponto de partida limpo |
| **Google Drive montado** em `~/Library/CloudStorage/GoogleDrive-…` e **legível pelo terminal** — lista `Meu Drive` e `Drives compartilhados`, lê conteúdo de arquivo, com `~/Documents` bloqueado como controle | ❌ **o TCC não protege montagem de nuvem** — ver §5 |
| **iCloud logado** na conta pessoal, `KEYCHAIN_SYNC` ligado | ✅ desejado — passkeys em Secure Enclave |
| macOS **26.5.2** | ✅ acima do 26.4 que corrigiu o bypass de TCC do Archive Utility (CVE-2026-28910) |
| `alex` ainda está em `admin` | ⏳ item 1.5 pendente — rebaixar depois do `av harden` |

A FASE 6, nesta máquina, é **majoritariamente uma decisão de não-fazer**: não
instalar Chrome, não conceder grants, não logar conta em navegador fora do TCC,
não gravar ADC.

### Emenda de 01/ago/2026 — o Chrome entrou, e a decisão do §4 caiu

O `google-chrome` e o `chrome-remote-desktop-host` foram declarados em
`configuration.nix` a pedido explícito, para ter acesso gráfico remoto. A
premissa "a zona de maior risco simplesmente não existe" **não é mais
verdadeira** e não adianta o resto do documento fingir que é.

O que muda, concretamente:

| Antes | Agora |
| --- | --- |
| Nenhum navegador fora do TCC no disco | Chrome instalado, fora do TCC |
| Sem `Chrome Safe Storage` no chaveiro | Passa a existir assim que o Chrome guardar qualquer segredo |
| Nenhuma conta logada fora do Safari | **Uma** conta Google logada no Chrome — a que autoriza o CRD |

A regra que substitui a garantia perdida é mais fraca, porque depende de
disciplina em vez do kernel. Ainda assim, é o que temos:

> **O Chrome existe para uma coisa só: o console do Chrome Remote Desktop.**
> Nenhuma outra conta, nenhuma senha salva, nenhuma extensão, nenhuma navegação
> pessoal. A vida pessoal continua no Safari, atrás do TCC. Agente nenhum toca o
> Chrome — a exceção do `@playwright/mcp` continua sendo o Chromium **próprio**
> do Playwright (§3), e isso não mudou.

O que **não** mudou, e é o que impede o estrago de crescer: continua valendo a
regra 1 do §3 (nenhum FDA, nenhum Files & Folders). Os grants que o CRD pede são
Gravação de Tela e Acessibilidade, para o `Chrome Remote Desktop Host` — não são
FDA e não abrem `~/Documents` nem o Drive por essa via. Mas **Acessibilidade é um
grant forte**: quem controla esse processo controla teclado e mouse da sessão
gráfica, o que na prática alcança tudo que você alcança sentado na máquina.

O ponto único de falha passa a ser a **conta Google** — ver o inventario privado de acesso remoto
§11, que também foi emendado.

### Revisão de 29/jul/2026 — duas linhas da tabela acima precisam de emenda

Levantado ao dirigir a UI do GitHub por `@playwright/mcp` (runbook §1).

**O item do chaveiro procurava o nome errado.** "Sem `Chrome Safe Storage`"
continua verdade, mas existe **`Chromium Safe Storage`**, criado em 29/jul/2026
16:07 — e um perfil persistente em `~/Library/Caches/ms-playwright-mcp/`. Ou
seja: o `@playwright/mcp` já tinha rodado **não-isolado**, gravando perfil em
disco com a chave de cifra de cookies no chaveiro. Não é vazamento da sessão
pessoal — o Safari segue intocado e a fronteira do §2 está de pé —, mas
contradiz o "sem `storageState` em disco" que a própria exceção do §3 exige. Um
inventário que procura só o nome da marca dá verde para a família inteira.

Corrigido em `~/.claude.json`: o MCP agora roda com **`--browser chromium
--isolated`**. O `--isolated` é a metade que importa; sem ele, uma sessão do
GitHub autenticada à mão fica em disco até alguém lembrar de limpar. O default
do MCP era o canal `chrome` da Google, que nesta máquina simplesmente falha ao
subir — falha de sorte, porque o conserto óbvio (`npx playwright install chrome`)
seria instalar exatamente o que esta arquitetura decidiu não ter.

⚠️ **Downloads do Playwright caem dentro do repo.** O MCP grava snapshots e
downloads em `.playwright-mcp/`, relativo ao cwd — e o cwd é este repositório
**público**. Foi por ali que passou a chave privada do GitHub App, em
29/jul/2026. Agora está no `.gitignore`, mas a regra operacional é mais forte:
**ignorar não é apagar**; segredo que desça por esse caminho vai para o Keychain
e o arquivo é removido no mesmo passo.

*(18/ago/2026: o `scripts/finish-github-app.sh`, que fazia esse passo para a
chave do App, foi removido junto com o próprio App — ADR §6.6. A regra continua
valendo para qualquer segredo baixado pelo MCP; o que sumiu foi o script
específico, não o cuidado. Os PATs de hoje nunca descem por download: são
colados direto no `gh-pat`.)*

**E o `gcloud` não está mais instalado.** A linha da tabela era verdade em
28/jul. O commit `4168393` (29/jul, 09:25) tirou `"gcloud-cli"` da lista de
`casks` e, com `onActivation.cleanup = "zap"`, isso **desinstalou** a ferramenta —
o `zap` funcionando como projetado. Sobrou só `~/.config/gcloud/credentials.db`,
verificado com **0 linhas** e sem `application_default_credentials.json`, então o
estado de credencial segue limpo.

Consequência fora deste doc: a trilha GCP do plano de tokens
(`broker/gcp/setup-sa-broker.sh`) está bloqueada por falta da ferramenta. Se a
remoção foi deliberada, o bloqueio é a decisão se cumprindo e o plano é que
precisa ser emendado; se foi efeito colateral do ajuste de casks, basta
redeclarar `"gcloud-cli"`.

---

## 5. O que esta arquitetura NÃO cobre

**Extensão é a fronteira que o TCC não enxerga.** O TCC protege
`~/Library/Safari` de processos de fora; uma extensão roda *dentro* do processo
autorizado. Os incidentes de 2026 são exatamente isso: **ShadowPrompt** (site
qualquer injetando instrução no Claude in Chrome) e **ClaudeBleed** — extensão
com **zero permissões declaradas** dirigindo o agente para ler Gmail, Docs e
Calendar, com os diálogos de aprovação contornados por *spam de aprovação*. A
Manifold reverificou em 7/jul/2026: ainda reproduzível em v1.0.80, idêntico em
oito releases. **Por isso a regra é "app diferente", não "perfil diferente".**

**Prompt injection continua sem solução no nível do modelo.** A própria Anthropic
recomenda perfil dedicado sem contas sensíveis e reporta <0,08% de sucesso em
avaliação interna — número que não sobrevive como garantia diante do resultado de
Nasr et al. (FASE 5): defesas que reportavam quase-zero caíram acima de 90% de
ASR sob ataque adaptativo. **Contenção, não detecção.**

**A montagem de nuvem fica FORA do TCC — e isso derrubou uma premissa deste
documento.** A versão anterior colocava o Google Drive na zona pessoal supondo
que o conteúdo de `~/Library/CloudStorage` caía sob "Arquivos e Pastas". Medido
em 28/jul/2026, logo após montar: **falso**. O terminal, sem nenhum grant e com
`~/Documents` bloqueado como controle, lista `Meu Drive` e `Drives
compartilhados` e lê conteúdo de arquivo. O mecanismo exato da diferença não foi
determinado (relatos de `Operation not permitted` ali existem, mas são de
processos lançados por launchd, não de descendentes de um app de terminal) — o
que vale é o comportamento medido.

Consequência de desenho: **o Drive não está atrás de fronteira nenhuma que o SO
aplique.** O único mecanismo que o separa de um agente é a regra 5.4 — o agente
roda **dentro do container**, montando só o repo. Enquanto houver agente rodando
no host (hoje há: o próprio Claude Code), ele alcança o Drive inteiro, incluindo
drives compartilhados de terceiros. Isso reclassifica a FASE 5 de "isolamento
desejável" para **a única barreira** entre o agente e o seu Drive.

**Risco aceito (29/jul/2026), com escopo declarado.** A decisão foi manter o
Claude Code no host para **tarefas curtas e supervisionadas**, assumindo o acesso
dele ao Drive. Não é a recomendação original do plano (o item 6.4 dizia "nunca
num contexto que rode agente", sem depender do SO) — é uma troca deliberada de
segurança por ergonomia, feita com o número na mão. O que a mantém defensável é o
escopo: supervisão humana no lugar da barreira ausente, trabalho longo migrando
para o container, e reavaliação se o padrão de uso mudar. Registrada aqui porque
risco aceito sem escopo escrito vira, com o tempo, risco esquecido.

**Cookie roubado continua valendo em outra máquina.** A defesa estrutural (DBSC,
que amarra a sessão ao Secure Enclave) saiu primeiro no Windows; o macOS está na
fila. Até lá, sessão em navegador fora do TCC = segredo em texto plano no home —
e é assim que AMOS e ClickLock operam hoje.

**A fronteira é binária e reversível por um clique.** Um único "Permitir" de FDA
ou de Files & Folders apaga o §2 inteiro, retroativamente e em silêncio. Não há
alarme; a única defesa é a verificação periódica da FASE 8.

**E a ferramenta pede o clique.** Medido em 28/jul/2026: o `zap` do Homebrew
(política deliberada deste repo) falha quando a stanza do cask mira
`~/Library/Application Support/com.apple.sharedfilelist`, que é TCC-protegido —
e a mensagem de erro **instrui a conceder FDA ao terminal**. O pedido não vem de
um site suspeito, vem do seu próprio `darwin-rebuild`, no meio de uma saída de
sucesso. É a forma mais realista de a fronteira cair: não por ataque, por
conveniência. Consequência prática: cask não-declarado cuja `zap` toque caminho
protegido **não é removido** — fica meio-desinstalado até limpeza manual
(`rm -rf /opt/homebrew/Caskroom/<cask>`). O custo do desenho é esse trabalho
manual; o preço de evitá-lo seria a fronteira inteira.

**Dentro do run, o agente faz tudo que o perfil permite.** Perfil isolated limita
*quanto tempo* a sessão vive, não *o que* ela faz enquanto vive — o mesmo limite
da janela de 1h do token no doc de segredos.

**Playwright no host é browser separado, não sandbox.** A exceção de 29/jul/2026
mantém o `@playwright/mcp` no host, e ela compra exatamente uma propriedade: o
agente dirige um Chromium *dele*, com perfil próprio e descartável, sem tocar a
sessão do Safari — o §2 continua de pé. O que ela **não** compra é contenção: o
processo roda como `alex`, então alcança o home e a montagem do Drive como
qualquer outro processo do usuário, e nem o sandbox interno do Chromium ajuda
(ele protege o conteúdo da página do resto do sistema, não o sistema do
orquestrador Node). Perfil isolado é higiene de sessão; **a única barreira real
continua sendo rodar no container**. Traces, vídeos e downloads do Playwright
gravam em disco o que a página mostrou — fora de `~/Library/CloudStorage`, e
limpos depois.

**Nada observa o egress do host.** LuLu e Little Snitch saíram do plano em
29/jul/2026 (item 7.1): são filtros por processo do host e não veem o tráfego da
microVM, que é o que precisa ser controlado. A consequência honesta é que o
tráfego dos processos do host — Claude Code, Playwright, o próprio Google Drive —
não passa por filtro nenhum. Para o risco do Drive, o substituto é o Santa (item
7.5), que autoriza **acesso a arquivo**, não conexão.

**`--no-sandbox` é a tentação que anula a camada de baixo.** Chromium em
container costuma esbarrar em syscalls bloqueadas e o atalho conhecido desliga o
sandbox interno do próprio navegador. Isolamento externo **e** sandbox interno,
não um no lugar do outro.

**Nuvem: impersonation resolve o host, não a cauda.** GCP tem o caminho certo
(user creds + impersonation, WIF). AWS/Azure exigem fiação própria, e SaaS sem
federação recai no mesmo buraco de chave estática da FASE 5 — endereçável só pelo
proxy de injeção.

**Pasta sincronizada é canal de exfiltração bidirecional.** Se um dia Drive ou
OneDrive for montado: escrever ali publica, e o provedor guarda histórico de
versão. Repositório **nunca** dentro de pasta sincronizada.

### Resumo em uma frase

A FASE 6 entrega **"a vida pessoal fica atrás de uma fronteira que o kernel
aplica, e o agente só alcança sessão descartável"** — mas depende inteiramente de
**nenhum grant de FDA/Files & Folders**, não cobre **extensão dentro do navegador
autorizado**, e não impede que **cookie roubado valha em outra máquina** enquanto
o DBSC não chegar ao macOS.

---

## 6. Leituras e questões em aberto

- **DBSC no macOS** — quando chegar (Secure Enclave amarrando a sessão ao
  hardware), o modelo muda: cookie roubado deixa de valer fora daqui. É o item
  mais impactante da fila; acompanhar.
- **Extensão de agente com garantia real** — hoje não existe. Acompanhar
  `event.isTrusted`/validação de origem no Claude for Chrome, e a pesquisa de
  sandbox de agente de browser (*ceLLMate*, arXiv:2512.12594) e de detecção de
  injeção (*WebSentinel*, arXiv:2602.03792).
- **Chromium em container sem `--no-sandbox`** — quais syscalls o `container`
  da Apple libera; comparar com o atrito conhecido em gVisor.
- **Impersonation de service account como padrão local** — fiar
  `gcloud --impersonate-service-account` no mesmo broker "blessed" do AV, para
  que o token curto de nuvem siga o mesmo caminho que o do GitHub App seguia até
  18/ago/2026 (o GitHub saiu do broker; GCP e Salesforce continuam).
- **Verificação contínua de grants de TCC** — não há API para ler o estado sem
  FDA (por desenho: o `TCC.db` do sistema é `644 root:wheel` e mesmo assim
  responde *authorization denied*; o `tccutil` só faz `reset`, não lista). O
  substituto é o teste de comportamento da FASE 8: tentar ler os caminhos e
  exigir que falhem — rodado **de dentro de cada app**, porque o grant é do app,
  não do usuário.
  ⚠️ Armadilha medida em 28/jul/2026: caminho protegido nem sempre responde
  *Operation not permitted* — `~/Library/Mobile Documents` respondeu
  *No such file or directory*. Portanto **nunca use `[ -e ]` como guarda** num
  verificador desses: ele converte "protegido" em "pulado em silêncio".
