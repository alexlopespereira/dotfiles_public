#!/usr/bin/env python3
"""denials-by-command.py - de que exatamente as negacoes reclamam.

Por que este script existe: cc_audit.py conta negacoes e classifica em
permission-rule / user-rejected / automode-blocked, mas NAO guarda qual tool
call foi negada. Sem o comando, nao da para escrever uma allowlist com
evidencia - so por palpite. Este script casa cada tool_result negado com o
tool_use de mesmo id e imprime familia, projeto e comando.

Uso:
    python3 denials-by-command.py [--since DIAS] [--project SUBSTRING]
                                  [--include-firstmate] [--json]

Sem --since, varre o corpus inteiro. O default EXCLUI qualquer projeto cujo
caminho contenha "firstmate": depois do desligamento essas sessoes viram ruido
historico e mante-las infla a taxa de negacao do periodo "antes".
"""
import argparse, collections, datetime as dt, json, pathlib, re, sys

CLASSES = [
    ("permission-rule", re.compile(
        r"(permissionDecision.{0,10}deny|<tool_use_error>Blocked:"
        r"|PreToolUse:.{0,40}hook error|PostToolUse:.{0,40}hook error)", re.I)),
    ("automode-blocked", re.compile(
        r"(denied by the Claude Code auto mode classifier|Blocked by classifier)", re.I)),
    ("user-rejected", re.compile(
        r"(The user doesn't want to proceed|user rejected|tool use was rejected"
        r"|user doesn't want to take this action)", re.I)),
]


def familia(nome, cmd):
    if nome == "AskUserQuestion":
        return "AskUserQuestion"
    if cmd.startswith("sleep "):
        return "sleep-foreground"
    if cmd.startswith("cd /private/tmp/claude-501"):
        return "cd-scratchpad"
    if "@salesforce/cli" in cmd:
        return "salesforce-cli"
    if cmd.startswith("cd "):
        return "cd-outro"
    return (cmd.split() or ["(sem comando)"])[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", type=int, default=None, help="so os ultimos N dias")
    ap.add_argument("--project", default=None, help="filtra por substring do projeto")
    ap.add_argument("--include-firstmate", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--roots", default=str(pathlib.Path.home() / ".claude" / "projects"))
    a = ap.parse_args()

    corte = None
    if a.since:
        corte = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=a.since)

    linhas = []
    for f in pathlib.Path(a.roots).rglob("*.jsonl"):
        proj = f.parent.name
        if not a.include_firstmate and "firstmate" in proj:
            continue
        if a.project and a.project not in proj:
            continue
        usos = {}
        try:
            conteudo = f.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for linha in conteudo:
            if '"tool_use"' not in linha and '"tool_result"' not in linha:
                continue
            try:
                r = json.loads(linha)
            except ValueError:
                continue
            if corte:
                ts = r.get("timestamp")
                if ts:
                    try:
                        if dt.datetime.fromisoformat(ts.replace("Z", "+00:00")) < corte:
                            continue
                    except ValueError:
                        pass
            for blk in (r.get("message") or {}).get("content") or []:
                if not isinstance(blk, dict):
                    continue
                if blk.get("type") == "tool_use":
                    inp = blk.get("input") or {}
                    cmd = inp.get("command") or inp.get("file_path") or inp.get("url") or ""
                    usos[blk.get("id")] = (blk.get("name") or "?", str(cmd))
                elif blk.get("type") == "tool_result":
                    txt = json.dumps(blk.get("content"))[:4000]
                    for classe, rx in CLASSES:
                        if rx.search(txt):
                            nome, cmd = usos.get(blk.get("tool_use_id"), ("?", ""))
                            linhas.append({
                                "projeto": proj, "classe": classe, "tool": nome,
                                "familia": familia(nome, cmd), "comando": cmd[:200],
                                "quando": r.get("timestamp"),
                            })
                            break

    if a.json:
        json.dump(linhas, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return

    print(f"negacoes recuperadas: {len(linhas)}"
          f"{'' if a.include_firstmate else '  (excluindo projetos firstmate)'}")
    if not linhas:
        return
    print("\n== por classe x familia ==")
    c = collections.Counter((x["classe"], x["familia"]) for x in linhas)
    for (cl, fa), n in c.most_common():
        print(f"  {n:3d}  {cl:18s} {fa}")
    print("\n== por projeto ==")
    for p, n in collections.Counter(x["projeto"] for x in linhas).most_common():
        print(f"  {n:3d}  {p}")
    print("\n== comandos mais negados (candidatos a allowlist) ==")
    for (p, cmd), n in collections.Counter(
            (x["projeto"], x["comando"][:90]) for x in linhas).most_common(20):
        print(f"  {n:3d}  {p[:34]:34s} {cmd}")


if __name__ == "__main__":
    main()
