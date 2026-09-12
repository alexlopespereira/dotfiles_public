#!/bin/sh
# commit -> branch efemera -> PR -> squash-merge -> apaga a branch.
# Roda DENTRO da VM, sobre um clone local do guest. Uma invocacao, um PR.
#
#   shuru-pr.sh "feat(anuidade): calcula proporcional do primeiro ano"
#   shuru-pr.sh --no-wait-checks "fix(g2s): trata 429 do Salesforce"
#   shuru-pr.sh --dry-run "..."      # mostra o que faria, nao toca o remoto
#
# METODOLOGIA (decisao do Alex, 30/jul/2026): a VM trabalha num checkout da
# `main`, sem worktree. A branch nasce so na hora do PR e morre no merge. Quem
# confere o RESULTADO e o humano; o merge nao passa por revisao humana. Por isso
# os portoes deste script sao a unica coisa entre o agente e a `main` — o repo
# nao ajuda: medido em 30/jul/2026, `SEU-USUARIO/meu-projeto` e privado
# num plano free, entao `GET /rules/branches/main` responde 403 ("Upgrade to
# GitHub Pro") e `GET /branches/main` devolve `protected: false`. Nao existe
# branch protection, nao existe required check, e o `.github/CODEOWNERS` esta
# inerte (code-owner review so e exigivel ATRAVES de branch protection).
#
# SQUASH e a escolha certa e e a convencao medida: 592 commits de squash
# ("... (#N)") contra 26 merge commits nos 696 commits do repo, com os merges
# abandonados depois de jan/2026 e os ultimos 15 commits todos de squash. O
# proprio `.github/BRANCH_PROTECTION.md` pede "Require linear history" — que
# nunca foi aplicado, mas diz a intencao.
#
# COMO O TOKEN CHEGA AQUI (mudou em 18/ago/2026): por MOUNT, em /ghcred/token,
# read-only, criado pelo host so quando aquela sessao pediu GitHub. O valor la e
# um PAT fine-grained de vida longa, real e literal — o `github-pat-vm` do
# keychain do Mac (scripts/gh-pat.sh).
#
# O arranjo ANTERIOR era outro e vale registrar, porque o codigo abaixo ainda
# carrega marcas dele: o guest recebia um PLACEHOLDER em $GITHUB_TOKEN e o proxy
# do shuru trocava pelo valor real so no egress. Isso exigia que cada projeto
# declarasse `secrets.GITHUB_TOKEN` no shuru.json dele, e obrigava o host a
# pre-codificar o blob Basic (um base64 feito no guest destruiria o placeholder
# como substring). Nada disso e mais necessario: com valor real aqui dentro, o
# proprio guest codifica.
#
# O shuru.json do projeto ainda precisa, para esta tarefa:
#
#   "network": { "allow": [ ..., "github.com", "api.github.com" ] }
#
# `github.com` NAO esta no shuru.json do dotfiles de proposito, e nao deve virar
# default em projeto nenhum: rede para o GitHub e uma decisao daquela sessao.
set -eu

# ---------------------------------------------------------------- argumentos
ESPERAR_CHECKS=1
DRY_RUN=0
MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-wait-checks) ESPERAR_CHECKS=0; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -m)               MSG="${2:?-m exige a mensagem}"; shift 2 ;;
    -h|--help)        sed -n '2,40p' "$0"; exit 0 ;;
    --)               shift; MSG="${1:-$MSG}"; break ;;
    -*)               echo "erro: opcao desconhecida: $1" >&2; exit 2 ;;
    *)                MSG="$1"; shift ;;
  esac
done

die() { printf '\033[31mERRO\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32mok\033[0m   %s\n' "$*"; }
passo() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

[ -n "$MSG" ] || die "uso: $0 \"tipo(escopo): assunto\""
# O claude-shuru ja exporta GITHUB_TOKEN a partir de /ghcred/token; esta leitura
# cobre o caminho direto (shuru-vm, console) em que nada exportou nada.
if [ -z "${GITHUB_TOKEN:-}" ] && [ -r /ghcred/token ]; then
  GITHUB_TOKEN=$(cat /ghcred/token)
  export GITHUB_TOKEN
fi
[ -n "${GITHUB_TOKEN:-}" ] || die "GITHUB_TOKEN ausente, e /ghcred/token nao existe.
     Suba a VM pedindo GitHub (claude-shuru --github, ou GITHUB_TOKEN no
     ambiente do shuru-vm). Sem ele nao ha push nem PR."
command -v python3 >/dev/null 2>&1 || die "python3 ausente no guest — a parte da API precisa dele"

ASSUNTO=$(printf '%s' "$MSG" | head -n1)
case "$ASSUNTO" in
  # Conventional Commits em portugues e o estilo do repo (feat(anuidade):,
  # chore(g2s):, ...). Aviso, nao recusa: nao e a mim que cabe reprovar a
  # mensagem que o humano escolheu.
  [a-z]*:*|[a-z]*\(*\):*) ;;
  *) printf '\033[33maviso\033[0m assunto fora de Conventional Commits: %s\n' "$ASSUNTO" >&2 ;;
esac
[ "${#ASSUNTO}" -le 72 ] || printf '\033[33maviso\033[0m assunto com %s chars (>72)\n' "${#ASSUNTO}" >&2

# ------------------------------------------------------------------ contexto
git rev-parse --git-dir >/dev/null 2>&1 || die "nao estou num repositorio git"
RAIZ=$(git rev-parse --show-toplevel); cd "$RAIZ"

# O `.git` de um worktree e um ARQUIVO com `gitdir: <caminho absoluto do host>`,
# que nao resolve dentro da VM. E um mount read-only do repo do host daria ao
# guest escrita em `.git/hooks` do HOST — execucao de codigo no seu proximo
# commit. Este script so opera em clone de verdade, local do guest.
[ -d "$RAIZ/.git" ] || die "'$RAIZ/.git' nao e diretorio: isto e um worktree ou um
     mount do host. Clone o repo dentro da VM antes (git clone /workspace ~/repo)."

# Um mount do repo do host TEM um .git de verdade, entao o teste acima passa e o
# perigo fica silencioso. Detectamos pelo SISTEMA DE ARQUIVOS, nao pelo caminho:
# medido em 30/jul/2026 dentro do guest, com `df --output=fstype`,
#
#   overlay   mount sem ':rw'  — a escrita vai para o upperdir e NAO chega ao
#                               host. Nao ha erro: o `git commit` "passa" e o
#                               trabalho evapora no fim do boot.
#   virtiofs  mount com ':rw'  — a escrita chega no host de verdade, .git/hooks
#                               incluso, o que e execucao de codigo na SUA
#                               maquina no proximo commit ou checkout.
#   ext4      disco do guest   — o unico lugar seguro.
#
# A versao anterior testava `case "$RAIZ" in /workspace*)`, o que so pegava o
# mount do shuru-vm.sh. O claude-shuru monta ESPELHADO (/Users/alex/Projects/...)
# e passava batido. `[ -w ]` tambem nao serve: no overlay tudo parece gravavel.
FS=$(df --output=fstype -- "$RAIZ" 2>/dev/null | tail -1 | tr -d ' ')
case "$FS" in
  overlay|overlayfs|virtiofs|9p|fuse*)
    die "'$RAIZ' esta num mount do host ($FS), nao no disco do guest.
     overlay = suas escritas somem no fim do boot; virtiofs = elas caem no .git
     do HOST. Clone local primeiro (nao usa rede):
       git clone '$RAIZ' /work && cd /work" ;;
esac

BASE=$(git symbolic-ref --quiet --short HEAD) || die "HEAD destacada; fique na main"
[ "$BASE" = "main" ] || die "voce esta em '$BASE'. A metodologia e trabalhar na main;
     a branch efemera quem cria e este script."

URL=$(git remote get-url origin 2>/dev/null) || die "sem remote 'origin'"
# Um clone feito a partir do mount tem origin=/workspace. Em vez de exigir um
# `git remote set-url` decorado — passo que se esquece e que falha tarde —
# herde o remoto de la: e o mesmo repositorio.
case "$URL" in
  /*) URL=$(git -C "$URL" remote get-url origin 2>/dev/null) \
        || die "origin aponta para um caminho local que nao tem remoto proprio" ;;
esac
SLUG=$(printf '%s' "$URL" | sed -e 's#^git@github.com:#/#' -e 's#^https://github.com/#/#' \
                                -e 's#\.git$##' -e 's#^/##')
case "$SLUG" in */*) ;; *) die "nao consegui derivar OWNER/REPO de: $URL" ;; esac
ok "repo $SLUG, base $BASE"

# Autenticacao do git sem tocar em argv (`ps`) e sem gravar credencial no
# .git/config: config por ambiente, valido so para este processo e seus filhos.
#
# O BLOB VEM PRONTO DO HOST, e isso nao e otimizacao — e o unico jeito de o
# segredo chegar ao GitHub. O proxy do shuru substitui o placeholder pelo valor
# real por TEXTO LITERAL no stream ja decifrado; se o guest codifica o token em
# base64 antes de manda-lo, o placeholder deixa de existir como substring e a
# troca nunca acontece. O GitHub entao recebe o placeholder cru e responde
# "Password authentication is not supported for Git operations."
#
# Medido de dentro da VM em 31/jul/2026, com controles: `Bearer $GITHUB_TOKEN`
# contra api.github.com da 200 (o token e valido e a troca funciona quando o
# valor vai literal), o MESMO token em `Basic base64(...)` da 401, e sem auth
# nenhuma da 404. Bearer nao serve para git-over-https no GitHub — so Basic —,
# entao a saida e o host pre-codificar e declarar o blob como segredo proprio.
if [ -n "${GITHUB_BASIC:-}" ]; then
  CAB=$GITHUB_BASIC
else
  # Fora da VM nao ha proxy nem placeholder: ali $GITHUB_TOKEN e o valor real e
  # codificar aqui e o correto.
  CAB=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')
fi
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.extraheader
export GIT_CONFIG_VALUE_0="Authorization: Basic $CAB"
unset CAB
# O remoto tem que ser HTTPS para o header valer: SSH ignoraria e pediria chave,
# e um caminho local faria o fetch e o push irem para /workspace em silencio.
#
# Compare com o valor CANONICO, nao com a forma. A versao anterior perguntava
# "$URL ja e https?" — mas $URL, quando o origin era local, ja tinha sido
# reescrito para a URL herdada do repo-pai, entao a comparacao dava "sim" e o
# remote real continuava apontando para /workspace. Falha tardia e silenciosa.
CANONICA="https://github.com/$SLUG.git"
if [ "$(git remote get-url origin)" != "$CANONICA" ]; then
  git remote set-url origin "$CANONICA"
  printf '     origin -> %s\n' "$CANONICA"
fi

passo "1/7 sincronia com origin/$BASE"
git fetch --quiet origin "$BASE"
LOCAL=$(git rev-parse HEAD); REMOTO=$(git rev-parse "origin/$BASE")
# Divergencia aqui vira conflito de merge la na frente, quando ja houver branch e
# PR abertos no remoto para limpar. Falhar agora custa menos.
if [ "$LOCAL" != "$REMOTO" ]; then
  git merge-base --is-ancestor "$LOCAL" "$REMOTO" \
    && die "sua main esta ATRAS de origin/$BASE. Rode: git pull --ff-only" \
    || die "sua main divergiu de origin/$BASE (commit local nao publicado).
     Este script publica o WORKING TREE, nao commits soltos. Resolva a mao."
fi
ok "main igual a origin/$BASE ($(git rev-parse --short HEAD))"

passo "2/7 o que ha para publicar"
git add -A
git diff --cached --quiet && die "nada a commitar — a arvore esta limpa"
ARQUIVOS=$(git diff --cached --name-only)
printf '%s\n' "$ARQUIVOS" | sed 's/^/     /'

passo "3/7 portoes"
# (a) O App do broker NAO tem a permissao `Workflows`. Um push que toque
#     .github/workflows/ e rejeitado pelo GitHub com uma mensagem obscura, DEPOIS
#     de a branch ja existir no remoto. Barrar aqui e mais barato — e mexer em CI
#     e mudanca que merece o seu olho, nao o de um agente.
if printf '%s\n' "$ARQUIVOS" | grep -q '^\.github/workflows/'; then
  git reset --quiet
  die "o diff toca .github/workflows/ — o App nao tem a permissao 'Workflows' e o
     push seria rejeitado. Mudanca de CI vai a mao. Arquivos:
$(printf '%s\n' "$ARQUIVOS" | grep '^\.github/workflows/' | sed 's/^/       /')"
fi

# (b) Varredura de segredo no diff EXATO que vai subir. A ordem importa: em
#     29/jul/2026 um push daqui saiu com um commit que eu nao tinha lido, porque
#     escaneei antes de outra sessao commitar. Escaneie o que voce empurra, no
#     momento em que empurra.
# ERE, nao BRE: com `grep -E` as chaves sao `{20,}`. Escapadas (`\{20,\}`) elas
# viram literais e o padrao deixa de casar com nada — um portao que so PARECE
# fechado e pior que portao nenhum.
PADROES='ghp_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
#     Capture ANTES do reset: `git reset` esvazia o index, e um `$(git diff
#     --cached ...)` dentro da mensagem do die avaliaria depois — o portao
#     barrava certo e mostrava uma lista vazia, que e a pior combinacao possivel
#     (o humano nao descobre O QUE vazou).
SUSPEITAS=$(git diff --cached -U0 | grep -n -E "$PADROES" | cut -c1-120 | sed 's/^/       /' || true)
if [ -n "$SUSPEITAS" ]; then
  git reset --quiet
  die "o diff parece conter SEGREDO. Nada foi enviado. Linhas suspeitas:
$SUSPEITAS"
fi
ok "sem workflows, sem padrao de segredo"

# ------------------------------------------------------------------- commit
# Identidade de agente, de proposito: um commit feito por uma VM deve parecer
# feito por uma VM. Se o guest ja tiver user.name/user.email configurados, eles
# ganham — a decisao continua sendo sua.
git config user.email >/dev/null 2>&1 || git config user.email "shuru-agent@users.noreply.github.com"
git config user.name  >/dev/null 2>&1 || git config user.name  "shuru-agent"

# Nome da branch: previsivel, sem colisao, e obviamente descartavel.
#
# `[^a-z0-9][^a-z0-9]*` e nao `[^a-z0-9]\+`: o `\+` e extensao do GNU sed e o sed
# do macOS o le como um MAIS LITERAL. Medido em 30/jul/2026: o assunto
# "chore(teste): valida o shuru-pr" produziu a branch
# `agente/chore(teste): valida o shuru-pr-064ae88` — com parenteses, dois-pontos
# e espacos, que o `git checkout -b` recusa. O script roda no guest (GNU) mas e
# testado no host (BSD); tem que funcionar nos dois.
SLUGIF=$(printf '%s' "$ASSUNTO" | tr 'A-Z' 'a-z' \
         | sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-*//' -e 's/-*$//' | cut -c1-40 \
         | sed -e 's/-*$//')
BRANCH="agente/${SLUGIF:-mudanca}-$(git rev-parse --short HEAD)"
# Cinto e suspensorio: se ainda assim sair um nome invalido, pare aqui — e nao
# no meio da operacao, com estado ja no remoto.
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 \
  || die "nome de branch invalido: '$BRANCH'"

if [ "$DRY_RUN" -eq 1 ]; then
  git reset --quiet
  printf '\n\033[33mdry-run\033[0m nada enviado. Faria:\n'
  printf '     branch  %s\n     PR      %s <- %s\n     merge   squash, depois apaga a branch\n' \
    "$BRANCH" "$BASE" "$BRANCH"
  exit 0
fi

passo "4/7 branch efemera + commit"
git checkout --quiet -b "$BRANCH"
printf '%s\n' "$MSG" | git commit --quiet --file=-
SHA=$(git rev-parse --short HEAD)
ok "$BRANCH @ $SHA"

# A partir daqui existe estado no REMOTO. Qualquer saida sem merge tem que
# limpar, senao a proxima rodada tropeca numa branch orfa com o mesmo nome.
limpar() {
  st=$?
  rm -f "${MSGFILE:-}" 2>/dev/null || true
  [ "$st" -eq 0 ] && return 0
  printf '\n\033[33mlimpando\033[0m saida com erro (%s) — desfazendo o que ficou no remoto\n' "$st" >&2
  git push --quiet --delete origin "$BRANCH" 2>/dev/null || true
  git checkout --quiet "$BASE" 2>/dev/null || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
  printf '\033[33m\033[0m seu trabalho continua no reflog: git checkout %s\n' "$SHA" >&2
}
trap limpar EXIT INT TERM

passo "5/7 push"
git push --quiet --set-upstream origin "$BRANCH"
ok "branch no remoto"

passo "6/7 PR e squash-merge"
# A mensagem vai por ARQUIVO, nao por argv nem por variavel de ambiente: ela pode
# ter varias linhas e aspas, e um heredoc `<<'PY'` nao interpola nada.
MSGFILE=$(mktemp); chmod 600 "$MSGFILE"
printf '%s\n' "$MSG" > "$MSGFILE"
export SHURU_PR_MSGFILE="$MSGFILE"
# Tudo o que fala com a API vai num python so: abrir o PR, esperar os checks e
# fazer o merge sao passos acoplados (o numero do PR e o titulo do squash vem do
# primeiro), e dividir em varias chamadas so multiplicaria o tratamento de erro.
# O token vem do ambiente — nunca por argv.
PR_NUM=$(python3 - "$SLUG" "$BRANCH" "$BASE" "$ESPERAR_CHECKS" <<'PY'
import json, os, ssl, sys, time, urllib.error, urllib.request

slug, branch, base, esperar = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
tok, api = os.environ["GITHUB_TOKEN"], "https://api.github.com/repos/" + slug

# CONTEXTO TLS: verificacao completa, MENOS a checagem estrita de extensoes.
#
# O proxy do shuru intercepta TLS — e assim que ele troca o placeholder pelo
# segredo — entao quem assina a cadeia aqui e a CA dele, nao a do GitHub. Essa
# CA nao carrega a extensao Authority Key Identifier, e o Python 3.13 passou a
# ligar VERIFY_X509_STRICT por padrao em create_default_context(), que rejeita
# exatamente isso. Medido de dentro da VM em 31/jul/2026: o passo 6/7 morria com
# "CERTIFICATE_VERIFY_FAILED - Missing Authority Key Identifier" enquanto o curl,
# que nao usa a flag, falava com o MESMO host com 200, e o push (git, passo 5/7)
# passava sem queixa.
#
# O que fica LIGADO: cadeia de confianca e hostname (check_hostname). O que sai
# e so a exigencia de extensoes bem-formadas — uma propriedade do certificado do
# proxy local que somos nos mesmos, nao um sinal sobre o outro lado. Nao ha
# CERT_NONE aqui, e nao deve haver: isso aceitaria qualquer certificado.
CTX = ssl.create_default_context()
CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT

def chamar(metodo, caminho, corpo=None):
    dados = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(api + caminho, data=dados, method=metodo, headers={
        "Authorization": "Bearer " + tok,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, context=CTX) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:    return e.code, json.loads(e.read().decode())
        except Exception: return e.code, {}

def morrer(msg):
    print("ERRO " + msg, file=sys.stderr); sys.exit(1)

msg = open(os.environ["SHURU_PR_MSGFILE"], encoding="utf-8").read()
titulo, corpo = (msg.split("\n", 1) + [""])[:2]

st, pr = chamar("POST", "/pulls", {
    "title": titulo.strip(), "head": branch, "base": base,
    "body": (corpo.strip() + "\n\n" if corpo.strip() else "")
            + "Aberto e mesclado por `scripts/shuru-pr.sh` de dentro de uma microVM shuru.\n"
              "Revisao humana e do RESULTADO, nao do merge."})
if st != 201:
    morrer("POST /pulls -> %s %s" % (st, pr.get("message", pr)))
num = pr["number"]
print("     PR #%d aberto" % num, file=sys.stderr)

# Checks. Nao ha required check nenhum configurado (o repo e privado num plano
# free — nao existe branch protection), entao o GitHub mesclaria com o CI
# vermelho sem reclamar. Este bloco e o unico portao de CI que existe.
if esperar:
    limite, inicio = 900, time.monotonic()
    while time.monotonic() - inicio < limite:
        st, cs = chamar("GET", "/commits/%s/check-runs" % pr["head"]["sha"])
        runs = cs.get("check_runs", []) if st == 200 else []
        if runs:
            pend = [c for c in runs if c["status"] != "completed"]
            ruim = [c for c in runs if c["conclusion"] in ("failure", "timed_out", "cancelled")]
            if ruim:
                morrer("CI vermelho, NAO mesclado: " + ", ".join(c["name"] for c in ruim)
                       + " -- veja " + pr["html_url"])
            if not pend:
                print("     %d check(s) verdes" % len(runs), file=sys.stderr); break
        elif time.monotonic() - inicio > 60:
            # Sessenta segundos sem nenhum check registrado: este diff nao
            # dispara CI. Esperar 15 min por algo que nao vem e so latencia.
            print("     nenhum check disparou para este diff", file=sys.stderr); break
        time.sleep(10)
    else:
        morrer("checks ainda pendentes depois de %ds, NAO mesclado: %s" % (limite, pr["html_url"]))

# `mergeable` e calculado de forma assincrona; null significa "ainda pensando".
for _ in range(30):
    st, atual = chamar("GET", "/pulls/%d" % num)
    if st == 200 and atual.get("mergeable") is not None:
        break
    time.sleep(2)
else:
    morrer("o GitHub nao decidiu se o PR e mesclavel: " + pr["html_url"])
if not atual["mergeable"]:
    morrer("PR nao mesclavel (%s), NAO mesclado: %s"
           % (atual.get("mergeable_state"), pr["html_url"]))

# Titulo no formato que o repo usa ha 592 commits: "assunto (#N)".
st, res = chamar("PUT", "/pulls/%d/merge" % num, {
    "merge_method": "squash",
    "commit_title": "%s (#%d)" % (titulo.strip(), num),
    "commit_message": corpo.strip()})
if st != 200 or not res.get("merged"):
    morrer("merge recusado (%s): %s -- %s" % (st, res.get("message", res), pr["html_url"]))
print("     mesclado por squash: %s" % res["sha"][:7], file=sys.stderr)
print(num)
PY
) || die "a API do GitHub recusou. A branch remota foi apagada; nada foi mesclado."
ok "PR #$PR_NUM mesclado"

passo "7/7 finalizando a branch efemera"
trap - EXIT INT TERM
rm -f "$MSGFILE"
git checkout --quiet "$BASE"
git branch --quiet -D "$BRANCH"
# Em 30/jul/2026 voce ligou "Automatically delete head branches" no repo, entao
# na pratica isto quase sempre nao acha mais nada para apagar — dai o `|| true`.
# Fica mesmo assim: a opcao e config de repo, mudavel por qualquer um com acesso
# a Settings, e a limpeza nao pode depender de algo que o script nao controla.
git push --quiet --delete origin "$BRANCH" 2>/dev/null || true
# `--ff-only`: se isto falhar, alguem mexeu na main durante a operacao e eu
# prefiro parar barulhento a passar por cima com um reset --hard.
git pull --quiet --ff-only origin "$BASE"
ok "main em $(git rev-parse --short HEAD), branch $BRANCH removida (local e remoto)"

printf '\n\033[32mPR #%s mesclado na %s.\033[0m %s/pull/%s\n' \
  "$PR_NUM" "$BASE" "https://github.com/$SLUG" "$PR_NUM"
