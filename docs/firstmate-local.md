# Alterações locais no firstmate

O firstmate é **clonado**, não forkado: `git clone https://github.com/kunchenguid/firstmate ~/Projects/firstmate`
(passo 2 da seção de firstmate no `reinstall-checklist.md`). Nada dentro de
`~/Projects/firstmate` é versionado por este repositório, e o remote é de outra
pessoa — não dá para empurrar para lá.

Consequência: numa máquina nova, ou depois de um `git reset --hard origin/main`,
tudo que fizemos nele **some sem aviso**. Este arquivo existe para que isso seja
reconstruível em minutos em vez de redescoberto por arqueologia.

Duas categorias morrem de formas diferentes:

| O quê | Onde vive | Como morre |
|---|---|---|
| Commits sobre o `main` do upstream | histórico local | máquina nova, ou reset |
| Config ignorada pelo git | `data/projects.md` | máquina nova, ou `.gitignore` |

## Estado em 01/ago/2026

- **Base do upstream:** `daf6dce` (`fix: scope validation corrections by accepted behavior (#1281)`)
- **Commit local:** `02a738d` — `feat(brief): flag --vm para briefs no-mistakes dentro da microVM`
- **Patch:** `docs/firstmate-patches/0001-fm-brief-vm-flag.patch`

Não foi empurrado para o upstream **de propósito**, não por esquecimento: o repo
é `kunchenguid/firstmate`, o histórico é todo PR-merged, e virar PR lá é decisão
do capitão. Enquanto não for, o patch daqui é a única cópia fora do disco local.

## O que o patch faz

Adiciona a flag `--vm` ao `bin/fm-brief.sh`, no mesmo padrão de `--scout` e
`--herdr-lab`. Ela muda **exatamente duas coisas** num brief, e só quando é passada:

1. **Regra 7 (`$RULE7`).** A proibição de mexer no daemon do `no-mistakes`
   continua igual; o *motivo* é que muda. No host o daemon é uma instância
   compartilhada e reiniciá-lo mata os runs de outras lanes. Dentro da microVM
   ele é da própria VM — nasceu no boot do guest, morre com ela, e ninguém mais
   está nele. Reiniciar continua proibido (destrói o próprio run e o estado do
   gate), mas pela razão certa. Regra cuja razão declarada é falsa no contexto é
   regra que agente aprende a descontar.

2. **Linha final (`$NM_FINISH`).** Na VM o crewmate faz o merge da própria PR
   depois do CI verde (squash + apaga a branch, tolerando "already merged") e
   reporta `done: PR {url} merged`. No host ele para em CI-verde. A microVM é
   destruída no fim do run: uma PR parada em CI-verde não teria quem a
   mergeasse. Casa com a metodologia do capitão — ele confere o resultado, não
   o merge.

Sem `--vm`, o brief sai **byte a byte idêntico** ao que saía antes do patch.
Isso foi verificado, não presumido (ver abaixo).

## Como replicar numa máquina nova

Depois do passo 2 da seção de firstmate no `reinstall-checklist.md` (o clone):

```sh
cd ~/Projects/firstmate
git am ~/Projects/dotfiles/docs/firstmate-patches/*.patch
```

E reconstrua o registry ignorado, que o clone não traz:

```sh
mkdir -p data
cat > data/projects.md <<'EOF'
# Projects

Registry privado (gitignorado). Formato lido por `bin/fm-project-mode.sh`:

    - <nome> [<modo> [+yolo]] - <descrição> (added <data>)

Modos: `no-mistakes` (default quando o colchete é omitido), `direct-PR`,
`local-only`. Projeto ausente daqui cai em `no-mistakes off` **com aviso** — o
default é o portão forte, então um typo nunca derruba a validação em silêncio.

- meu-projeto [direct-PR] - ETL de um projeto proprio (added 2026-07-30)
EOF
```

`meu-projeto` está em `direct-PR` porque o `no-mistakes` dentro da VM ainda
não rodou de ponta a ponta. A troca para `[no-mistakes]` é a Fase 4 do
`plano-adocao-tokens.md` — não mude aqui antes de lá.

`state/` também é ignorado, mas é runtime (heartbeats, contadores, filas de
wake). Não replique: nasce sozinho e replicá-lo só carrega lixo de outra
máquina.

## Como verificar que o patch pegou sem estragar o host

O que importa não é a flag existir — é o caminho **sem** a flag continuar
intocado. Gere os dois e compare:

```sh
cd ~/Projects/firstmate
bin/fm-brief.sh zz-check <repo-em-modo-no-mistakes>
cp data/zz-check/brief.md /tmp/sem-vm.md
bin/fm-brief.sh zz-check-vm <repo-em-modo-no-mistakes> --vm
diff /tmp/sem-vm.md data/zz-check-vm/brief.md
rm -rf data/zz-check data/zz-check-vm /tmp/sem-vm.md
```

O `diff` deve mostrar **só** dois blocos: a regra 7 e a linha final. Qualquer
terceira diferença é regressão — o patch vazou para fora do escopo.

Na verificação original (01/ago/2026) o caminho do host foi comparado contra
`data/nm-cpf-1/brief.md`, gerado **antes** da mudança, e saiu idêntico.

## Se o `git am` der conflito

Significa que o upstream mexeu no heredoc do brief `ship` ou no texto da regra 7.
Não force. Reaplique à mão: o patch é pequeno e o que importa são os dois pontos
de extensão (`$RULE7` e `$NM_FINISH`) substituindo texto que hoje é literal.
Depois refaça a verificação acima — ela é o teste de regressão de verdade.

Se o upstream um dia adotar a flag, apague este arquivo e o patch. Documentação
de divergência que sobrevive à convergência vira mentira.
