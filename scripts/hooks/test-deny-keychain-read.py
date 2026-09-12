#!/usr/bin/env python3
"""Testes do hook deny-keychain-read. Rode: python3 scripts/hooks/test-*.py

Os casos NEGATIVOS importam mais que os positivos: um guard-rail que atrapalha o
trabalho legítimo é desligado na primeira semana, e aí não protege nada.
"""
import json
import os
import subprocess
import sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "deny-keychain-read.py")

BLOQUEAR = [
    ("o vazamento real de 02/ago",
     "security find-generic-password -s av-broker-github -w 2>&1 >/dev/null | head -3"),
    ("forma simples",
     "security find-generic-password -s claude-setup-token -w"),
    ("com chaveiro posicional",
     'security find-generic-password -s av-broker-gcp -w "$HOME/Library/Keychains/av-broker.keychain-db"'),
    ("no meio de um pipeline",
     "echo oi && security find-generic-password -s x -w | pbcopy"),
    ("senha de internet",
     "security find-internet-password -s github.com -w"),
    ("despejo do chaveiro inteiro",
     "security dump-keychain -d ~/Library/Keychains/login.keychain-db"),
    ("dentro de $( )",
     'TOKEN=$(security find-generic-password -s claude-setup-token -w)'),
    ("dentro de backticks",
     'T=`security find-generic-password -s x -w`'),
    ("caminho absoluto do binário",
     "/usr/bin/security find-generic-password -s x -w"),
    # --- o segundo vazamento de 02/ago: token do broker impresso na tela ---
    ("o vazamento real de 02/ago à noite",
     "av-broker salesforce --emit json 2>&1 | tail -25"),
    ("emit solto, sem nada",
     "av-broker salesforce --emit json"),
    ("emit canalizado para outro comando",
     "av-broker gcp --target-sa x@y.iam --emit token | head -1"),
    ("emit pelo caminho do repo",
     "./broker/bin/av-broker gcp --target-sa x@y.iam --emit token"),
    # --- PAT de vida longa (18/ago/2026): o wrapper que o padrao do
    #     `security` nao alcanca, porque o hook le a string do comando ---
    ("leitura direta do PAT do Mac",
     "gh-pat get host"),
    ("leitura do PAT que vai para a VM",
     "gh-pat get vm"),
    ("capturado em $( ) — aqui NAO ha excecao: o valor e o produto",
     'T=$(gh-pat get host)'),
    ("pelo caminho do repo",
     "./scripts/gh-pat.sh get vm"),
]

PERMITIR = [
    ("metadado — é o que o doctor usa",
     "security find-generic-password -s av-broker-gcp"),
    ("metadado com chaveiro",
     "security find-generic-password -s av-broker-gcp ~/Library/Keychains/av-broker.keychain-db"),
    ("dump sem -d (foi como achei o item órfão)",
     "security dump-keychain ~/Library/Keychains/login.keychain-db | grep av-broker"),
    ("lista de chaveiros",
     "security list-keychains -d user"),
    ("Python capturando em memória — o caminho CERTO",
     'python3 -c \'import subprocess; p=subprocess.run(["security","find-generic-password","-s","x","-w",KC],capture_output=True)\''),
    ("heredoc Python, como a migração inteira foi feita",
     'python3 - <<PY\nimport subprocess\np = subprocess.run(["security", "find-generic-password", "-s", S, "-w", KC], capture_output=True)\nPY'),
    ("grep pela string, não execução",
     "grep -rn 'find-generic-password' scripts/"),
    ("escotilha explícita",
     "AV_GUARD_OK=1 security find-generic-password -s x -w"),
    ("delete não imprime nada",
     "security delete-generic-password -s x ~/Library/Keychains/login.keychain-db"),
    ("outro comando com -w qualquer",
     "grep -w padrao arquivo.txt"),
    # --- os fluxos LEGÍTIMOS do --emit: quebrá-los quebra gh e shuru.json ---
    ("captura em $( ) — fluxo documentado do broker",
     'TOKEN="$(av-broker gcp --target-sa x@y.iam --emit token)"'),
    ("captura em $( ) com pipe DENTRO da substituição",
     'V=$(av-broker salesforce --emit json | jq -r .access_token)'),
    ("captura em crases",
     "T=`av-broker salesforce --emit token`"),
    ("redireciona para arquivo",
     "av-broker salesforce --emit json > /caminho/seguro.json"),
    ("descarta e lê o log — o jeito certo de TESTAR a cunhagem",
     "av-broker salesforce --emit json >/dev/null && av-broker log --tail 1"),
    ("append para arquivo",
     "av-broker gcp --target-sa x@y.iam --emit token >> /tmp/t"),
    ("av-broker sem --emit não imprime segredo",
     "av-broker doctor && av-broker log --tail 5"),
    ("gh-pat check só diz presente/ausente, nunca o valor",
     "gh-pat check"),
    ("gh-pat set LÊ do stdin, não imprime",
     "gh-pat set host"),
    ("o gh normal não é o helper",
     "gh pr list --limit 5"),
    ("escotilha explícita no emit",
     "AV_GUARD_OK=1 av-broker salesforce --emit json | tail -25"),
]


def roda(comando):
    p = subprocess.run([sys.executable, HOOK],
                       input=json.dumps({"tool_name": "Bash",
                                         "tool_input": {"command": comando}}).encode(),
                       capture_output=True)
    return p.returncode, p.stderr.decode()


falhas = 0
print("=== deve BLOQUEAR ===")
for nome, cmd in BLOQUEAR:
    rc, _ = roda(cmd)
    ok = rc == 2
    falhas += not ok
    print("  %s %s" % ("ok " if ok else "FALHOU", nome))

print("=== deve PERMITIR ===")
for nome, cmd in PERMITIR:
    rc, err = roda(cmd)
    ok = rc == 0
    falhas += not ok
    print("  %s %s%s" % ("ok " if ok else "FALHOU", nome,
                         "" if ok else "  <- bloqueou indevidamente"))

print("=== falha ABERTO com entrada torta ===")
for nome, entrada in (("json inválido", b"nao e json"), ("vazio", b""),
                      ("sem tool_input", b'{"tool_name":"Bash"}')):
    p = subprocess.run([sys.executable, HOOK], input=entrada, capture_output=True)
    ok = p.returncode == 0
    falhas += not ok
    print("  %s %s" % ("ok " if ok else "FALHOU", nome))

print("\n%s" % ("TODOS PASSARAM" if not falhas else "%d FALHA(S)" % falhas))
sys.exit(1 if falhas else 0)
