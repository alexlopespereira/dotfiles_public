# Navegadores e nuvem numa máquina que roda agentes: estado da arte (julho/2026)

Base de pesquisa da **FASE 6** do `docs/reinstall-checklist.md`. O documento de
design que sai daqui é `docs/arquitetura-navegadores.md`. Complementa
`research/seguranca_containers.md` (FASE 5): lá o ativo é o **segredo**; aqui é a
**sessão** — cookie, perfil, grant de TCC, credencial de nuvem no disco.

## TL;DR

- **A única fronteira que o macOS aplica de graça é o TCC, e ela é por-app e
  por-caminho.** Medido nesta máquina em 28/jul/2026 (terminal sem FDA): Safari,
  Mail, Messages, Desktop, Documents, Downloads e o espelho local do iCloud Drive
  são **bloqueados** para o terminal; `~/Library/Application Support/<app de
  terceiro>` **não é protegido**. Isso, sozinho, decide qual navegador pode ser o
  pessoal: **Safari está dentro da fronteira; Chrome e Firefox estão fora.**
- **Cookie de sessão é credencial bearer de longa vida, sem TTL e sem revogação
  prática** — é o mesmo buraco que o doc de segredos descreve para APIs de chave
  estática, só que o "vault" é o perfil do navegador. As duas defesas reais do
  Chrome não valem aqui: **App-Bound Encryption é Windows-only** e o **DBSC**
  (vínculo da sessão ao hardware) saiu primeiro no Windows, com macOS "numa
  release futura". No macOS a proteção é o item de chaveiro *Chrome Safe
  Storage*, e os stealers de 2025–2026 (AMOS, ClickLock) o colhem rotineiramente.
- **A superfície mais quente de 2026 não é o navegador — é a extensão de agente.**
  ShadowPrompt (Koi, mar/2026) e ClaudeBleed (LayerX, mai/2026) mostram que uma
  extensão qualquer, ou até uma página, consegue dirigir o Claude for Chrome e ler
  Gmail/Docs/Calendar. A reabertura da Manifold (7/jul/2026) confirma o bug ainda
  reproduzível em **v1.0.80**, "byte-identical" em oito releases. **Nada disso
  passa pelo TCC** — a extensão já está dentro do processo autorizado.
- **Para o agente, o padrão vencedor é o mesmo da FASE 5**: browser Chromium
  **dentro do container**, perfil **isolated** (não persistente), sem
  `storageState` de conta real, egress pelo mesmo proxy default-deny. Perfil
  persistente e `storageState` **são credenciais em disco** — trate como segredo.
- **Nuvem**: `application_default_credentials.json` no disco é chave estática de
  longa vida com a *sua* identidade — é exatamente o anti-padrão do `.env` que a
  FASE 0 eliminou. A recomendação de 2026 é user-creds + **impersonation** (token
  curto) no host e **nada de ADC dentro do container**.

---

## 1. O que o macOS protege sozinho — e o que não

### Medição desta máquina (26.5.2, terminal WezTerm sem FDA, `alex`)

| Caminho | Resultado |
| --- | --- |
| `~/Library/Safari` | **TCC bloqueia** |
| `~/Library/Mail`, `~/Library/Messages`, `~/Library/Cookies` | **TCC bloqueia** |
| `~/Library/Application Support/com.apple.TCC` | **TCC bloqueia** |
| `~/Desktop`, `~/Documents`, `~/Downloads` | **TCC bloqueia** (Files & Folders) |
| `~/Library/Mobile Documents` (iCloud Drive local) | **TCC bloqueia** |
| `~/Library/CloudStorage` (vazio hoje) | lê o diretório |
| `~/Library/Keychains` | lê os arquivos (cifrados; leitura ≠ destravar) |
| `~/Library/Application Support/<app de terceiro>` | **sem proteção** |

Detalhe operacional que só aparece medindo: **a negação nem sempre é
`Operation not permitted`**. Em `~/Library/Mobile Documents` a mesma sessão
recebeu `EPERM` numa hora e `No such file or directory` em outra — o SO às vezes
esconde a existência em vez de negar o acesso. Consequência prática para
qualquer script de verificação: **`[ -e "$p" ]` não serve de guarda**, porque
transforma "protegido" em "pulado em silêncio". Teste sempre pelo `ls` e trate
ENOENT como *inconclusivo*, nunca como aprovação.

O ponto que interessa: **a proteção não é do dado, é do caminho**. O macOS reserva
o TCC para os caminhos *dele* (Safari, Mail, Messages, Fotos) e para as pastas do
usuário (Files & Folders). O que um app de terceiro grava em
`Application Support` fica **fora** — e é lá que Chrome, Firefox, Brave e Edge
guardam cookies, histórico e logins.

### Notas sobre o TCC que importam para o desenho

- **FDA é a chave-mestra**: um grant de Full Disk Access a um terminal anula todos
  os bloqueios da tabela acima de uma vez. É por isso que o item 2.2 do checklist
  ("nunca conceder FDA a terminal nenhum") é o item de maior alavancagem de todo
  o plano — mais do que qualquer coisa da FASE 6.
- **Files & Folders é separado de FDA**: Desktop/Documents/Downloads/CloudStorage
  têm mecanismo próprio, com prompt por pasta. Ou seja, existe um caminho em que o
  agente ganha `~/Documents` sem ganhar FDA — e ele **também** deve ser negado.
- **Grants morrem quando o binário muda**: relatos consistentes de que a
  atualização do binário (ex.: interpretador do Homebrew) invalida silenciosamente
  o grant, e reconceder é só-GUI. Para nós é vantagem: reforça a política de
  **nunca conceder**, porque um `darwin-rebuild` que atualiza o WezTerm não deve
  poder herdar autorização.
- **O TCC já foi contornado em 2026**: CVE-2026-28910 (Mysk, mai/2026) — o
  Archive Utility tinha acesso de arquivo quase irrestrito e, combinado com um
  quirk de drag-and-drop, permitia furar containers de sandbox, TCC e sequestrar
  apps de terceiros **sem permissão especial**. Corrigido no **macOS 26.4**; esta
  máquina roda **26.5.2**, então está do lado corrigido. A lição de arquitetura:
  o TCC é uma boa camada, não um perímetro — vale como *primeira* fronteira, não
  como a única.
- **macOS 26 melhorou o lado do navegador**: o Safari passou a aplicar proteção
  avançada contra fingerprinting em **toda** a navegação, não só na privada.

---

## 2. Cookies e sessões: o token sem TTL

O ativo real de um navegador pessoal não é a senha (essa está no gerenciador e
atrás de MFA) — é o **cookie de sessão já autenticado**, que vale sem senha, sem
MFA e sem prazo definido. É o análogo exato do problema da "cauda longa de APIs
de chave estática" do doc de segredos.

**O que a indústria construiu, e por que quase nada disso vale no macOS hoje:**

- **App-Bound Encryption (Chrome 127+)**: liga o dado à identidade do app via
  serviço privilegiado — declaradamente inspirada no Keychain do macOS, e
  disponível **só no Windows**. Mesmo lá foi furada: o ataque **C4** (CyberArk)
  decifra cookies como usuário de baixo privilégio, e a SpyCloud documentou
  famílias de stealer contornando a proteção em semanas.
- **DBSC — Device Bound Session Credentials**: a defesa estruturalmente correta,
  porque amarra a sessão ao hardware (TPM no Windows, **Secure Enclave no
  macOS**) e faz o cookie roubado não valer em outra máquina. Reportado como
  disponível no **Chrome 146 no Windows**, com macOS "numa release futura"
  *(fonte secundária — confirme antes de contar com isso)*.
- **No macOS, hoje, a proteção do Chrome é o item de chaveiro `Chrome Safe
  Storage`** — que descriptografa `Cookies` e `Login Data` e pode ser lido por
  código rodando como o usuário. Os stealers ativos vivem disso: **AMOS/Atomic**
  (Microsoft Defender Experts, jan/2026) coleta explicitamente cookies do
  Firefox/Waterfox, `logins.json` e `key4.db`; **ClickLock** (Group-IB, jul/2026)
  mata apps em loop a cada ~210 ms até a vítima digitar a senha, com ≥100 alvos em
  33 países desde maio.
- **Firefox é o pior caso desta máquina**: `logins.json` + `key4.db` são um par
  auto-suficiente — quem leva os dois decifra as senhas offline, sem malware
  residente e sem prompt nenhum. E o diretório **não é protegido pelo TCC**.

**Conclusão para o desenho:** num navegador fora do TCC, "estar logado" é
equivalente a ter um segredo em texto plano no home. A única mitigação que não
depende do fornecedor é **não ter sessão pessoal ali**.

---

## 3. Extensões e agentes de browser: a fronteira que o TCC não vê

Esta é a mudança mais relevante desde a redação do checklist:

- **ShadowPrompt** (Koi Security, divulgado mar/2026): allowlist de origem com
  wildcard + XSS de DOM num subdomínio de CAPTCHA permitia que **qualquer site
  malicioso** injetasse instruções no Claude in Chrome. Corrigido em jan/2026 com
  checagem estrita de origem (`https://claude.ai` exato).
- **ClaudeBleed** (LayerX, reportado 21/mai/2026, divulgado mai/2026): uma
  extensão **com zero permissões declaradas** manda comandos direto para a
  extensão do Claude e eles executam. Os aprovadores ("ask before acting") foram
  contornados por **spam de mensagens de aprovação** até o sistema aceitar — é
  fadiga de alarme explorada como bug, não como comportamento humano.
- **Reabertura (Manifold Security, 7/jul/2026)**: o bug segue vivo de **v1.0.72 a
  v1.0.80**, "byte-identical" em oito releases; a causa é falta de validação de
  `event.isTrusted` num handler de clique — qualquer script com acesso ao DOM
  fabrica o clique sintético. Alcance: ler Gmail, comentários do Google Docs,
  Calendar; potencialmente alterar leads no Salesforce. O correção é uma linha e
  não foi aplicada até a data da publicação.
- **A orientação oficial da Anthropic** ("Use Claude in Chrome safely") já assume
  o risco e recomenda exatamente segregação: **perfil dedicado sem acesso a
  contas sensíveis** (banco, saúde, governo), começar por sites confiáveis, e
  evitar contas de trabalho com dado sensível. Declara que os classificadores
  reduzem o sucesso de prompt injection para **<0,08%** em teste interno, mas
  "o risco não é zero".

**Leitura arquitetural:** o TCC protege `~/Library/Safari` de *processos de
fora*. Uma extensão não está de fora — ela roda **dentro** do processo do
navegador, que é justamente quem tem autorização. Ou seja: a fronteira barata do
6.1 não cobre nada do que está nesta seção. Extensão de agente e navegador
pessoal precisam ser **apps diferentes**, não perfis diferentes do mesmo app.

---

## 4. O browser do agente

- **Modos de perfil do Playwright MCP**: *persistent* (default — mantém cookies e
  localStorage entre sessões), *isolated* (limpo a cada run) e *extension*
  (reusa a sessão do seu Chrome). A própria doc da categoria recomenda
  **isolated como ponto de partida seguro**; *extension* é o modo que fura toda a
  separação desenhada aqui e não deve ser usado.
- **`storageState` é credencial**: um JSON de `storageState` é uma sessão
  serializada — cookies e tokens que o agente lê. Traces do Playwright capturam
  requisições e respostas, **incluindo headers de autorização**. Se o agente
  gravar trace, ele grava segredo em disco.
- **Histórico de CVE**: `CVE-2025-9611`, DNS rebinding no Playwright MCP antes de
  0.0.40 (corrigido com `allowedHosts` validando o header Host); redação de
  segredo em log de console só chegou na 0.0.77. Ou seja: a ferramenta de browser
  do agente é, ela mesma, superfície de ataque em evolução.
- **Isolamento por kernel tem atrito específico com browser**: o Chrome é um dos
  processos mais intensivos em syscall que existem, e o container bloqueia
  justamente as syscalls que o Chrome usa para sandboxear os próprios renderers.
  Sob gVisor (ex.: GKE Agent Sandbox) todo syscall passa pelo Sentry; a saída
  fácil — desligar o sandbox interno do Chrome (`--no-sandbox`) — **remove a
  proteção interna do navegador**. O desenho certo é: isolamento externo forte
  (container/microVM) **e** manter o sandbox do Chromium ligado.
- **Pesquisa em andamento** (ainda não é base para decisão): *ceLLMate*
  (arXiv:2512.12594) para sandbox de agentes de browser, *WebSentinel*
  (arXiv:2602.03792) para detectar e localizar prompt injection em agentes web.

---

## 5. Nuvem

- **ADC (Application Default Credentials)**: `gcloud auth application-default
  login` grava `~/.config/gcloud/application_default_credentials.json` — um
  refresh token de longa vida, com a *sua* identidade, em texto no home, fora do
  TCC. É o mesmo anti-padrão do `GH_PAT` em `.env` que a FASE 0 eliminou, com
  raio maior. **Chaves de service account em arquivo são piores ainda** e a
  própria Google as classifica como risco de segurança não recomendado.
- **O caminho recomendado em 2026** para desenvolvimento local: credencial de
  **usuário** (não SA key) e **impersonation de service account** — sua
  identidade cunha um token curto para agir como a SA, sem nunca materializar
  chave. Para carga não-interativa, **Workload Identity Federation** (troca OIDC
  → token curto), o mesmo RFC 8693 que a pesquisa da FASE 5 já identificou como
  padrão emergente. É a versão GCP do que o GitHub App faz.
- **Estado medido aqui**: `gcloud` instalado pelo cask, **sem** ADC;
  `gcloud auth list` → *No credentialed accounts*. O `credentials.db` existe com
  **0 linhas** — ele nasce vazio no primeiro `gcloud` que roda, então a
  verificação útil é contar linhas, não checar se o arquivo existe. O ponto de
  partida está limpo — o objetivo é que continue assim.
- **Drive/OneDrive**: montam via File Provider em `~/Library/CloudStorage`, cujo
  **conteúdo** cai sob TCC (Files & Folders) — há relatos consistentes de
  processos via launchd tomando `Operation not permitted` ali. Duas consequências:
  (a) o agente sem grant não lê o Drive — bom; (b) se você conceder Files &
  Folders a um terminal "só uma vez", perde isso — e a pasta sincronizada vira
  **canal de exfiltração bidirecional**, porque escrever nela publica na nuvem e
  o provedor guarda histórico de versão.
- **iCloud Keychain / Passwords**: E2E, ancorado no Secure Enclave, e desde o
  ciclo 26 o app Passwords virou gerenciador completo com passkeys sincronizadas.
  Para esta máquina isso é ativo, não passivo: **passkey em Secure Enclave é a
  única credencial da casa que um agente comprometido não consegue copiar**, por
  não ser extraível por design.

---

## Recomendações priorizadas (esta máquina)

**Custo ~zero, ganho alto:**
1. **Safari = único navegador com conta pessoal.** É o único que está dentro do
   TCC, e a medição confirma que o bloqueio funciona hoje.
2. **Não instalar Chrome.** No macOS ele não tem App-Bound Encryption nem DBSC, e
   o `Chrome Safe Storage` é alvo padrão de AMOS/ClickLock. Com
   `onActivation.cleanup = "zap"`, basta **não declarar** — um `brew install`
   manual some no próximo rebuild.
3. **Nada de ADC no host.** Quando precisar de GCP: `gcloud auth login` +
   impersonation. Nunca `application-default login`, nunca SA key em arquivo.
4. **Nunca conceder Files & Folders** (Desktop/Documents/Downloads/CloudStorage)
   a terminal ou editor — é o FDA "parcelado".

**Decisão estrutural:**
5. **Extensão de agente de browser: não, no navegador pessoal.** ClaudeBleed
   segue aberto em v1.0.80. Se for usar, que seja num app separado, sem conta
   pessoal, com o navegador do agente dentro do container.
6. **Browser do agente = Chromium no container, perfil isolated**, sem
   `storageState` real, sem trace com header, sandbox interno do Chromium ligado,
   egress pelo proxy default-deny da FASE 5.
7. **Firefox**: ou removê-lo do `casks` (superfície zero — hoje ele está
   instalado e nunca foi aberto: não há `~/Library/Application Support/Firefox`),
   ou mantê-lo como navegador **sem conta**, com Sync desligado e senhas só no
   gerenciador — porque `logins.json` + `key4.db` fora do TCC decifram offline.

**Higiene contínua:**
8. Manter macOS ≥ 26.4 (CVE-2026-28910 do Archive Utility fura TCC abaixo disso).
9. Revisar periodicamente Privacidade & Segurança → FDA e Files & Folders: a
   lista tem que estar vazia para terminais/editores.

---

## Caveats

- **Datas e versões de fontes secundárias**: "DBSC no Chrome 146 (Windows), macOS
  em release futura", "ClickLock ≥100 alvos em 33 países" e a cronologia
  ShadowPrompt/ClaudeBleed vêm de imprensa técnica e blogs de fornecedor
  consistentes entre si, não da doc primária. Trate como bem corroborado, mas
  confirme antes de decisão irreversível.
- **ClaudeBleed**: o status "não corrigido" é o da publicação da Manifold em
  7/jul/2026 (v1.0.80). Reverifique a versão atual antes de instalar a extensão —
  a conclusão de desenho ("agente e navegador pessoal são apps diferentes") não
  muda com o patch, mas o risco imediato sim.
- **`<0,08%` de sucesso de prompt injection** é métrica **interna** da Anthropic
  em avaliação própria; a literatura da FASE 5 (Nasr et al., arXiv:2510.09023)
  mostra defesas reportando quase-zero e caindo acima de 90% de ASR sob ataque
  adaptativo. Não use esse número como garantia.
- **A medição de TCC é de um instante e de um binário** (WezTerm em 28/jul/2026).
  Grants mudam por prompt e por atualização de binário; re-rode a verificação da
  FASE 8 depois de cada `darwin-rebuild` relevante.
- **CORREÇÃO (28/jul/2026, medido depois de montar o Drive):** a afirmação de que
  o conteúdo de `~/Library/CloudStorage` cai sob "Arquivos e Pastas" **não se
  confirmou**. Com o Google Drive montado, o terminal (sem FDA, sem Arquivos e
  Pastas, com `~/Documents` bloqueado como controle) lista `Meu Drive` e os
  `Drives compartilhados` e lê conteúdo de arquivo. Os relatos de *Operation not
  permitted* que embasaram a suposição são de processos lançados por **launchd**,
  não de descendentes de um app de terminal — provavelmente é outra situação de
  atribuição de responsabilidade no TCC, mas o mecanismo não foi determinado.
  **Trate montagem de nuvem como fora do TCC.**

---

## Fontes

- [Use Claude in Chrome safely — Claude Help Center](https://support.claude.com/en/articles/12902428-use-claude-in-chrome-safely)
- [ClaudeBleed Reopened — Manifold Security](https://www.manifold.security/blog/claude-for-chrome-extension-bypass)
- [Researchers Say Claude for Chrome Flaw Lets Rogue Extensions Trigger Gmail Reads — The Hacker News](https://thehackernews.com/2026/07/claude-for-chrome-flaw-lets-other.html)
- [ShadowPrompt — Koi Security](https://www.koi.ai/blog/shadowprompt-how-any-website-could-have-hijacked-anthropic-claude-chrome-extension)
- [Vulnerability in Claude Extension for Chrome Exposes AI Agent to Takeover — SecurityWeek](https://www.securityweek.com/vulnerability-in-claude-extension-for-chrome-exposes-ai-agent-to-takeover/)
- [Improving the security of Chrome cookies on Windows — Google Online Security Blog](https://security.googleblog.com/2024/07/improving-security-of-chrome-cookies-on.html)
- [Google Chrome adds infostealer protection against session cookie theft — BleepingComputer](https://www.bleepingcomputer.com/news/security/google-chrome-adds-infostealer-protection-against-session-cookie-theft/)
- [How Infostealer Malware Bypassed Chrome's App-Bound Cookie Encryption — SpyCloud](https://spycloud.com/blog/infostealers-bypass-new-chrome-security-feature/)
- [C4 Bomb: Blowing Up Chrome's AppBound Cookie Encryption — CyberArk](https://www.cyberark.com/resources/threat-research-blog/c4-bomb-blowing-up-chromes-appbound-cookie-encryption)
- [Hunting Infostealers — macOS Threats (AMOS) — Microsoft](https://techcommunity.microsoft.com/blog/microsoftsecurityexperts/hunting-infostealers---macos-threats/4494435)
- [New ClickLock macOS Stealer — The Hacker News](https://thehackernews.com/2026/07/new-clicklock-macos-stealer-kills-apps.html)
- [CVE-2026-28910: Breaking macOS App Sandbox Data Containers, TCC — Mysk](https://mysk.blog/2026/05/19/cve-2026-28910/)
- [Explainer: Permissions, privacy and TCC — The Eclectic Light Company](https://eclecticlight.co/2025/11/08/explainer-permissions-privacy-and-tcc/)
- [Hardening Guide macOS 26 Tahoe — ernw](https://github.com/ernw/hardening/blob/master/operating_system/osx/26/Hardening_Guide-macOS_26_Tahoe_1.0.md)
- [macOS Tahoe improves privacy — Help Net Security](https://www.helpnetsecurity.com/2026/01/22/macos-tahoe-security/)
- [macOS Sequoia/Tahoe — Application Data Privacy & Full Disk Access — Retrospect](https://docs.retrospect.com/docs/macos-sequoia-application-data-privacy-full-disk-access)
- [Playwright MCP — Profile & State](https://playwright.dev/mcp/configuration/user-profile)
- [Playwright MCP Security Best Practices — QASkills](https://qaskills.sh/blog/playwright-mcp-security-best-practices-2026)
- [Playwright MCP Server: Secure Setup for AI Agents — Strac](https://www.strac.io/blog/playwright-mcp-server)
- [Sandboxing Browser Agents — Isolation Options for Go + Chrome](https://ghchinoy.medium.com/sandboxing-browser-agents-isolation-options-for-go-chrome-0c1bf3afbfbf)
- [Browser Sandboxing for Coding Agents: 2026 Security Guide — Blaxel](https://blaxel.ai/blog/browser-sandboxing-for-coding-agents)
- [How Application Default Credentials works — Google Cloud](https://docs.cloud.google.com/docs/authentication/application-default-credentials)
- [Configure Workload Identity Federation with deployment pipelines — Google Cloud](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [iCloud Keychain security overview — Apple](https://support.apple.com/guide/security/icloud-keychain-security-overview-sec1c89c6f3b/web)
- [ceLLMate: Sandboxing Browser AI Agents (arXiv:2512.12594)](https://arxiv.org/pdf/2512.12594)
- [WebSentinel: Detecting and Localizing Prompt Injection Attacks for Web Agents (arXiv:2602.03792)](https://arxiv.org/pdf/2602.03792)
