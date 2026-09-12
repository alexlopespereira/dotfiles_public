#!/usr/bin/env python3
"""Hook PreToolUse: barra comandos de shell cujo PRODUTO é um segredo em stdout.

Por que existe. Em 02/ago/2026 eu (o agente) rodei

    security find-generic-password -s av-broker-github -w 2>&1 >/dev/null | head -3

esperando que o `2>&1 >/dev/null` descartasse a chave. A ordem de redirecionamento
faz o oposto: `2>&1` copia o stdout ATUAL (o terminal) para o stderr, e só depois
o stdout vai para /dev/null — então a chave privada do GitHub App foi impressa
inteira no transcript. A chave teve de ser revogada e o App rotacionado.

O que este hook impede não é o descuido, é a CLASSE: um comando de shell cujo
propósito é imprimir um segredo, confiando em redirecionamento para contê-lo.
Redirecionamento é fácil de errar e o erro só aparece depois de o segredo já ter
saído. Ler segredo continua permitido pelo caminho certo — de dentro de um
processo que captura em memória (`subprocess.run(..., capture_output=True)`), que
é como toda a migração de 02/ago foi feita.

Três famílias desde 18/ago/2026: o `gh-pat get` entrou junto com a migração do
GitHub para PAT de vida longa. Entrou por uma razão que vale ler — o hook casa a
STRING do comando, não o que ele executa, e `gh-pat` é um wrapper do security.
Todo wrapper novo abre o mesmo furo até alguém listá-lo aqui.

Duas famílias históricas, dois critérios. Para o `security`, o critério é o COMANDO: `-w` e
`dump-keychain -d` imprimem valor, e não há uso legítimo disso via `Bash`. Para o
`av-broker --emit`, imprimir é o propósito — lá o critério é o DESTINO da saída
(ver o comentário de EMIT, mais abaixo).

Falha ABERTO de propósito: se o JSON não vier, ou vier torto, o comando passa.
Um hook que bloqueia tudo quando quebra é pior que hook nenhum — e o valor deste
aqui está em pegar o caso óbvio, não em ser uma fronteira de segurança. Quem tem
shell na sua conta não precisa da ferramenta `Bash` para ler o seu Keychain.
"""
import json
import re
import sys

# Comandos que IMPRIMEM o valor. A busca sem `-w` devolve só metadado e é
# inofensiva (é o que o `doctor` usa, e é justamente por isso que ele é barato).
PADROES = [
    # `security [flags] find-*-password ... -w`  → valor em stdout.
    # A fronteira depois do `-w` é `(?![\w-])`, não `\s|$`: com espaço-ou-fim, um
    # `TOKEN=$(security ... -w)` escapava, porque ali vem `)`. Cobre também
    # backtick e aspas. E `-what` continua não casando.
    (re.compile(r"(?<![\w.-])(?:[\w./~-]*/)?security\s+(?:-[a-zA-Z]+\s+)*"
                r"find-(?:generic|internet)-password\b[^|;&\n]*?\s-w(?![\w-])"),
     "imprime o VALOR do item (-w) no stdout"),
    # `security dump-keychain -d`  → despeja TODOS os segredos do chaveiro
    (re.compile(r"(?<![\w.-])(?:[\w./~-]*/)?security\s+(?:-[a-zA-Z]+\s+)*"
                r"dump-keychain\b[^|;&\n]*?\s-d(?![\w-])"),
     "despeja TODOS os segredos do chaveiro (-d)"),
    # `gh-pat get host|vm`  -> imprime o PAT do GitHub no stdout.
    #
    # Acrescentado em 18/ago/2026, junto com a migracao para PAT de vida longa.
    # E preciso ser honesto sobre o alcance disto: o `gh-pat` e um wrapper do
    # security, e o padrao acima NAO o pega — o hook le a string do comando,
    # nao o que ele executa. Sem esta entrada, `gh-pat get host` imprimiria o
    # token no transcript exatamente como a chave do App vazou em 02/ago/2026.
    # Qualquer wrapper novo abre o mesmo furo ate alguem lista-lo aqui: isto e
    # uma lista de nomes, nao uma fronteira.
    #
    # Vale para o comando DIGITADO. O gh-token.sh chama o helper de dentro de
    # um processo que captura em memoria, que e o caminho certo e segue livre.
    (re.compile(r"(?<![\w.-])(?:[\w./~-]*/)?gh-pat(?:\.sh)?\s+get(?![\w-])"),
     "imprime um PAT do GitHub (github-pat / github-pat-vm) no stdout"),
]

# Escotilha deliberada. Impossível de digitar por acidente, e deixa rastro no
# próprio comando — se um dia houver motivo de verdade, ele fica escrito ali.
ESCOTILHA = "AV_GUARD_OK=1"

MENSAGEM = """BLOQUEADO pelo hook deny-keychain-read: este comando %s.

Nunca construa um comando de shell cujo produto seja um segredo contando com
redirecionamento para contê-lo — a ordem de `2>&1 >/dev/null` faz o oposto do
que parece, e foi assim que a chave privada do GitHub App vazou para o
transcript em 02/ago/2026 (revogada e rotacionada no mesmo dia).

O caminho certo é ler de dentro de um processo que capture em memória:

    p = subprocess.run(["security", "find-generic-password", "-s", SERVICO,
                        "-w", CHAVEIRO], capture_output=True)
    valor = p.stdout.decode().strip()      # e imprima só o hash, nunca o valor

Se precisar MESMO do comando de shell, escreva %s no início dele."""

EMIT_MENSAGEM = """BLOQUEADO pelo hook deny-keychain-read: `av-broker --emit` com a
saída solta. Ela iria para o stdout da ferramenta, ou seja, para o transcript —
foi assim que um access token vivo da sandbox do Salesforce vazou na noite de
02/ago/2026 (revogado no mesmo minuto).

Emitir é o propósito do comando; o que importa é para ONDE. Capture:

    TOKEN="$(av-broker gcp --target-sa x@y.iam --emit token)"
    av-broker salesforce --emit json > /caminho/seguro.json

Se o objetivo é só TESTAR se a cunhagem funciona, descarte a saída e leia o log,
que registra o resultado sem tocar no segredo:

    av-broker salesforce --emit json >/dev/null && av-broker log --tail 1

Se precisar MESMO ver o valor na tela, escreva %s no início do comando."""


# `av-broker ... --emit` cunha uma credencial e a IMPRIME. Diferente dos padroes
# acima, aqui imprimir e o proposito legitimo do comando — o fluxo documentado e
#   TOKEN="$(av-broker gcp --target-sa x@y.iam --emit token)"
# e quebra-lo quebraria o gh do host e os shuru.json dos projetos. O que separa o
# uso certo do errado nao e o comando, e o DESTINO da saida:
#
#   capturada  ($(...), crase, > arquivo)  -> vai para quem vai usar. Seguro.
#   solta ou canalizada                    -> vai para o stdout da ferramenta, e
#                                             portanto para o transcript.
#
# Escrito na noite de 02/ago/2026, depois de eu mandar
# `av-broker salesforce --emit json` para `tail -25` e imprimir um access token
# vivo da sandbox no transcript — horas depois de criar este mesmo hook, no mesmo
# dia, para a familia de erro anterior (a chave do GitHub App). A regra
# que eu tinha aprendido ("nao construa comando cujo produto seja um segredo")
# nao cobria o caso em que o produto do comando E um segredo, por design.
EMIT = re.compile(r"(?<![\w.-])(?:[\w./~-]*/)?av-broker\s+[^|;&\n]*?--emit(?![\w-])")


def _capturada(comando, pos):
    """A saida do comando em `pos` vai para alguem que a usa, ou para a tela?

    Conta substituicoes ABERTAS antes da posicao. Nao e um parser de shell — e
    uma heuristica deliberada, que erra para o lado de BLOQUEAR: um falso
    positivo custa a escotilha, um falso negativo custa uma credencial.
    """
    antes = comando[:pos]
    if antes.count("$(") - antes.count(")") > 0:
        return True                            # dentro de $( ... )
    if antes.count("`") % 2 == 1:
        return True                            # dentro de crases
    # Redirecionamento no MESMO segmento: `> arquivo`, `>/dev/null`, `>> log`.
    segmento = re.split(r"[|;&\n]", comando[pos:])[0]
    if re.search(r">>?\s*\S", segmento):
        return True
    return False


def main():
    try:
        evento = json.load(sys.stdin)
        comando = (evento.get("tool_input") or {}).get("command") or ""
    except Exception:
        return 0                      # falha aberto: ver docstring
    if not isinstance(comando, str) or ESCOTILHA in comando:
        return 0
    for padrao, o_que in PADROES:
        if padrao.search(comando):
            sys.stderr.write(MENSAGEM % (o_que, ESCOTILHA) + "\n")
            return 2                  # 2 = bloqueia e mostra o stderr ao agente
    for m in EMIT.finditer(comando):
        if not _capturada(comando, m.start()):
            sys.stderr.write(EMIT_MENSAGEM % ESCOTILHA + "\n")
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
