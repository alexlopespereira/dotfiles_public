# av-broker — cunhagem JIT de credenciais efêmeras

Fase 3 de `docs/plano-adocao-tokens.md`. Implementa o "broker no host" do ADR
(`docs/arquitetura-segredos.md` §6): a chave-mãe fica no Keychain sob o Automic
Vault, o broker cunha um token curto e escopado, e **só o token efêmero cruza a
fronteira host→VM**.

```
Keychain (chave privada, sob AV)
      │  av inject → prompt do AV
      ▼
  av-broker  ──┬── GCP:        JWT RS256 → impersonation → access token (≤1 h, escopo mínimo)
               └── Salesforce: JWT Bearer (ADR §6.2) → access token + instance_url
      │
      ▼  stdout (transporte plugável — ver "Pendências")
   consumidor
```

## Estado

**O alvo GitHub saiu do broker em 18/ago/2026.** A cunhagem efêmera do App
(`alex-agent-broker`, em produção desde 29/jul/2026) foi trocada por dois PATs
fine-grained de vida longa: `github-pat` no login keychain do Mac e
`github-pat-vm` para o container/VM. A perda de segurança — segredo de vida
longa, sem portão por cunhagem — foi aceita explicitamente. Com o provedor saiu
também o subsistema de agente, que existia só para segurar a chave privada do
App em RAM. **GCP e Salesforce continuam cunhados aqui, sem mudança.**

O que segue nesta seção é o histórico do item do GitHub no Keychain. Ele fica
porque é a medição que justifica o desenho do chaveiro dedicado, que vale para
TODAS as credenciais que restaram.

**ACL do item do GitHub endurecida em 29/jul/2026.** Ele havia sido criado **sem**
`-T ""` (`scripts/salesforce-keypair.sh`, o runbook privado da Fase 0), então
qualquer invocação de `security` lia a chave-mãe **sem diálogo nenhum** — medido
em 0,02s, contra 4,7s do item do GCP. A chave em produção era a menos protegida
das duas. Corrigido recriando o item com `-T ""`, com cópia de segurança dentro do
próprio Keychain (nunca em disco) e conferência por SHA-256 antes e depois.

⚠️ **`-T ""` só vale na criação.** `security add-generic-password -U -T ""` num
item existente **não** substitui a ACL: a primeira tentativa de conserto passou
sem erro e deixou o item exatamente tão frouxo quanto antes. Endurecer exige
apagar e recriar — e por isso exige backup.

⚠️ **E `-T ""` sozinho não cobrava nada.** Corrigido em 02/ago/2026, depois de
medir: com o item no `login.keychain`, a ACL vazia **não** abria diálogo. O
`partition_id` do item lá é aberto (`applications: <null>`, isto é, qualquer
aplicativo) e o chaveiro de login fica destrancado a vida inteira — o Automic
Vault o destranca ativamente, e um monitor de 90 minutos não registrou **uma**
transição para trancado. O endurecimento de 29/jul era, na prática, decorativo.

Quem cobra o gesto é o **par**: ACL vazia **mais** chaveiro próprio. Prova nos
três sentidos, medida no mesmo dia:

| chaveiro | leitura com ele destrancado | o AV destranca? | sobrevive à search list? |
|---|---|---|---|
| `login`   | silenciosa       | sim, em ~5s | — |
| dedicado  | **pede gesto**   | **não** (45s sem tocar) | **sim** |

## Chaveiro dedicado

Desde 02/ago/2026 as credenciais — GCP, as duas de Salesforce e o
`claude-setup-token` (a do GitHub App saiu em 18/ago/2026) — vivem em `~/Library/Keychains/av-broker.keychain-db`,
não no `login`. O broker **não mudou uma linha** para achá-las:
`find-generic-password -s <serviço>` varre toda a *search list*, e a ACL continua
sendo cobrada mesmo com o chaveiro dentro dela (foi o que a última coluna da
tabela mediu — era a hipótese que poderia matar o plano).

Efeito medido no mesmo dia, na chave do GCP: leitura de **0,02 s** no `login`
contra **4,12 s** no chaveiro dedicado. Os 4,12 s são o diálogo — isto é, um
humano. Essa diferença *é* o endurecimento; o resto é contabilidade.

A migração de cada chave foi: copiar para o chaveiro dedicado com ACL vazia,
validar no `openssl` **antes** de gravar, reler de lá e conferir o SHA-256 contra
o que saiu do `login`, e só então apagar o item velho. Enquanto o item do `login`
existe ele é o que vale (o `login` vem primeiro na search list), então até o
último passo não há nada a desfazer.

⚠️ **A search list é preferência de usuário: não está no nix, não vem daqui, e um
wipe a perde.** O sintoma é cruel — o item some para o broker enquanto o arquivo
do chaveiro está intacto no disco. O `doctor` detecta e diz o comando; a receita é:

```sh
security list-keychains -d user -s ~/Library/Keychains/login.keychain-db \
  ~/Library/Keychains/av-broker.keychain-db
```

⚠️ **`add-generic-password` sem chaveiro posicional grava no `login`**, mesmo que
o item vivesse no dedicado — a busca varre a search list, a escrita não. Uma
rotação distraída moveria a chave de volta para o chaveiro fraco, com exit 0 e
releitura conferindo. Por isso `cmd_rotate` descobre o chaveiro com
`keychain_file()` em vez de supor, e registra `keychain_file` no log de auditoria.

Pendente por dependência de outra fase:
- `gcp.broker_sa_email` → rodar `gcp/setup-sa-broker.sh`. **Bloqueado: `gcloud`
  não está instalado** (medido 29/jul/2026) nem declarado em nenhum `.nix`.
- entrega do token à VM → **Fase 2** (ver "Pendências")

## Por que um arquivo só

`bin/av-broker` é um script Python monolítico, sem dependências fora da stdlib:
cada pacote de terceiros seria código de terceiros no caminho da chave, e um
arquivo único se audita de uma sentada.

⚠️ **A justificativa original deste parágrafo estava errada, corrigida em
29/jul/2026.** Ela dizia que o Automic Vault "atesta por hash de um caminho
(`av bless`)" e que quebrar em módulos deixaria os imports fora da atestação.
Medido: `av bless` **recusa este arquivo** — `av bless: script is not a valid
blessable file`. O AV não atesta um executável arbitrário; ver "Atestação pelo
AV" abaixo. **Hoje o broker não é atestado por nada.**

A chave privada **nunca toca o disco**: é passada ao `openssl` por pipe em
`/dev/fd/N`.

## Instalação

```sh
cp broker/config.example.json ~/.config/av-broker/config.json
chmod 600 ~/.config/av-broker/config.json
ln -s "$PWD/broker/bin/av-broker" ~/.local/bin/av-broker   # já está no sessionPath
av-broker doctor
```

## Atestação pelo AV — como funciona, e por que ainda não está ligada

Medido em 29/jul/2026 com `av` 2.3.0. **O trecho que este parágrafo substitui
mandava rodar `av bless "$HOME/.local/bin/av-broker"`, que não funciona.**

`av bless PATH` não abençoa um binário nem um script qualquer: ele abençoa um
script cujo **shebang é o próprio `av inject`** — o mesmo stub que os hardeners
do AV instalam (`AUTOMIC_VAULT_ENV_WRAPPER_STUB_V1`):

```sh
#!/usr/local/bin/av inject --allow-missing-keys +GCP_BROKER_KEY /usr/bin/env python3
```

Comprovado com um script de teste: com esse shebang ele roda e imprime
`automic vault: human approval required` → `approved`. Isto é, **sem bless
prompta a cada execução; com bless fica silencioso.** A atestação e o conforto
são a mesma coisa — não dá para ter um sem o outro, e é isso que torna o desenho
honesto.

Restrições medidas: o path não pode ser symlink nem estar sob `/private/tmp`
(`script path must be canonical`), e o script tem teto de 1 MiB (o broker tem
65 KB). Como `~/.local/bin/av-broker` é symlink para o repo, o bless teria de
apontar para o arquivo real.

**O que bloqueia hoje: `av save` exige `/dev/tty`.** Ele recusa stdin com
`failed to open /dev/tty: Device not configured (os error 6)`, então não existe
como canalizar a chave do Keychain para o AV por pipe — ela teria de ser
**colada por você num terminal**, passando por clipboard e scrollback. Expor uma
chave que hoje nunca é exibida, para melhorar a custódia dela, é um mau negócio.

**Quando ligar: na próxima rotação (Fase 4).** Lá existe uma chave nova que ainda
não está em lugar nenhum, e ela vai direto para o `av save` sem que a antiga
apareça. Só então `key_provider` vira `env:`, o shebang entra no arquivo do repo
e o `av bless` passa a valer.

⚠️ Não existe `av unbless`, e **toda edição no arquivo abençoado anula a bênção**.
O modo de falha é seguro e barulhento — volta a promptar — mas é custo
operacional real, e o `av-broker` ainda está em evolução.

O que entra no `av save` é o **PEM cru**, de preferência. Mas se o prompt dele
truncar multi-linha (incógnita não medida — ele exige `/dev/tty` e não se deixa
testar por pty), o plano B já está pronto: guarde `base64:<pem-numa-linha>` e o
`read_key()` desfaz o prefixo também em `env:`, com o mesmo contrato explícito
do `keychain:`. Hex, não — hex é um artefato do `security -w`, que não existe no
caminho do AV.

## Uso

```sh
# GCP impersonando a SA de baixo privilégio (leitura abre sessão de projeto após
# a 1ª aprovação; escrita prompta SEMPRE, mesmo com sessão viva)
av-broker gcp --target-sa av-agent@projeto.iam.gserviceaccount.com

# Salesforce por JWT Bearer (ADR §6.2) — use json, o instance_url vem nele
av-broker salesforce --emit json

# operação
av-broker session list
av-broker session revoke --all
av-broker log -n 20
av-broker doctor          # zero diálogos: checa presença das chaves, não conteúdo
av-broker doctor --deep   # lê e valida no openssl — um diálogo POR chave

# higiene contínua (Fase 4 — ver docs/runbook-fase4-rotacao.md)
av-broker rotate                                     # idade de cada credencial
av-broker rotate --target salesforce < nova.pem      # verifica antes de trocar
```

Não há mais `av-broker github` nem `av-broker review`: os dois saíram em
18/ago/2026 com o provedor. A revisão dos PATs se faz na UI do GitHub, em
Settings → Developer settings → Personal access tokens.

`--dry-run` roda política, classificação e log **sem** chamar a API — é como se
desenvolve antes da Fase 0. `--no-prompt` falha em vez de promptar (uso
não-interativo; a recusa vai para o log).

## A política (ADR §6.5)

| Classe | Como decide | Comportamento |
| --- | --- | --- |
| **read** | todo escopo termina em `.readonly` (GCP) / `read_only` no config (Salesforce) | Touch ID na 1ª vez; depois **silencioso** enquanto a sessão do projeto viver (teto 8 h) |
| **write** | qualquer `write`/`admin`, ou escopo GCP amplo como `cloud-platform` | **prompta sempre** — nunca silencioso, nunca cacheado |

**Salesforce é o caso em que o broker não consegue decidir.** O grant JWT Bearer
não aceita escopo na cunhagem (ADR §6.2) — o poder do token vem do permission set
do usuário de integração, que não aparece na resposta do `/token`. Default:
**write**, porque classificar como leitura o que não se sabe ler seria mentir. O
`"read_only": true` no config é uma afirmação sua de que verificou o permission
set; existe só no config, **nunca como flag**, para que um chamador comprometido
não possa rebaixar a própria classificação.

Detalhes que não são acidentais:

- **A sessão guarda a aprovação, não o token.** O token é re-cunhado a cada
  chamada, então não existe token em repouso no disco.
- **A sessão é presa ao contexto que deu sentido à aprovação** — não só ao
  provedor e ao projeto. São quatro amarras, cada uma nascida de um consentimento
  que não correspondia ao que aconteceu:

  | Amarra | Sem ela |
  | --- | --- |
  | `target` | aprovar `voce/dotfiles` silencia `outro/dotfiles` — nomes colidem entre donos |
  | `dry_run` | um ensaio aprovado autoriza cunhagem real (aconteceu em 29/jul/2026) |
  | `gate` | um `tty` — que não resiste a quem controla o stdio — herda a autoridade do diálogo |
  | `cred` | trocar de App/SA ou de origem da chave preserva o consentimento anterior |

  O `cred` é derivado da **config** (app_id/SA + `key_provider`), não do material
  da chave: ler a chave só para validar sessão dispararia o prompt do AV a cada
  cunhagem, que é o oposto do objetivo. Grants gravados antes dessas amarras não
  têm os campos e são recusados sozinhos.
- **Aprovar um write não abre sessão.** O próximo write prompta de novo; é o
  ponto do gate contra o "egress que parece legítimo".
- **O fallback sem biometria não é `[s/N]`.** Exige digitar uma palavra que muda
  a cada prompt — o equivalente prático do aviso polimórfico de Anderson et al.
  (CHI 2015), que mostrou queda de processamento visual já na 2ª exposição a um
  aviso idêntico.
- **O portão é escolhido por resistência, não por conveniência** — ver abaixo.

## Portões de aprovação

`policy.gate` aceita `auto` (default), `touchid`, `gui` ou `tty`; `auto`
resolve para o mais forte disponível. Override pontual: `AV_BROKER_GATE=tty`.

| Portão | Resiste a um chamador que controle o stdio? | Situação |
| --- | --- | --- |
| `touchid` | **sim** — exige presença física | indisponível nesta máquina |
| `gui` | **sim** — a palavra só existe no diálogo | **em uso** |
| `tty` | **não** | só para sessões sem GUI (SSH) |

**Esta máquina é um Mac mini M4 sem teclado biométrico** (`AppleBiometricSensor`:
0), e a decisão de 29/jul/2026 foi não comprar um. O portão é o **diálogo nativo
do macOS**: mostra repo, permissões, TTL e uma palavra que muda a cada prompt, e
exige digitá-la. `default button "Negar"` — Enter nega, o caminho reflexo é o
seguro. Expira em 120 s negando (falha fechada).

⚠️ **Por que o desafio de terminal não serve como portão principal.** Ele lê de
stdin e escreve em stdout, então **quem controla o stdio do broker lê a palavra e
a digita de volta**. Isso foi demonstrado em 29/jul/2026: um harness com pty
aprovou sozinho uma cunhagem de *escrita*. O diálogo do macOS fecha esse vetor —
a palavra nunca passa pelo stdio, e dirigir o diálogo por software exige
permissão de Acessibilidade (TCC), que o checklist recusa por princípio.
`av-broker doctor` marca o portão `tty` como fraco quando ele estiver ativo.

`bin/touchid-gate.swift` continua no repo e é compilado sob demanda (cache por
hash da fonte): se um Magic Keyboard com Touch ID for pareado, `auto` passa a
escolhê-lo sozinho, sem mudança de config. O `--probe` verifica disponibilidade
**sem** mostrar diálogo — é o que evita um aviso de falha a cada aprovação.

## Agente em memória — removido em 18/ago/2026

Havia aqui um agente que lia a chave privada do GitHub App **uma vez**, a mantinha
em RAM e servia cunhagens por um socket unix (`agent start|stop|status`,
`--lazy-key` sob launchd). Ele existia por uma medição: **28 senhas do Keychain
digitadas num dia** (02/ago/2026), depois que o `gh` do host passou a cunhar por
comando. `_agent_handle` conhecia uma única operação — `mint` de github.

Com o GitHub fora do broker não sobrou nada que ele resolvesse, e manter chave
privada retida em RAM sem benefício é só o custo: antes a chave existia em
memória por ~1 s por cunhagem, com o agente existia pela vida dele, e o Python
não permite zerá-la de forma confiável. GCP e Salesforce nunca passaram por ele
(1 cunhagem de GCP e 5 de Salesforce em cinco dias de log) e seguem pagando um
diálogo por cunhagem, como sempre pagaram.

O `launchd.user.agents.av-broker-agent` declarado em `configuration.nix` fica
órfão com esta remoção — retirá-lo é edição fora de `broker/`.

## Auditoria

JSONL append-only em `~/.local/state/av-broker/mints.jsonl` (0600) — o
substituto viável de um audit log próprio (o do GitHub é Enterprise-only, e o
alvo GitHub nem passa mais por aqui desde 18/ago/2026). Registra
cunhagens, **e também recusas** (`denied`, `no-prompt`): algo tentando cunhar
token de escrita não-interativamente é justamente o que se quer ver.

```sh
av-broker log -n 20
jq 'select(.classification=="write")' ~/.local/state/av-broker/mints.jsonl
```

## Pendências (dependem de outras fases)

**Transporte para a VM — Fase 2.** Hoje o token sai em stdout (`--emit
token|json`) e nunca é escrito em disco. A entrega por placeholder/vsock do
shuru entra como um novo modo em `emit()`; **nada mais do broker muda** — é a
tese do ADR §6.3 de que o transporte é camada substituível. Não fie o transporte
antes de o checklist adversarial (`research/egress.md` §4.4) aprovar o egress.

**`gcloud-admin` — fiado em 29/jul/2026.** `shell/gcloud-admin.zsh` é carregado
pelo `programs.zsh.initContent` do `home.nix`; vale a partir do próximo
`darwin-rebuild switch`.

## Riscos residuais

- **O broker não é atestado por nada, hoje.** Um processo rodando como `alex`
  pode editar `bin/av-broker` e a próxima cunhagem usa o código editado. O texto
  anterior aqui dizia que "quem sustenta a integridade é a atestação do AV sobre
  o broker" — **falso**, ver "Atestação pelo AV". Esta é a lacuna mais séria em
  aberto, e a Fase 4 é onde ela fecha.
- **O gate gráfico é controle de habituação, não de integridade.** Ele garante
  que a aprovação seja um ato deliberado, não que o código aprovado seja o que
  você escreveu. Um processo rodando como `alex` também pode adulterar o binário
  de Touch ID compilado em `~/.local/state`.
- **A ACL do Keychain protege o dado, não o metadado.** Um item criado com
  `-T ""` exige autorização para ler o valor (~4,7s de diálogo), mas responde à
  pergunta "existe?" em 0,02s sem prompt. É o que permite ao `doctor` ser barato,
  e também significa que a *existência* das suas credenciais não é segredo.
- **Aprovar um mint aprova tudo que o token faz na janela.** O escopo limita
  *qual* SA/org e *por quanto tempo*, não *o que* acontece dentro dele.
- **O GitHub saiu do modelo de segurança do broker em 18/ago/2026.** Os dois PATs
  fine-grained são de vida longa e não passam por portão nenhum: quem lê o
  Keychain (`github-pat`) ou o ambiente da VM (`github-pat-vm`) tem acesso pela
  validade inteira do token, sem consentimento por uso e sem linha no JSONL.
  Perda aceita explicitamente pelo dono do repo.
- **A classificação do GCP é por sufixo de escopo.** `cloud-platform` cai em
  write e prompta — conservador de propósito, mas um escopo customizado de
  leitura que não termine em `.readonly` também vai promptar.
- **A search list do Keychain é estado fora do nix.** O chaveiro dedicado só é
  encontrado porque ele está nela, e nada neste repositório garante isso. Ver
  "Chaveiro dedicado"; o `doctor` avisa, mas só depois de já ter quebrado.
- **Cunhagem de GCP e de Salesforce custa um diálogo de senha cada.** Sempre
  custou: o agente em memória nunca serviu essas duas (`_agent_handle` só
  conhecia `mint` de github) e saiu em 18/ago/2026. O volume torna isso tolerável
  — em cinco dias de log houve 1 cunhagem de GCP e 5 de Salesforce, contra 39 de
  GitHub num dia só. Se o volume mudar, o conserto NÃO é devolver as chaves ao
  `login`.
- **`shuru-vm.sh` passou a exigir sessão gráfica.** Ele lê o `claude-setup-token`
  para injetá-lo na VM, e agora essa leitura abre diálogo (~3s, medido). De `ssh`,
  `cron` ou launchd sem Aqua, ele falha — com mensagem própria, que não confunde
  "não autorizado" com "não custodiado".
