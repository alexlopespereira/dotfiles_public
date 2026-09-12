# Aula — um IdP caseiro para agentes de IA

Resumo do que foi configurado nesta máquina até **29/jul/2026**. Cada bullet é
uma coisa que fizemos; o sub-bullet é o **motivo principal** dela existir.

Detalhe completo em `arquitetura-segredos.md` (o ADR, o porquê),
`plano-adocao-tokens.md` (as fases, o quê) e `broker/README.md` (a ferramenta).

> ⚠️ **Emenda de 18/ago/2026 — o GitHub saiu deste desenho.** A seção 2 abaixo
> descreve um mecanismo que **não existe mais nesta máquina**: não há GitHub App,
> chave privada, cunhagem nem token de instalação de 1 h. O acesso ao GitHub
> passou a **dois PATs fine-grained de vida longa** no login keychain, lidos sem
> gesto nenhum.
>
> **Isso não é melhoria de segurança — é o contrário.** Foi troca de segurança
> por ergonomia, decidida de olhos abertos por custo humano medido: 582 diálogos
> do Automic Vault em 24 h e 28 senhas do Keychain no mesmo dia (02/ago/2026),
> mais um token que morria em 1 h no meio do trabalho. Contexto completo e o que
> se perdeu: ADR §6.6.
>
> **O resto desta aula continua verdadeiro.** GCP, Salesforce e Shopify seguem
> exatamente como descritos — chave assimétrica no Keychain, portão, cunhagem,
> token curto, log. Leia a seção 2 como **história**, e como o exemplo mais
> didático do desenho, que é o que ela sempre foi.

---

## A ideia em uma frase

Um agente nunca recebe uma credencial de longa duração. Ele recebe um **token
curto, escopado e auditado**, cunhado sob demanda por um **broker no host** a
partir de uma **chave privada que nunca sai do Keychain**.

*(18/ago/2026: com uma exceção declarada — o GitHub. Ver a emenda acima. A frase
vale para GCP, Salesforce, Shopify e Anthropic.)*

- Isso é literalmente o que um Identity Provider faz: guarda a raiz de
  confiança, exige uma prova, e emite algo curto no lugar dela. A diferença é
  que aqui o "IdP" é um script de ~1500 linhas na sua própria máquina.

---

## 1. Raiz de confiança e custódia

- **Secret zero é sempre uma chave privada assimétrica, guardada no Keychain
  local (sem iCloud).** Nunca uma senha, nunca um token de longa duração, nunca
  um arquivo JSON de chave.
  - Chave assimétrica só assina — ela não é o que trafega. Mesmo que a rede
    inteira seja observada, o que passa é uma asserção de vida curta, não o
    segredo.
- **A chave nunca cruza a fronteira host→VM.** O agente na microVM recebe só o
  token cunhado.
  - Comprometer o agente dá acesso ao que o token permite, por ≤1 h. Não dá
    acesso à capacidade de cunhar mais tokens.
- **Secure Enclave foi descartado para armazenamento.** O SE só guarda ECC
  P-256, e as Service Accounts do GCP (como o GitHub App, até 18/ago/2026)
  exigem RSA (RS256).
  - O hardware entra pelo **gesto** de aprovação, não pela custódia da chave.
    Descobrir isso cedo evitou desenhar em cima de uma premissa falsa.
- **Segredo nunca entra por `argv`, nunca por arquivo `.env`.**
  - `argv` é legível por qualquer processo seu via `ps`, e o modelo de ameaça
    aqui é exatamente "agente comprometido rodando como você". Um `.env`
    exportaria tudo para todo processo filho — inclusive o próximo agente.

## 2. GitHub — JWT RS256 → token de instalação  *(desfeito em 18/ago/2026)*

> **Esta seção é histórica.** Descreve o arranjo que valeu de 29/jul a
> 18/ago/2026. O que existe hoje está no fim da seção, em "2.1".

- **Um GitHub App pessoal** (`alex-agent-broker`, App ID `4426468`), com **3
  permissões de 99**: Contents RW, Pull requests RW, Metadata read-only. Webhook
  desativado, "Only on this account".
  - As permissões do App são o **teto rígido** de qualquer token que venha a ser
    cunhado. O que não está aqui não pode ser concedido depois, por engano nenhum.
- **Instalado em um único repositório** (`SEU-USUARIO/dotfiles`).
  - A lista de instalação é o raio de explosão **se a chave vazar** — quem tem o
    PEM fala com a API direto, sem broker, sem diálogo e sem log.
    `All repositories` está descartado porque concederia também aos repos que
    ainda nem existem.
- **O broker reduz por cunhagem**: 1 repo + `contents:read` por padrão; escrita
  só quando a tarefa exige.
  - Medido contra a API real, não por `--dry-run`: leitura no repo escopado →
    200; escrita → **403**; repo fora da instalação → **404**. O downscoping era
    real, não decorativo.

### 2.1 O que existe hoje (18/ago/2026): dois PATs de vida longa

- **Dois Personal Access Tokens fine-grained**, no **login keychain**:
  `github-pat` (usado pelo `gh` do host) e `github-pat-vm` (montado read-only em
  `/ghcred/token` dentro do guest do shuru).
  - São **dois** para que um vazamento seja diagnosticável: dá para saber qual
    cópia vazou e revogar só ela. É a única mitigação que sobrou.
- **Não há portão.** O item está no login keychain com ACL normal; qualquer
  processo seu o lê sem diálogo enquanto o chaveiro estiver destrancado.
  - E não adianta criar com `-T ""`: o Automic Vault destranca o chaveiro, o que
    anula a ACL (medido). Fingir um portão é pior que declarar que não há.
- **Não há TTL, não há escopo por comando, não há log de cunhagem.** O escopo é o
  que a UI do GitHub deu ao token; a rotação é lembrete humano.
  - O que se comprou com isso: zero gesto, token que não morre no meio de um run,
    e `gh` de **conta** (`gh repo list`, `gh search`, criar repo) — que o token
    de instalação nunca permitiu, por definição.
- **`gh auth login` continua proibido**, agora por outro motivo: o token pessoal
  virou o arranjo, e o problema passou a ser a **segunda cópia** em texto puro
  em `~/.config/gh/hosts.yml`.
  - Uma cópia, um lugar. Segredo que existe em dois lugares é segredo que se
    revoga pela metade.
- **A lição didática que essa reviravolta ensina, e que vale mais que o
  mecanismo:** um controle de segurança tem um custo humano, e quando esse custo
  passa do que a pessoa aguenta, o controle não é "seguido com esforço" — ele é
  removido. Projetar o gesto é tão parte do desenho quanto projetar a cripto.

## 3. GCP — impersonation de service account

- **Uma SA-broker** (`av-broker@projeto-broker`) com **papel único**:
  `roles/iam.serviceAccountTokenCreator` sobre a SA de trabalho.
  - Ela não tem permissão de dado nenhum. Só o direito de cunhar token para
    outra SA — o que mantém o raio pequeno mesmo se a chave dela vazar.
- **Uma SA de trabalho** (`av-agent@…`) que **nasceu sem permissão nenhuma**.
  - O privilégio cresce só na medida do que o trabalho exigir, e cada aumento é
    uma decisão explícita. O default é zero, não "Editor".
- **`gcloud` do host vive deslogado**; sessão administrativa é
  `login → trabalho → revoke` (função `gcloud-admin`).
  - `gcloud auth login` grava refresh token de **usuário em texto plano** em
    `~/.config/gcloud/credentials.db`, fora do TCC e fora de qualquer gate.
    É a credencial mais poderosa da máquina; não pode ser a única sem portão.
- **Nunca `gcloud auth application-default login`; nunca chave de SA em arquivo.**
  - ADC em disco é uma credencial persistente que nenhum gate observa. O script
    de setup gera a chave, importa no Keychain e apaga o arquivo no mesmo passo.

## 4. Anthropic — placeholder trocado no egress

- **`claude setup-token`** (credencial da assinatura, ~1 ano) fica no Keychain
  no host; a VM recebe um **placeholder** e o proxy injeta o valor real só no
  tráfego para `api.anthropic.com`. ⏳ *Custódia ainda pendente — é um gesto humano.*
  - A troca acontece **abaixo do guest**, por bytes no fluxo TLS. Não existe uma
    variável de ambiente que um código malicioso possa ler ou remover.
- **`/login` dentro da VM é proibido.**
  - Gravaria a credencial real (access + refresh) em
    `~/.claude/.credentials.json` **dentro do guest** — exatamente o que o
    placeholder existe para evitar.

## 5. O portão de aprovação

- **Diálogo nativo do macOS** como gesto de aprovação (não Touch ID: este Mac
  mini não tem sensor, e a decisão foi não comprar teclado biométrico).
  - O diálogo é **out-of-band do stdio**. Um portão digitado no terminal (`tty`)
    não resiste a quem controla a entrada e saída do broker — o que um agente
    comprometido controla por construção.
- **Escrita prompta sempre; leitura abre sessão de até 8 h.**
  - Anti-fadiga de alarme: perguntar a cada leitura treina o clique-reflexo, e
    aí a pergunta que importa (escrita, rotação) também é clicada sem ler.
- **A sessão aprovada é presa ao contexto que a tornou significativa**: alvo,
  `--dry-run`, portão usado e impressão da credencial-mãe.
  - Nasceu de um bug real: uma aprovação dada a um **ensaio** com chave de
    brinquedo pelo portão fraco silenciou a **primeira cunhagem de produção**.
    O consentimento dado não era o consentimento usado.
- **Rotação nunca abre sessão e falha fechada** (`--no-prompt` recusa e registra).
  - Trocar a raiz de confiança é a operação mais sensível do sistema; automatizá-la
    em silêncio é precisamente o evento que se quer conseguir enxergar.

## 6. Auditoria

- **Log JSONL append-only** de toda cunhagem: horário, provedor, alvo,
  permissões, TTL, se foi aprovado ou silencioso.
  - Um controle que ninguém consegue reconstruir depois não é um controle. E a
    idade das credenciais sai daqui, não do Keychain — `security -U` preserva a
    data de criação do item, então uma chave recém-rotada pareceria velha.
- **O log guarda a impressão SHA-256 da chave pública**, nunca material secreto.
  - Permite responder "qual chave estava em uso?" sem transformar o log num
    segundo lugar de onde vazar.
- **Canary tokens** (chave AWS falsa) plantados no host e na imagem da VM.
  - Detecção, não prevenção: se alguém ler o que não devia, o alerta chega por
    e-mail. É a única linha que age depois que todas as outras falharam.

## 7. Isolamento e egress

- **microVM `shuru`** (Virtualization.framework), **offline por padrão**, com
  versão pinada e SHA-256 conferido do CLI e da imagem.
  - Sem rede declarada, o guest **não tem sequer interface de rede**. Isso é uma
    garantia de topologia, não de política — é mais forte do que uma regra.
- **Allowlist default-deny por projeto**, validada por **12 testes adversariais
  rodados de dentro do guest**.
  - O enforcement é **estrutural, não cooperativo**: a interceptação acontece
    abaixo do guest, então não há `HTTP_PROXY` para o código malicioso remover.
- **`pf` foi descartado após medição**, não por preguiça.
  - Não existe bridge NAT: a rede é em modo usuário e os pacotes terminam dentro
    do processo do shuru. O `pf` filtra interfaces do host e não teria onde agir.
- **Lição do gate**: a primeira versão acusou **13 vazamentos inexistentes**.
  - A pilha em modo usuário completa o handshake TCP **localmente** antes de
    decidir se abre a saída. Sucesso de `connect()` não prova alcance; o critério
    honesto é **byte de volta**. Um teste adversarial sem controle negativo é um
    carimbo de aprovação automático.

## 8. Higiene contínua

- **Rotação trimestral** (chaves GitHub/GCP) e **semestral** (Anthropic), com
  verificação **antes** da troca: assina com a chave nova e testa; se falhar,
  nada é gravado e a antiga continua valendo.
  - É isso que dá "rotação sem downtime" — não a folga de 25 chaves do GitHub.
- **Revisão trimestral** das instalações do App e das SAs (bindings órfãos).
  - Privilégio só encolhe se alguém olhar. Sem revisão, a lista de repositórios
    e as permissões crescem monotonamente.
- **`av-broker doctor`** valida a instalação — inclusive **lendo a chave** e
  submetendo-a ao `openssl`.
  - Aprendido do jeito caro: o `doctor` dizia "tudo certo" com a chave do App
    destruída no Keychain, porque validava o *ponteiro* e nunca o *segredo*.

---

## Riscos aceitos (documentados, não resolvidos)

- **Quem tem a chave não passa pelo broker.** O portão protege o *broker*, não a
  *chave*. Gates, diálogo e log são bypassáveis por quem lê o Keychain — por isso
  a lista de instalação e os papéis das SAs importam tanto.
- **Exfiltração por domínio permitido.** Uma allowlist por host não vê conteúdo:
  um `push` com token válido para o repo escopado é tráfego legítimo.
- **Prompt injection não está resolvido.** A aposta é contenção arquitetural,
  nunca defesa no nível do modelo.
- **Um único ponto de enforcement.** Se o proxy do shuru tiver um bug de
  fail-open, não há segunda camada — é o preço da decisão de não usar `pf`.

---

## Referências

Princípios:

- Saltzer, J. H.; Schroeder, M. D. **"The Protection of Information in Computer
  Systems"**, *Proceedings of the IEEE*, 63(9), 1975. A fonte de *least
  privilege*, *fail-safe defaults* e *complete mediation* — os três princípios
  que este desenho aplica quase literalmente.
- NIST SP **800-207**, *Zero Trust Architecture*, 2020. Formaliza "nenhum
  privilégio implícito por localização de rede", que é por que o agente não
  herda credencial só por rodar na sua máquina.

Protocolos:

- **RFC 7523** — *JWT Profile for OAuth 2.0 Client Authentication and
  Authorization Grants*. É o padrão que GCP e Salesforce instanciam (e que o
  GitHub App instanciava até 18/ago/2026): asserção JWT assinada trocada por
  access token.
- **RFC 8693** — *OAuth 2.0 Token Exchange*. O modelo formal de "troque esta
  credencial por outra, mais fraca e mais curta".
- **RFC 6749** — *The OAuth 2.0 Authorization Framework*. A base dos dois acima.

Documentação dos provedores:

- GitHub Docs — *Authenticating as a GitHub App installation*
  (`docs.github.com/apps/creating-github-apps/authenticating-with-a-github-app`).
  Fonte do teto de 1 h e da regra de que um token de instalação não recebe
  permissão que o App não tenha. *(Referência histórica desde 18/ago/2026 — ver
  2.1. O que vale hoje é `docs.github.com/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens`.)*
- Google Cloud — *IAM Credentials API: `generateAccessToken`* e *Service account
  impersonation* (`cloud.google.com/iam/docs/service-account-impersonation`).
  Fonte do `lifetime ≤ 3600s` e do papel `serviceAccountTokenCreator`.

Neste repositório:

- `research/seguranca_containers.md` — o levantamento que originou as decisões,
  e onde está a literatura citada sobre habituação a alertas de segurança e
  sobre prompt injection.
- `research/egress.md` — o checklist adversarial de egress (§4.4) que virou o
  gate da Fase 2.
