#!/usr/bin/env python3
"""Testes do ensure-keychain-search-list.sh. Rode: python3 scripts/test-*.py

O `security` REAL nunca e chamado aqui: `AV_SECURITY` aponta para um stub que so
registra os argumentos. `list-keychains -d user -s` de verdade trocaria a search
list da maquina, e um erro no teste custaria Wi-Fi e Safari.

Os dois casos que mais importam sao regressoes de defeitos medidos em
11/ago/2026, ambos escondidos porque o PATH do shell interativo tem /usr/bin e o
da ativacao do home-manager nao:
  1. sem /usr/bin no PATH, `security` nao era encontrado e o script saia 0 —
     a garantia nunca rodava, em silencio;
  2. com a leitura da lista falhando, o script montava um `-s` VAZIO, que
     deixaria so o chaveiro do broker na lista e derrubaria o login.keychain.
"""
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(AQUI, "ensure-keychain-search-list.sh")

LOGIN = "/Users/fulano/Library/Keychains/login.keychain-db"
SISTEMA = "/Users/fulano/Library/Keychains/outro com espaco.keychain-db"

# PATH da ativacao do home-manager: tem coreutils, nao tem /usr/bin.
def path_sem_usr_bin():
    for raiz in ("/nix/store",):
        if not os.path.isdir(raiz):
            continue
        for nome in sorted(os.listdir(raiz)):
            if "coreutils" in nome and os.path.isdir(os.path.join(raiz, nome, "bin")):
                return os.path.join(raiz, nome, "bin")
    return os.path.join(tempfile.gettempdir(), "nao-existe-de-proposito")


PATH_ATIVACAO = path_sem_usr_bin()


def stub(dirpath, rc=0):
    """Escreve um `security` falso que loga os argumentos e imprime $SAIDA."""
    caminho = os.path.join(dirpath, "security-stub")
    log = os.path.join(dirpath, "chamadas.log")
    with open(caminho, "w") as f:
        f.write('#!/bin/sh\n'
                'printf "%s\\n" "$*" >> "' + log + '"\n'
                'case "$*" in *" -s "*) exit 0 ;; esac\n'
                'printf %s "$SAIDA"\n'
                'exit ' + str(rc) + '\n')
    os.chmod(caminho, 0o755)
    return caminho, log


def roda(saida="", rc=0, keychain=None, args=(), env_extra=None, path=None):
    """Roda o script com stub. Devolve (returncode, stdout+stderr, chamadas)."""
    with tempfile.TemporaryDirectory() as d:
        sec, log = stub(d, rc=rc)
        kc = keychain
        if kc is None:
            kc = os.path.join(d, "av-broker.keychain-db")
            open(kc, "w").close()
        env = {
            "HOME": d,
            "PATH": PATH_ATIVACAO if path is None else path,
            "AV_SECURITY": sec,
            "AV_KEYCHAIN": kc,
            "SAIDA": saida,
        }
        env.update(env_extra or {})
        p = subprocess.run(["/bin/sh", SCRIPT] + list(args),
                           env=env, capture_output=True)
        chamadas = []
        if os.path.exists(log):
            with open(log) as f:
                chamadas = [l.rstrip("\n") for l in f if l.strip()]
        return p.returncode, (p.stdout + p.stderr).decode(), chamadas, kc


def escreveu(chamadas):
    return any(" -s " in c or c.endswith(" -s") for c in chamadas)


falhas = 0


def checa(nome, cond, detalhe=""):
    global falhas
    falhas += not cond
    print("  %s %s%s" % ("ok " if cond else "FALHOU", nome,
                         "" if cond else "  <- " + detalhe))


print("=== defeito 1: PATH sem /usr/bin ===")
rc, out, chamadas, kc = roda(saida="    \"%s\"\n    \"%s\"\n" % (LOGIN, SISTEMA))
checa("acha o security mesmo assim", "command not found" not in out, out.strip())
checa("chamou a leitura da lista",
      any("list-keychains -d user" in c for c in chamadas), repr(chamadas))
checa("escreveu a lista nova, com o chaveiro do broker no fim",
      chamadas and chamadas[-1] == "list-keychains -d user -s %s %s %s"
      % (LOGIN, SISTEMA, kc), repr(chamadas))
checa("preservou o login.keychain",
      chamadas and LOGIN in chamadas[-1], repr(chamadas))
checa("saiu 0", rc == 0, "rc=%d" % rc)

print("=== defeito 2: leitura vazia NAO pode virar escrita ===")
rc, out, chamadas, _ = roda(saida="")
checa("nao chamou a escrita", not escreveu(chamadas), repr(chamadas))
checa("saiu != 0", rc != 0, "rc=%d" % rc)
checa("avisou alto", "ERRO" in out, out.strip())

print("=== leitura so com linhas em branco tambem e vazia ===")
rc, out, chamadas, _ = roda(saida="\n   \n\"\"\n")
checa("nao chamou a escrita", not escreveu(chamadas), repr(chamadas))
checa("saiu != 0", rc != 0, "rc=%d" % rc)

print("=== leitura falhando (exit != 0) ===")
rc, out, chamadas, _ = roda(saida="%s\n" % LOGIN, rc=3)
checa("nao chamou a escrita", not escreveu(chamadas), repr(chamadas))
checa("saiu != 0", rc != 0, "rc=%d" % rc)
checa("avisou alto", "ERRO" in out, out.strip())

print("=== idempotente: chaveiro ja na lista ===")
with tempfile.TemporaryDirectory() as d:
    kc = os.path.join(d, "av-broker.keychain-db")
    open(kc, "w").close()
    rc, out, chamadas, _ = roda(
        saida="    \"%s\"\n    \"%s\"\n" % (LOGIN, kc), keychain=kc)
    checa("nao chamou a escrita", not escreveu(chamadas), repr(chamadas))
    checa("saiu 0", rc == 0, "rc=%d" % rc)
    checa("disse que ja estava", "ja esta na lista" in out, out.strip())

print("=== --dry-run nao escreve ===")
rc, out, chamadas, kc = roda(saida="\"%s\"\n" % LOGIN, args=["--dry-run"])
checa("nao chamou a escrita", not escreveu(chamadas), repr(chamadas))
checa("saiu 0", rc == 0, "rc=%d" % rc)
checa("mostrou a lista atual no comando previsto",
      LOGIN in out and kc in out, out.strip())

print("=== --dry-run com leitura vazia tambem recusa ===")
rc, out, chamadas, _ = roda(saida="", args=["--dry-run"])
checa("saiu != 0", rc != 0, "rc=%d" % rc)
checa("nao imprimiu um -s vazio", " -s  " not in out, out.strip())

print("=== chaveiro ausente ===")
with tempfile.TemporaryDirectory() as d:
    ausente = os.path.join(d, "nao-existe.keychain-db")
    rc, out, chamadas, _ = roda(saida="%s\n" % LOGIN, keychain=ausente)
    checa("saiu 0", rc == 0, "rc=%d" % rc)
    checa("avisou", "nao existe" in out and "PULADO" in out, out.strip())
    checa("nem chamou o security", not chamadas, repr(chamadas))

print("=== security ausente ===")
with tempfile.TemporaryDirectory() as d:
    kc = os.path.join(d, "av-broker.keychain-db")
    open(kc, "w").close()
    p = subprocess.run(["/bin/sh", SCRIPT],
                       env={"HOME": d, "PATH": PATH_ATIVACAO,
                            "AV_SECURITY": os.path.join(d, "sem-security"),
                            "AV_KEYCHAIN": kc},
                       capture_output=True)
    saida = (p.stdout + p.stderr).decode()
    checa("saiu 0, sem quebrar a ativacao", p.returncode == 0,
          "rc=%d %s" % (p.returncode, saida.strip()))
    checa("avisou", "PULADO" in saida, saida.strip())

print("\n%s" % ("TODOS PASSARAM" if not falhas else "%d FALHA(S)" % falhas))
sys.exit(1 if falhas else 0)
