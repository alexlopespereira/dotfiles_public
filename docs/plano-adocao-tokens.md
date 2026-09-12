# Plano de adoção: tokens efêmeros, shuru e egress

Decidido em 29/jul/2026, em sessão de grilling sobre
`research/seguranca_containers.md` e `research/egress.md`. As decisões de
arquitetura estão registradas no ADR (`arquitetura-segredos.md` §6); este
documento é o **plano de execução** — fases, ordem e gates de aceitação.
Implementação fase a fase, em sessões próprias; nenhuma fase seguinte começa
sem o gate da anterior.

## Correção de premissa

O pedido original falava em "OIDC/RFC 8693 para o GitHub". Não existe: o GitHub
não aceita federação OIDC externa para uso pessoal (o OIDC dele é do Actions).
O mecanismo real é o do ADR — JWT RS256 do GitHub App (estilo RFC 7523) →
token de instalação de 1 h. OIDC/token exchange de verdade só aparece no GCP
(impersonation) e, futuramente, no WIF da Anthropic.

> ⚠️ **Superado em 18/ago/2026 para o GitHub.** O GitHub App e o token de
> instalação de 1 h foram abandonados; o acesso passou a dois PATs
> fine-grained de vida longa. Não é melhoria de segurança — é troca de
> segurança por ergonomia. Ver "Rota 4" e ADR §6.6. **GCP, Salesforce e
> Shopify seguem exatamente como descrito aqui**, com credencial efêmera e
> portão.

## Decisões fechadas (resumo — detalhe no ADR §6)

1. **shuru substitui o Apple `container`** como runtime (FASE 5 do checklist).
   Apple `container` é plano B se o shuru reprovar no gate da Fase 2.
2. **Proxy embutido do shuru = ponto único** de enforcement + injeção. Sem
   Squid paralelo. `pf` só se o teste adversarial revelar bridge NAT (7.3).
   ✅ **Fechado em 29/jul/2026:** não revelou — rede em modo usuário, sem
   bridge. `pf` não entra. O proxy é mesmo o ponto único, com o que isso tem de
   bom (um lugar para acertar) e de ruim (um lugar para falhar).
3. **GitHub: 1 App pessoal**, instalado só nos repos ativos. Teto:
   `contents:write`, `pull_requests:write`, `metadata:read`. Broker downscopa
   por cunhagem: 1 repo, `contents:read` por default, write só quando a tarefa
   exige.
4. **GCP: SA-broker** (papel único `serviceAccountTokenCreator`) com chave RSA
   no Keychain sob o AV; tokens ≤1 h down-scoped por projeto.
5. **`gcloud` do host deslogado** por default; sessão admin = login → revoke.
6. **Anthropic: `claude setup-token`** (assinatura, ~1 ano) no Keychain sob o
   AV; a VM só vê placeholder. `/login` dentro da VM proibido. WIF fica como
   evolução futura (hoje fatura como API, fora do pool da assinatura).
7. **Aprovação: Touch ID por sessão de projeto** (teto 8 h); renovação
   read-only silenciosa; **write prompta sempre** com repo+permissões+TTL.
8. **Complementos**: canary tokens, pnpm/`ignore-scripts` na imagem-base,
   Touch ID no sudo via nix-darwin, log JSONL do broker.
9. **Fora de escopo**: Salesforce (plugin futuro do mesmo broker, ADR §6.2) e
   Santa (segue como item 7.5 "avaliar", decisão separada).

---

## Fase 0 — Fundações (independentes entre si)

> Executada em 29/jul/2026. Gate: **6 ok, 0 falhas, 2 pendências**, as duas
> irredutivelmente humanas (criar o App na UI, cunhar o `setup-token`).
> Verificação: `scripts/verify-fase0.sh` — que separa **FALHA** (regressão) de
> **PENDENTE** (falta um gesto seu) e delega a saúde interna do broker ao
> `av-broker doctor` em vez de reimplementá-la. Passos manuais:
> o runbook privado da Fase 0.

- [x] `security.pam.services.sudo_local.touchIdAuth = true` no nix-darwin
  (substitui o passo manual 2.3 do checklist).
  ⚠️ **Medido em 29/jul/2026: inócuo neste hardware.** Mac mini M4 não tem
  sensor biométrico e a decisão foi **não** comprar um Magic Keyboard. Declarar
  não faz mal (passa a valer se um teclado biométrico chegar), mas o gesto de
  aprovação do broker é o **diálogo nativo do macOS**, não a biometria — ver
  ADR §6.5 para a tabela de resistência dos portões.
- [x] ~~Criar o **GitHub App**~~ — **desfeito em 18/ago/2026** (Rota 4). O
  registro do que foi feito fica abaixo porque ele explica o que a máquina
  teve entre 29/jul e 18/ago, e porque o App pode continuar existindo na conta
  até ser deletado na UI. O que a máquina usa hoje: `gh-pat set host` e
  `gh-pat set vm`. `scripts/finish-github-app.sh` saiu junto.
- [x] Criar o **GitHub App** — feito em 29/jul/2026 pela UI, dirigida por
  `@playwright/mcp`. `alex-agent-broker`, **App ID 4426468**, instalação
  `149883954`. Auditado no formulário antes de submeter: **3 permissões de 99**
  (Contents RW, Pull requests RW, Metadata read-only), webhook inativo, "Only on
  this account". Chave privada no Keychain (`av-broker-github`), PEM apagado,
  chave descartável de dev removida. Fecho automatizado:
  `scripts/finish-github-app.sh` (script removido em 18/ago/2026).

  ✅ **Desfeito em 18/ago/2026, na ordem certa e verificado.** O App foi
  deletado em `github.com/settings/apps` **antes** de a chave sair do chaveiro —
  primeiro se mata o poder, depois se apaga a cópia; a ordem inversa deixaria um
  App vivo e sem dono. Em seguida
  `security delete-generic-password -s av-broker-github`. Conferido depois:
  `av-broker-github` e `av-broker-dev-github` ausentes, e as chaves de gcp e
  salesforce intactas no `av-broker doctor`. Não sobrou credencial de GitHub App
  nesta máquina nem na conta.
  **Instalado só em `SEU-USUARIO/dotfiles`.** A lista de instalação é o raio
  de explosão *se a chave vazar* — quem tem o PEM fala com a API direto, sem
  passar pelo broker, sem diálogo e sem aparecer no JSONL. Ampliar é decisão
  consciente, repo a repo; `All repositories` está descartado porque concede
  também aos repos que ainda não existem.
- [x] Cunhar o `claude setup-token` e guardar no Keychain sob o AV. Feito;
  `av-broker rotate` já o rastreia contra a cadência semestral (origem: log). O
  token impresso não persiste em lugar nenhum fora do Keychain — runbook §2 usa
  `stty -echo` para que nem o histórico o veja.
- [x] Gerar canary tokens (Thinkst, canarytokens.org): chave AWS falsa para a
  imagem-base da VM (Fase 1) + arquivo-isca no host. Feitos, alertando por
  e-mail; valores em `canary-host-aws` / `canary-vm-aws` no Keychain, nunca
  versionados. Detalhes e o caveat do `sts get-caller-identity`: runbook §3.

**Gate:** App criado com o teto mínimo e chave no Keychain; `setup-token`
custodiado; nenhum PEM/token em disco (`find ~ -name "*.pem" -newer …` limpo).

**Medido:** a varredura de disco passa limpa. O regex de vazamento precisou de
piso de comprimento (`sk-ant-oat[0-9]{2}-[A-Za-z0-9_-]{80,}`): sem ele, exemplos
escritos em prosa nesta própria árvore marcavam falha, e um check ruidoso é um
check que se aprende a ignorar. `security -w` devolve **hex**, não texto, para
qualquer valor com quebra de linha — ou seja, para todo PEM; era um bug real no
`read_key()` do `av-broker`, que afetava também o caminho de produção do GCP,
corrigido em 29/jul/2026.

## Fase 1 — shuru piloto

> Executada em 29/jul/2026. Gate: **os 8 testes passam**
> (`scripts/shuru-verify-gate.sh`, `RESULTADO: PASSOU`).

- [x] Verificar maturidade/atividade do repo do shuru (caveat do research:
  ecossistema muda semanalmente). Instalar com **versão pinada**.
  `scripts/install-shuru.sh` fixa a **v0.6.5** e confere SHA-256 do CLI **e** da
  imagem de SO. Nem o tap do brew (`onActivation.upgrade = true` segue o latest
  e quebra o pin) nem o `install.sh` deles (não confere hash); a imagem também
  vem daqui porque o download do `shuru init` não verifica nada.
  **Nunca rode `shuru upgrade`** — subir de versão exige re-rodar o gate
  adversarial da Fase 2.
- [x] Imagem-base da VM: pnpm v10 + `ignore-scripts=true` no npm, canaries
  plantados (`~/.aws/credentials` isca), herdr-linux-aarch64.
  `scripts/shuru-base-image.sh` (host) + `scripts/shuru/provision-base.sh`
  (guest). Além do pedido: `minimum-release-age=4320` (cooldown de 3 dias, que
  cobre as duas janelas do Shai-Hulud) e Claude Code pelo instalador nativo — o
  pacote npm depende de um postinstall que `ignore-scripts` justamente impede.
- [x] 1 projeto piloto **offline-by-default** (`shuru run` sem rede) montando
  só o repo. `shuru.json` na raiz: `allow_net: false`, mount read-only do repo,
  `network.allow` mínima (**github.com deliberadamente ausente**).
- [x] Ligar `allow_net` no piloto com `network.allow` mínima e validar o
  placeholder: `CLAUDE_CODE_OAUTH_TOKEN=<placeholder>` na VM, proxy injetando
  o real em `api.anthropic.com`.
  - ~~Ponto aberto~~ **Resolvido: o proxy substitui no header `Authorization`.**
    A troca é por bytes no fluxo TLS interceptado (`crates/shuru-proxy`), não uma
    expansão de env var, então cobre header, corpo e query igualmente. O guest
    viu `shuru_tok_…`; o destino recebeu o valor real. **O plano B do
    `apiKeyHelper` via vsock é desnecessário** e sai do desenho.

**Gate:** Claude Code funciona dentro da VM **sem nenhum segredo real dentro
dela** — inspecionar env, disco e `~/.claude` do guest.

**Medido:** placeholder na env; nenhum valor real na env, no disco ou em
`.claude/.credentials.json`; valor real chegando ao destino; **host que está na
allowlist de rede mas fora da lista de hosts do secret recebe só o placeholder**
(sem esse teste, a lista de hosts do secret seria decorativa); `claude` funcional;
canary presente. O gate roda com um valor **sentinela descartável**, não com o
`setup-token`: o caminho exercitado é idêntico e o que vazaria não vale nada.

**Dois achados que a Fase 2 herda:**

1. Com `--allow-net` o guest ganha um `eth0` **real em 10.0.0.2/24** — não é
   vsock-only. Pelo item 7.3 do checklist, isso aponta para o ramo do **anchor
   de `pf`**; decidir só depois dos 8 testes adversariais.
2. Contrabalançando: ler o proxy mostra enforcement **mais forte** do que o
   research supunha — o conjunto de IPs de destino é pinado às respostas de DNS
   (fecha o bypass por IP hardcoded), há allowlist por SNI e TLS **sem** SNI é
   recusado. Isso não substitui o teste; só muda a expectativa de resultado.

## Fase 2 — Egress (o gate que vale)

> Executada em 29/jul/2026. **PASSOU** — `scripts/shuru-verify-fase2.sh`.
> Nenhum caminho de egress fora da allowlist; 1 risco residual esperado.
> **O shuru fica. O plano B (Apple `container` + Squid + `pf`) não é acionado.**

- [x] Rodar **de dentro do guest** o checklist adversarial completo de
  `research/egress.md` §4.4 (8 testes: domínio fora da lista, socket direto,
  DNS direto, IP literal, DoH, protocolo não-HTTP, túnel SSH, `unset
  HTTP_PROXY`). Mais 4 que só fazem sentido nesta arquitetura: **SNI permitido
  apontando para IP proibido** (o bypass clássico de allowlist por SNI),
  **QUIC/UDP 443** (com ele aberto, ECH cifra o SNI e a allowlist vira
  decorativa), **o resolver do próprio shuru como canal encoberto**, e **pivot
  para o host e para a LAN** — que vale mais para um atacante do que a internet,
  porque é onde estão o broker e o Keychain.
- [x] Decidir o `pf` pelo resultado (checklist 7.3): **primeiro ramo — `pf` não
  será usado.** Não há bridge NAT: com a VM no ar o host não ganha `bridge1XX`
  nem `vmenet`, e o processo do shuru não abre porta de escuta. A rede é em
  **modo usuário** — os pacotes do guest terminam dentro do processo. O `pf`
  filtra interfaces do host e não teria onde agir. Gatilho de reabertura
  registrado no item 7.3 do checklist.

**Gate:** itens 1–7 do checklist **bloqueiam**. Se qualquer socket direto
passar, o isolamento está furado — parar e corrigir (ou cair no plano B Apple
`container` + Squid + `pf`) antes de qualquer trabalho real com rede.

**Medido.** O enforcement é **estrutural, não cooperativo**: não existe uma
variável `HTTP_PROXY` para o código malicioso remover — a interceptação
acontece abaixo do guest. Sem `--allow-net` o guest não tem sequer interface
(`lo` e nada mais), o que torna o modo offline uma garantia de topologia e não
de política.

⚠️ **A armadilha que quase inverteu o veredito.** A primeira versão do gate
acusou **13 vazamentos inexistentes**. A pilha em modo usuário aceita o
handshake TCP **localmente** antes de decidir se abre a saída, então
`connect()` "tem sucesso" até para `192.0.2.1` (TEST-NET-1, inalcançável por
definição). Sucesso de `connect()` não prova alcance; o critério honesto é
**byte de volta**. O gate hoje carrega **dois** controles que abortam com
INCONCLUSIVO: um positivo (o host permitido responde — senão a VM está sem rede
e "tudo bloqueado" não prova nada) e um negativo (TEST-NET-1 não devolve dados
— senão a sonda mede ficção). Um gate adversarial sem controle negativo é um
carimbo de aprovação automático.

**Risco residual confirmado na prática** (item 8, esperado): um corpo arbitrário
chega a `api.anthropic.com`. Allowlist por host não vê conteúdo. Só MITM
seletivo mitigaria, ao custo de quebrar pinning — segue como risco aceito.

## Fase 3 — Broker completo

> **Fechada em 29/jul/2026**, os dois lados, com cunhagem de ponta a ponta
> contra as APIs reais.

- [x] Assinador **GitHub** no script blessed (sob AV): JWT RS256 →
  `POST /app/installations/{id}/access_tokens` com `repositories` +
  `permissions` reduzidos por tarefa.
  **Medido contra a API real**, não só por `--dry-run`: token `ghs_` de 40 chars,
  `GET` no repo escopado → 200; `PUT contents/` → **403** (o token é read-only,
  então o downscoping é real e não decorativo); `GET` em repo fora da instalação
  → **404**. O 404 anterior em `/repos/…/installation` também informou: aquele
  endpoint só responde 404 *depois* de aceitar o JWT, então ele provou a cadeia
  de assinatura RS256 antes de o App estar instalado em repo nenhum.
- [x] Assinador **GCP**: sessão administrativa (login → revoke) para criar a
  SA-broker, as SAs de projeto e os bindings; chave da SA-broker importada no
  Keychain, PEM/JSON apagado. Broker cunha via `generateAccessToken`.
  **Feito** em `projeto-broker` (conta `admin@exemplo.com`) via
  `broker/gcp/setup-sa-broker.sh`. `av-broker@…` com papel único
  `tokenCreator` sobre `av-agent@…`; `av-agent` nasceu **sem permissão
  nenhuma**, de propósito — o raio hoje é zero e cresce só na medida do que for
  concedido a ela. Cunhagem real aprovada por `gui`: `ya29.c…` de 1024 chars,
  0,99 h de vida (pedimos 3600 s). Depois do script: `gcloud auth list` sem
  conta, `credentials.db` com 0 linhas, sem ADC, arquivo temporário da chave
  apagado.
  ⚠️ Isso trouxe um projeto **da organização** para a raiz de confiança de uma
  máquina pessoal. Quem tiver o item `av-broker-gcp` do Keychain cunha token
  chamando a API direto — sem broker, sem diálogo, sem log. O portão protege o
  broker, não a chave; é a mesma leitura que vale para a lista de instalação do
  GitHub App.
  A política de organização `iam.disableServiceAccountKeyCreation` **não** está
  ativa em `exemplo.com` — se um dia estiver, o caminho é Workload Identity
  Federation, que dispensa chave em disco e é melhor de todo jeito.
- [ ] Política de aprovação (ADR §6.5): Touch ID no 1º token da sessão,
  read-only silencioso até 8 h, write prompta sempre.
- [ ] Log **JSONL append-only** desde o primeiro mint: timestamp, projeto,
  repo, permissões, TTL, solicitante.
- [ ] Alias zsh `gcloud-admin` (login → subshell → revoke no exit) no
  `home.nix`.

**Gate:** cunhagem de ponta a ponta nos dois provedores com downscoping
visível no log; prompt de write aparecendo exatamente quando há permissão de
escrita e nunca em renovação read-only.

**A primeira cunhagem real não foi aprovada por ninguém — e isso era um bug.**
Ela saiu `silent`, herdando um grant de **15:11:57Z** que tinha sido aberto na
demonstração do exploit: `--dry-run`, contra a **chave descartável de dev**, pelo
portão **`tty`** (o que já sabíamos não resistir a quem controla o stdio). TTL de
8 h, então ainda estava vivo quando o App real entrou no ar.

O consentimento dado foi "deixe este ensaio com chave falsa ler um repo"; o que
ele silenciou foi "cunhe tokens reais do App real". Mesma classe da colisão de
sessão consertada mais cedo (chave só pelo nome do repo): **o grant não guardava
o bastante do contexto que tornou a aprovação significativa.** Consertado — ele
agora é preso também a `dry_run`, ao portão que o concedeu (um `tty` não herda a
autoridade do diálogo) e a um fingerprint da credencial-mãe derivado da config,
não do material da chave, para não disparar o AV a cada validação. Grants
anteriores ao conserto morrem sozinhos por não terem o campo.

Verificado ao vivo: com um grant de `--dry-run` ativo, a cunhagem real **promptou
de novo** (`portao=gui`), e a leitura real seguinte voltou a ser silenciosa em
0,9 s — o conserto não custou a propriedade de produtividade.

## Fase 4 — Higiene contínua

> Ferramental executado em 29/jul/2026. `scripts/verify-hardening.sh`:
> **14 ok, 0 alertas, 0 falhas.** Passo a passo humano:
> `docs/runbook-fase4-rotacao.md`.

- [x] Rotação **trimestral**: chave do GitHub App (gerar nova → atualizar
  broker → deletar antiga; só pela UI, 25-key headroom, sem downtime) e chave
  da SA-broker. → `av-broker rotate --target github|gcp`.
  ⚠️ **Em 18/ago/2026 o ramo `github` saiu**: não há mais chave de App para
  rotacionar, e `ROTATION_TARGETS["github"]`/`["github-dev"]` foram removidos.
  A rotação do GitHub virou **gesto manual** em
  `github.com/settings/personal-access-tokens` — revogar o PAT antigo, criar o
  novo, `gh-pat set host` / `gh-pat set vm`. Nenhum código lembra por você.
  O `--target gcp` (e Salesforce/Shopify) segue valendo integralmente.
  Duas decisões que não são acidentais: o segredo entra por **stdin**, nunca por
  argumento (`argv` é legível por qualquer processo seu no `ps`); e o broker
  **verifica antes de trocar** — assina um JWT com a chave nova e chama
  `GET /app`; se não autenticar, nada é gravado e a velha continua valendo. É
  isso que dá o "sem downtime", não a folga de 25 chaves.
- [x] Rotação **semestral**: `claude setup-token`. → `av-broker rotate --target
  anthropic`.
- [x] Revisão trimestral das instalações do App (mínimo de repos, teto de
  permissões) e das SAs de projeto (bindings órfãos). → ~~`av-broker review`
  sinaliza seleção diferente de "Only select repositories", permissão fora do
  teto acordado e excesso de repos.~~ **`av-broker review` foi removido em
  18/ago/2026** — ele só sabia auditar instalações de GitHub App, e não há
  mais App. A revisão trimestral do GitHub agora é olhar a lista de PATs em
  `github.com/settings/personal-access-tokens`: escopo, repos selecionados e
  data de expiração, a olho. O `gcloud-admin` (revisão das SAs) foi
  fiado no `home.nix` — era a pendência que a Fase 3 deixou anotada.
- [x] Script de verificação de hardening (juntar à FASE 8 do checklist):
  canaries vivos, `ignore-scripts` na imagem, proxy/pf conforme o modo, nenhum
  PEM/refresh-token em disco. → `scripts/verify-hardening.sh`, 7 seções.
  Ele delega o que é gate de fase ao `verify-fase0.sh` em vez de duplicar, e
  distingue **alerta** de **falha**.

**Gate:** primeira rodada de rotação executada e registrada no log JSONL.
⏳ **Pendente do gesto humano**, como a Fase 0: não há chave real de App para
rotacionar até o App existir. O caminho está exercitado ponta a ponta contra o
alvo `github-dev` (a chave descartável), incluindo o registro no JSONL.

**Medido.** Rotação é classificada como **escrita** (ADR §6.5): prompta sempre,
nunca abre sessão, nem para o segundo alvo da mesma rodada. Verificado que ela
**falha fechada** — `--no-prompt` recusa e grava `result: "no-prompt"` no log,
que é exatamente o evento que se quer enxergar se alguém tentar automatizar a
troca da raiz de confiança.

**Detalhes de desenho que economizam um bug depois:**

- A idade da credencial sai do **log JSONL**, não do Keychain. `security -U`
  preserva o `cdat` do item, então uma credencial recém-rotada continuaria
  parecendo velha; o `cdat` fica só como piso para quem nunca rodou uma rotação.
- O log registra a **impressão SHA-256 da chave pública** derivada do PEM —
  permite conferir *qual* chave está em uso sem que material secreto entre no
  log.
- Credencial **ainda não custodiada** não conta como vencida no `doctor`. Marcar
  em vermelho todo dia algo que depende de outra fase é a fadiga de alarme que o
  §6.5 combate.
- O alvo `github-dev` existe para que a rotação possa ser exercitada de verdade
  antes da Fase 0, sem plantar chave falsa no slot de produção — o que faria o
  `verify-fase0.sh` mostrar verde mentindo.

---

## no-mistakes dentro da microVM

Até 31/jul/2026 o `meu-projeto` rodava em `direct-PR` porque o `no-mistakes`
não existia na VM. O registro do firstmate chegou a afirmar que era
**impossível**; não era. O que estava medido era "não instalado" e "não alcança
o daemon do HOST" — um daemon local ao guest nunca tinha sido tentado. A
correção do vocabulário importa: não é impossível, é *não montado*.

**Metodologia que este desenho serve** (decisão do capitão): sem worktree na VM
— checkout da `main` —, o Claude Code cria a branch efêmera na hora do PR e
**faz o merge**. O capitão confere o resultado, não o merge.

### Fase 0 — exercitar o pipeline no host  ✔ parcialmente

O `nm-cpf-1` rodou `/no-mistakes` num spawn de host sobre uma tarefa real
(testes para `services/cpf_utils.py`). `review`/`test`/`document`/`lint` verdes,
`outcome: passed`. Os passos `pr` e `ci` foram **skipped** — ver o achado do
`gh auth status` no `AGENTS.md`.

### Fase 1 — os dois binários na imagem-base  ✔

- `nix/no-mistakes.nix`: pin **único**, importado pelo host (`home.nix`) e pelo
  guest (`flake.nix` → `packages.aarch64-darwin.no-mistakes-guest`). Duplicar o
  pin deixaria um bump pela metade passar no build e falhar só no `fm-bootstrap`.
- Cross-compila trocando o pacote `go`, não via `pkgsCross`: o `buildGoModule`
  faz `env = args.env or {} // { inherit (go) GOOS GOARCH; }` — o lado direito
  ganha, então `env` do chamador **não** muda o alvo. `pkgsCross` funcionaria mas
  arrastaria um gcc darwin→linux fora do cache binário, inútil para Go puro com
  CGO desligado.
- Efeito colateral do stdenv continuar nativo: o achatamento de
  `bin/GOOS_GOARCH/` do `buildGoModule` só roda quando
  `hostPlatform != buildPlatform`, então o `postInstall` faz isso à mão.
- `gh` entra como release oficial do `cli/cli`, sha256 pinado, mesmo padrão do
  herdr. Ficou em **2.96.0**: a 2.97.0 saiu dentro do cooldown de 3 dias que o
  próprio `provision-base.sh` declara.
- Verificado: binário do host **byte a byte idêntico** ao anterior ao refactor
  (`77996db5…`), e ambos os binários do guest respondem `--version` rodando de
  verdade num aarch64 Linux, com `timeout 30` para que um stall não vire
  bloqueio mudo.

### Fase 2 — ligar o guest  ✔ escrita, ✔ medida em 01/ago/2026

O gancho é o `startDetachedDaemon`: sem launchd nem systemd no guest, o daemon
**herda o ambiente** de quem o inicia — ao contrário do host, onde o launchd
entrega ambiente mínimo e só repassa `proxyEnvKeys`.

Escrito em `scripts/claude-shuru` sob a flag **`--no-mistakes`** (opt-in: o
caminho `direct-PR` está provado e não muda de comportamento por causa deste).
Antes de o agente existir, o guest passa a: apontar o `origin` do `/work` para a
URL canônica https herdada do repo-pai, exportar o `Authorization: Basic` por
`GIT_CONFIG_*`, exportar `GH_TOKEN` com o placeholder, subir
`no-mistakes daemon start` e rodar `init` + `doctor`. Falha em qualquer um deles
aborta o boot: um daemon meio de pé faria o agente bater no erro só depois do
trabalho caro.

A flag também soma `checks=read` à cunhagem — **só** com `--no-mistakes`,
porque pedir permissão que a instalação não tem devolve 422 e derruba a cunhagem
inteira, o que quebraria o `direct-PR` em qualquer instalação sem `Checks`.

- [x] **`Checks: Read-only` no App.** Antes do alargamento, pedir `checks=read`
  devolvia **HTTP 422** — `"The permissions requested are not granted to this
  installation."` — derrubando a cunhagem **inteira**. Não há rebaixamento
  silencioso: o comportamento é seguro, mas elimina "pedir e seguir sem" como
  fallback. Uma versão anterior deste plano dizia 403; é 422. Exigiu dois
  gestos, e o segundo é o esquecido: alargar em `settings/apps` **e aceitar** na
  instalação — o GitHub não aplica permissão nova a instalação existente, nem
  quando o dono do App é quem instalou. Feito em 01/ago/2026; a cunhagem passou
  a sair (`ghs_`, 390 bytes) e `checks:read` responde.
- [x] **Sonda válida para token de App.** `gh api user` **não serve**: devolve
  sempre `403 Resource not accessible by integration`, porque token de
  instalação não tem usuário autenticado. Uma versão anterior deste plano
  mandava sondar exatamente isso de dentro da VM — daria 403 com o proxy
  funcionando perfeitamente, e seria lido como quebra. Use
  `gh api repos/OWNER/REPO` (devolve `full_name`), e para o que o pipeline
  precisa, `gh auth status --hostname github.com` → exit **0**, que é o teste
  literal do `Available()`.
- [ ] Medir a checagem de atualização do `no-mistakes` sob egresso negado
  (deve falhar suave).

#### O que o boot de 01/ago/2026 provou

Um boot só, com `claude-shuru --from meu-projeto --github-write
SEU-USUARIO/meu-projeto --no-mistakes`, executando uma tarefa real (a PR
[#652](https://github.com/SEU-USUARIO/meu-projeto/pull/652), que conserta
o `collect_ignore` do `services/conftest.py`). Tarefa real e não sonda sintética
de propósito: o que interessa é o caminho que o pipeline vai usar.

> *Nota de 18/ago/2026 sobre a linha de comando acima:* hoje a flag é
> **`--github`, sem argumento** — o alcance é o escopo do PAT, definido na UI do
> GitHub, não um repo passado aqui. `--github-write OWNER/REPO` continua
> aceita como alias e **ignora o repo**, para não quebrar invocações antigas
> como esta. O registro do boot fica como foi feito.


| O que estava em aberto | Resultado |
|---|---|
| `startDetachedDaemon` sobe sem systemd | **sim** — `no-mistakes doctor` passou no guest |
| `gh` lê o placeholder através do proxy | **sim** — `gh auth status` exit 0 |
| `gh` alcança a API com o token substituído | **sim** — `gh api repos/…` devolveu `full_name` |
| `git push` com `Authorization: Basic` pelo proxy | **sim** — branch subiu do guest |
| `gh pr create` de dentro da VM | **sim** — PR #652 |

**O gate do `no-mistakes` continua sem prova, e a sonda que usei estava errada.**
Procurei por `/work/.no-mistakes` e não achei — mas esse diretório **não existe
por desenho**, nem no host: o gate é um bare repo em
`~/.no-mistakes/repos/<hash>.git`, ligado ao repo por um remote chamado
`no-mistakes` (`git remote -v` no host mostra os dois). Ou seja, o "FALHOU" foi
da sonda, não do guest.

E o `doctor` não cobre esse buraco: ele é do **sistema** (git, gh, daemon,
agentes) e passa igual num repo sem gate nenhum — medido rodando-o dentro e fora
do `meu-projeto`, saída idêntica. Um `doctor` verde nunca significou "este
repo está inicializado".

Por isso o `claude-shuru` deixou de confiar no `init >/dev/null || true`
sozinho: agora ele exige `git remote get-url no-mistakes` logo depois, e aborta
o boot se o remote não existir. A dúvida vira asserção no momento barato, em vez
de erro depois do trabalho caro — que é a mesma regra do resto do bloco.
- **Armadilha de redação, custou exposição parcial em 01/ago/2026.** O token de
  instalação novo do GitHub é um **JWT** (contém `.`, `_`, `-`), então a regex
  `gh[oprsu]_[A-Za-z0-9]+` casa só o prefixo e para no primeiro ponto, deixando
  o corpo passar. Não redija segredo por regex de formato: **descarte a linha
  inteira** (`grep -vi 'Token:'`). O `gh auth status` mascara a cauda por conta
  própria, o que limitou o estrago — mas isso foi sorte do formato do `gh`, não
  do desenho da redação.

### Fase 3 — variante do brief para VM  ✔ escrita

`firstmate/bin/fm-brief.sh` ganhou a flag **`--vm`**, no padrão do `--scout` e do
`--herdr-lab`. Ela muda exatamente duas coisas num brief `no-mistakes`:

- **Regra 7.** A proibição de mexer no daemon continua, mas o *motivo* passa a
  ser verdadeiro no contexto: na VM o daemon é do próprio crewmate, não uma
  instância compartilhada, então reiniciá-lo não machuca outras lanes — destrói
  o run dele e o estado do gate. Regra cuja razão declarada é falsa no contexto
  é regra que agente aprende a descontar.
- **Linha final.** Na VM o crewmate faz o merge (squash + apaga a branch,
  tolerando "already merged") e reporta `done: PR {url} merged`. No host ele
  para no CI-verde. A diferença existe porque a microVM é destruída no fim do
  run: um PR parado em CI-verde não teria quem o mergeasse. Casa com a
  metodologia do capitão — ele confere o resultado, não o merge.

Regressão verificada: o caminho do host sai **byte a byte idêntico** ao anterior
(regra 7 e linha final comparadas contra o brief do `nm-cpf-1`, gerado antes da
mudança).

- [ ] **Gesto do capitão:** `auto-merge.yml` restrito a label — o App não tem
  permissão de `Workflows`, então nenhum token cunhado aqui consegue tocar em
  arquivo de workflow.

  **Medido em 01/ago/2026**, e não mais deduzido. Uma tarefa que alterava
  `.github/workflows/ci.yml` foi levada até o `push` com token do App; o GitHub
  recusou no servidor, palavra por palavra:

  ```
  ! [remote rejected] HEAD -> fase4/ci-push-main (refusing to allow a GitHub App
    to create or update workflow `.github/workflows/ci.yml` without `workflows`
    permission)
  ```

  A fronteira segura. O teto do App (`contents`, `pull_requests`, `metadata`,
  auditado em `av-broker:1538`) não é declaração de intenção: é aplicado do outro
  lado do fio.

### Fase 4 — uma tarefa real de ponta a ponta

Só depois disso o `projects.md` vira `[no-mistakes]` de forma permanente.

**Ainda não aconteceu.** A tentativa de 01/ago/2026 não atravessou: a etapa 1
morreu no portão de confiança (ver a correção da Rota 1 abaixo) e a etapa 2
parou no limite de `workflows`, que era o resultado esperado da tarefa
escolhida. Nenhuma PR foi aberta, nenhum CI rodou. O `projects.md` continua
`[direct-PR]`, que descreve o que existe.

### Risco ~~em aberto~~ **encerrado em 18/ago/2026**: o token expira antes de o pipeline terminar

> **Encerrado por remoção do mecanismo, não por solução.** Em 18/ago/2026 o
> token de instalação deixou de existir nesta máquina (Rota 4, adotada); um PAT
> de vida longa não expira no meio de um run. Tudo o que segue nesta seção — as
> quatro rotas, as medições, as recusas — continua **verdadeiro para o período
> 29/jul–18/ago/2026** e é o material que justifica a virada. Leia como
> histórico.

O token de instalação vive **1 h** e é cunhado no boot. Um run completo roda
`review` com um agente dentro da VM; se passar de uma hora, os passos `pr` e
`ci` morrem com 401 **depois** de todo o trabalho caro já feito. Aconteceu ao
vivo em 01/ago/2026: um `gh pr list` no host, horas depois da cunhagem, devolveu
`HTTP 401: Bad credentials`.

**Primeiro, uma correção de vocabulário: "renovar" não existe.** O GitHub fixa o
token de instalação em 1 h e não publica endpoint de refresh — não há
`refresh_token`, não há extensão. Toda renovação é uma **cunhagem nova**. A
pergunta real é: como cunhar de novo sem um diálogo por hora, sem quebrar o
ADR §6.5?

#### Por que hoje custa um diálogo por cunhagem

Não é acidente, é a política, e ela está no código. `av-broker:838`:

```
write  → prompta SEMPRE (nunca silencioso, nunca cacheado)
read   → silencioso se a sessão do projeto está viva; senão prompta e abre sessão
```

e `av-broker:863` só chama `record_grant` quando `klass == "read"`. O comentário
ao lado é explícito: *"Aprovar um write NÃO silencia os próximos writes — é
exatamente o ponto do gate."* Como o pipeline pede `contents=write` e
`pull_requests=write`, toda cunhagem cai no ramo que sempre prompta.

A máquina de sessão já existe e é boa: `grants.json`, teto de 8 h
(`SESSION_TTL_CEILING`), e um `session_valid` que invalida por `target`,
`dry_run`, `cred` (fingerprint da chave-mãe, para que rotação derrube a sessão) e
força do portão. O que falta é **permissão de política**, não código.

#### Rota 1 — duas etapas  *(⚠️ a etapa 1 NÃO funciona — medido em 01/ago/2026)*

> **Correção de 01/ago/2026, noite.** A premissa desta seção é falsa. "O token
> não precisa existir durante a parte cara" foi escrito antes de alguém rodar um
> `no-mistakes axi run` de verdade na etapa 1. Quando isso foi feito, o run
> **falhou antes de qualquer step existir** (`steps[0]`, sem gate, sem finding):
>
> ```
> git fetch ... origin +refs/heads/main:...
>   → fatal: could not read Username for 'https://github.com': terminal prompts disabled
>   → cannot evaluate disable_project_settings: failed to fetch or resolve
>     trusted default branch "main" (refusing to run without reading the trusted config)
> ```
>
> Confirmado no fonte, não só no relato do agente: `internal/daemon/manager.go`
> linhas 208–223 roda `fetchRecoveredRemoteBranch(ctx, workDir, "origin",
> defaultBranch)` antes de montar a config; se o fetch falha, `trustedSHA` fica
> vazio e `assertGateTrustedConfigReadable` **aborta o run**. E a razão declarada
> é boa: `disable_project_settings` é fronteira de segurança lida só da cópia
> confiável do branch default, então config confiável ilegível não pode ser
> tratada como "não optou por sair".
>
> **`--skip` não alcança isso** — não é um step do pipeline, é um portão pré-run.
> O `no-mistakes` exige rede autenticada contra o `origin` no primeiro segundo.
>
> O que sobreviveu ao teste: a **etapa 2 funciona**. Retomando do checkpoint com
> token cunhado, `intent` e `rebase` completaram contra o `origin` real — o que
> por si só confirma o diagnóstico acima, porque a única diferença entre as duas
> etapas era a credencial.
>
> **Saída possível, e é decisão de política:** o fetch de confiança precisa de
> `contents=read`. Leitura é **silenciosa** enquanto a sessão do projeto está
> viva (`av-broker:836`), então um token read-only na etapa 1 satisfaria o portão
> sem custar gesto humano. O preço é que passaria a existir credencial dentro da
> VM durante a corrida longa — que é exatamente o que a Rota 1 existia para
> evitar. `claude-shuru:78` recusa token na etapa 1 hoje por esse motivo. Mudar
> isso é emenda ao desenho, não ajuste de script.

O token não precisa existir durante a parte cara. A peça que faltava não era
nossa: o **`shuru checkpoint create` roda um comando E salva o disco**. Com ela,
o `/work` (commits do agente) e o `~/.no-mistakes` (estado do run, gate, banco)
sobrevivem ao fim do boot — sem bundle, sem mount de escrita, sem importar nada
no host. E o guest já tolerava `/work` existente (`if [ ! -d /work ]`), então a
etapa 2 continua de onde a 1 parou.

```sh
# etapa 1 — cara, longa, SEM token e SEM diálogo
claude-shuru --from meu-projeto --stage1 etl-wip -- "… no-mistakes axi run --skip rebase,push,pr,ci …"
# etapa 2 — curta; só ela recebe o token, e só então empurra
claude-shuru --from etl-wip --github --no-mistakes -- "… no-mistakes axi run --skip review,test,document,lint …"
shuru checkpoint delete etl-wip     # o WIP são ~GB
```

Passos válidos do pipeline (`internal/types/types.go:30-38`): `intent`, `rebase`,
`review`, `test`, `document`, `lint`, `push`, `pr`, `ci`. A etapa 1 pula
`rebase` também porque ele fala com o `origin` — sem token, num repo privado,
falharia.

O relógio de 1 h só começa **depois** do trabalho caro. Não resolve o run único
e longo, e exige o capitão presente na etapa 2 — mas é a única rota que não
pede nada de ninguém.

> *18/ago/2026:* não há mais relógio, e o `--github` não pede mais gesto — mas a
> divisão em duas etapas **ficou**, com outra justificativa: a etapa longa, que
> roda código de terceiro com o agente solto, não precisa ver credencial
> nenhuma. Segregação de privilégio, não contorno de relógio.

**Duas recusas explícitas, pelo mesmo motivo.** Token morto no `no-mistakes` não
dá erro: o `Available()` roda `gh auth status`, lê saída ≠ 0 como "não
autenticado" e **pula `pr` e `ci` em silêncio**, com o run reportando
`outcome: passed`. Então (i) o host recusa `--stage1` junto com token, e (ii) o
guest **zera** `GH_TOKEN`/`GITHUB_TOKEN`/`GITHUB_BASIC` na etapa 1.

O (ii) não é zelo teórico: o `[ -n … ]` sozinho não bastava, porque **o shuru
injeta o placeholder mesmo quando o host não tem valor**. Medido — a etapa 1
subiu com `GH_TOKEN` preenchido e o guest respondeu `The token in GH_TOKEN is
invalid`. Token inválido é pior que ausente aqui.

Cunhar "no meio" do run continua impossível, e vale registrar por quê: o
`av-broker` é do host e macOS-only, e o valor real entra na VM como placeholder
resolvido pelo proxy **no momento do `shuru run`**. Não há processo do host capaz
de injetar valor novo numa VM já de pé — é exatamente o que a Rota 3 pediria.

#### Rota 2 — mandato limitado (mudança de política, exige emenda ao ADR)

Um gesto humano aprova não "um token", mas *até N cunhagens idênticas — mesmo
repo, mesmo conjunto de permissões, mesma credencial-mãe, mesma força de portão
— dentro de T horas*, revogável. Tecnicamente é pequeno: reusar `record_grant`
para escrita, com teto próprio bem abaixo das 8 h e um contador.

Isso enfraquece o gate de escrita, e não adianta fingir que não. O que o torna
discutível em vez de temerário é o escopo: hoje uma aprovação de escrita
autoriza **uma** cunhagem; no mandato ela autorizaria **N cunhagens
indistinguíveis daquela**, não escrita arbitrária. Ainda assim é exatamente a
regra que o `av-broker:861` existe para negar. Não faça sem emendar o ADR §6.5
por escrito — mudança silenciosa de política de segurança é como se perde a
confiança no portão inteiro.

#### Rota 3 — renovar no proxy, e o token nunca entra no guest  *(bloqueada)*

É a que se encaixa na arquitetura. O guest **já** só vê um placeholder; o valor
real vive no host, dentro do proxy do shuru. Se o proxy relesse o valor a cada
substituição em vez de capturá-lo no launch, o host poderia trocar o token por um
fresco e o guest nunca perceberia — o placeholder é estável para sempre e a
validade de 1 h deixa de ser problema dele.

Ganho extra, e não é pequeno: a credencial nunca cruza para dentro da VM. Um
guest comprometido consegue **usar** o proxy enquanto a VM vive, não **levar** um
token embora.

Bloqueio medido: o `shuru.json` declara `secrets.<NOME>.from = <VAR>` e o valor é
lido do ambiente do processo no `shuru run`. O `shuru` não tem subcomando
`secret` nem caminho documentado de refresh. Rota 3 depende de capacidade que o
shuru não expõe — pedido upstream ou fork, não decisão nossa.

E mesmo com ela pronta, a cunhagem silenciosa continuaria pedindo a Rota 2: o
proxy resolve *como entregar* o token novo, não *quem autoriza* cunhá-lo.

#### Rota 4 — PAT de vida longa  *(rejeitada em 01/ago/2026 — **adotada em 18/ago/2026**)*

**O texto da rejeição, preservado palavra por palavra como foi escrito em
01/ago/2026:**

> Trocaria credencial efêmera e escopada por credencial longa no disco. É o
> oposto declarado deste plano inteiro. Fica aqui só para não ser reinventada.

Foi reinventada dezessete dias depois, e adotada. O parágrafo acima fica onde
está porque **ele continua tecnicamente correto**: a adoção da Rota 4 não é
melhoria de segurança. É **troca de segurança por ergonomia**, feita de olhos
abertos, e quem ler este documento daqui a um ano precisa encontrar as duas
frases lado a lado, não só a segunda.

**Por que a mesa virou: custo humano, não argumento novo de segurança.** Nada
que a rejeição dizia sobre o risco deixou de valer. O que mudou foi a conta do
outro lado, e ela foi *medida*, não estimada:

- **Um gesto por cunhagem.** A política do ADR §6.5 é que qualquer cunhagem com
  permissão de write prompta SEMPRE — diálogo nativo do macOS com palavra
  polimórfica a digitar. Como todo run de `no-mistakes` pede `contents=write` e
  `pull_requests=write`, **toda** cunhagem caía nesse ramo. Não era o gesto
  ocasional que o desenho previa; era o gesto de rotina.
- **O diálogo não vinha sozinho.** Em 02/ago/2026 o Automic Vault produziu
  **582 diálogos num dia** e o Keychain pediu **28 senhas no mesmo dia**. O
  gesto do broker chegava a uma atenção já gasta — que é a definição operacional
  de fadiga de alarme, o Problema 4 que o §6.5 diz combater. Um portão que
  aparece no meio de 582 outros diálogos não está sendo lido; está sendo
  clicado.
- **O token morria no meio do trabalho.** TTL de 1 h, teto rígido do GitHub, sem
  endpoint de refresh. Foi isso que gerou a Rota 1 (`--stage1`), a Rota 2
  (mandato limitado, engavetada) e a Rota 3 (pedido upstream, sem resposta) —
  três desenhos inteiros para contornar um relógio. E a Rota 1, medida, **não
  funcionava como escrita** (ver a correção de 01/ago/2026 acima: a etapa 1
  abortava no `git fetch` do gate).

**O que se comprou:** zero gesto; token que não expira no meio de um run; e um
`gh` de *conta* — `gh repo list`, `gh search`, criar repositório —, coisas que o
token de instalação nunca fez e nunca faria, por definição: ele é escopado a uma
instalação, não à conta.

**O que se pagou, item por item:**

| Perdido | Era | Virou |
| --- | --- | --- |
| Credencial efêmera | `ghs_…` com TTL de 1 h | PAT que vale até você revogar no github.com |
| Escopo por repositório | 1 repo por cunhagem | o escopo que o PAT tiver, escolhido na UI e esquecido lá |
| Menor privilégio por comando | read por default, write só quando a tarefa exigia | um escopo só, o tempo todo |
| Portão humano | diálogo por cunhagem de write | nenhum — o item está no login keychain, com ACL normal |
| Log de auditoria de cunhagem | `~/.local/state/av-broker/mints.jsonl` | nada local; só o que o GitHub mostrar |
| Rotação automatizável | `av-broker rotate --target github` | lembrete humano em `github.com/settings` |
| Janela de vazamento | ≤45 min (cache de leitura), 1 repo, só leitura | indefinida, até a revogação manual |

**A mitigação que sobrou, e é pequena: são DOIS PATs, não um.**
`github-pat` fica no Mac e só o `scripts/gh-token.sh` (o `gh` do PATH) o lê;
`github-pat-vm` é o que viaja para dentro do guest do shuru, onde qualquer
código que rode na VM consegue lê-lo — é o de menor privilégio. Dois itens
existem por uma razão única: quando um vazar, dá para saber **qual cópia** e
revogar só ela. Isso não devolve efemeridade nem escopo; só torna a resposta a
incidente possível em vez de cega.

**Uma nota sobre `-T ""`.** Não se tentou criar os itens com ACL vazia para
fingir um portão. A Automic Vault destranca o chaveiro, e chaveiro destrancado
anula a ACL — medido. Um `-T ""` aqui daria a *aparência* de portão sem o
portão, o que é pior que assumir que não há portão nenhum.

#### Ordem invertida: o código veio antes da emenda ao ADR (18/ago/2026)

Este documento diz, na Rota 2 logo acima, que política de segurança não se muda
sem emendar o ADR §6.5 **por escrito, antes** — e que mudança silenciosa é como
se perde a confiança no portão inteiro. Vale registrar sem maquiagem: **desta
vez a ordem foi a inversa.** Em 18/ago/2026 o código foi escrito primeiro
(`scripts/gh-broker.sh` removido, `scripts/gh-token.sh` e `scripts/gh-pat.sh`
criados, alvo `github` extirpado do `av-broker`), e só depois o ADR recebeu a
emenda (`arquitetura-segredos.md` §6.6) e este plano foi corrigido.

Duas atenuantes reais, que não apagam o fato: a mudança **removeu** um portão em
vez de enfraquecê-lo em silêncio — não há como usar o gate de GitHub sem
perceber que ele não existe mais, porque o comando `av-broker github` some da
`--help` —, e a decisão é do dono único da máquina, sem ninguém a quem a
política prometesse algo. Ainda assim, a regra da Rota 2 continua valendo para
os alvos que sobraram (Shopify, GCP, Salesforce): ali, emenda primeiro.

#### Decisão do capitão (01/ago/2026, **revista em 18/ago/2026**)

> **Decisão original de 01/ago/2026, mantida como registro:**
>
> **Rota 1 agora** — feita, medida, em `scripts/claude-shuru` sob `--stage1`.
> **Rota 3 como pedido upstream ao shuru** — **enviada** em 01/ago/2026,
> [superhq-ai/shuru#40](https://github.com/superhq-ai/shuru/issues/40), texto em
> `docs/pedido-shuru-refresh-secret.md`, porque é a única que melhora a segurança
> em vez de só a ergonomia. Enquanto não houver resposta, nada muda: a Rota 1
> continua sendo o caminho, e o pedido não é bloqueante para nada aqui.
> **Rota 2 fica na gaveta**, e só sai dela se a Rota 1 doer na prática — nesse
> caso, emenda ao ADR §6.5 primeiro, código depois.

**Revisão de 18/ago/2026 — a Rota 4 passou por cima de todas.** A Rota 1 doeu na
prática *e* não funcionava como escrita; a Rota 2 continuaria custando um
diálogo a cada N cunhagens; a Rota 3 nunca teve resposta upstream. Em vez de
escolher entre as três, o capitão removeu o problema que elas resolviam:
**sem token de 1 h, não há renovação a orquestrar.**

Estado de cada rota depois da revisão:

- **Rota 1 (`--stage1`) — FICA, com outra justificativa.** Não é mais "o token
  de 1 h morre no meio do run". É: **a etapa longa, que roda código de terceiro
  com o agente solto, não precisa ver credencial nenhuma.** A flag continua
  recusando token junto com `--stage1`, e o guest continua zerando
  `GH_TOKEN`/`GITHUB_TOKEN`/`GITHUB_BASIC` na etapa 1. Segregação de privilégio,
  não contorno de relógio.
- **Rota 2 (mandato limitado) — segue na gaveta, e agora sem uso para o
  GitHub.** Continua sendo a rota certa se algum dia o gesto do Shopify, do GCP
  ou do Salesforce virar rotina.
- **Rota 3 (refresh no proxy) — perdeu o motivador do GitHub**, mas o pedido
  upstream continua de pé pelo `CLAUDE_CODE_OAUTH_TOKEN`. Ver
  `docs/pedido-shuru-refresh-secret.md`.
- **Rota 4 — adotada.**

**Como o token entra na VM agora, e por que não pelo canal de segredos do
shuru.** O `shuru run` não tem `--env`, e o único canal declarado
(`--secret NAME=ENV@HOSTS`) injeta um **placeholder** que o proxy troca no
egress — que é justamente a propriedade que se deixou de querer aqui, porque ela
exigia que cada projeto declarasse `secrets.GITHUB_TOKEN` no seu `shuru.json` e
que o host pré-codificasse `GITHUB_BASIC`. O caminho adotado é mais burro e mais
explícito: o host escreve o PAT num diretório temporário (0700, arquivo 0600) e
o monta em `/ghcred/token` **read-only**; o guest lê, exporta
`GH_TOKEN`/`GITHUB_TOKEN` e codifica o blob Basic sozinho. Consequência boa: os
`shuru.json` dos projetos não declaram mais segredo de GitHub nenhum.
Consequência ruim, dita por extenso: **o valor real do PAT passa a existir
dentro da VM**, coisa que o desenho de placeholder evitava. É o mesmo trade
desta seção inteira, na fronteira host↔guest.

**Gatilho de reavaliação:** se um PAT vazar, ou se o GitHub passar a oferecer
cunhagem de token de conta escopado e sem gesto, esta decisão volta à mesa.

---

## Riscos residuais (documentados, não resolvidos)

- **Exfiltração por domínio permitido** (push/gist/issue no repo escopado com
  token válido): mitigado — não eliminado — pelo write-prompt do broker e pelo
  downscoping read-only por default. MITM seletivo fica como opção futura.
- **Prompt injection não está resolvido** (Nasr et al. 2025): a aposta é
  contenção arquitetural, nunca defesa no nível do modelo.
- **setup-token é credencial de ~1 ano**: custodiada no host sob AV e trocada
  só no egress, mas dentro da janela vale a assinatura inteira para model
  requests. Rotação semestral + revogação no claude.ai são o limite.
- ~~**shuru `--allow-net` não verificado**~~ **Verificado em 29/jul/2026** (Fase
  2): 12 testes adversariais, nenhum caminho fora da allowlist. O `eth0` real
  em 10.0.0.2/24 que a Fase 1 anotou existe, mas não é rota — os quadros vão
  para a pilha em modo usuário do shuru, não para uma NAT do kernel.
  Permanece como risco: o mecanismo é **um só processo**. Se o `shuru-proxy`
  tiver um bug de fail-open, não há segunda camada atrás dele — foi
  precisamente a razão de recusar o `pf` que some a decisão, e o preço dela.
  Re-rodar `scripts/shuru-verify-fase2.sh` a cada bump de versão do shuru é o
  que mantém isso honesto.
- **Canal encoberto de baixa largura** continua aberto por construção: o
  resolver do shuru responde a nomes da allowlist, e timing/sequência de
  requisições a hosts permitidos não é observado por ninguém.

## Gatilhos de reavaliação

- Anthropic permitir WIF no pool da assinatura → migrar do setup-token para
  token de 1 h (ADR §6.4).
- shuru abandonado/reprovado → plano B Apple `container` + Squid + `pf`
  (arquitetura da versão anterior da FASE 7).
- Projeto Salesforce nesta máquina → ativar o plugin do broker (ADR §6.2).
- Sessões longas sem supervisão no host → reavaliar o risco aceito 6.7 e o
  item 7.5 (Santa).
