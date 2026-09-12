#!/bin/sh
# Cola de atalhos do Neovim (config NvChad + acrescimos), da sessao de
# 09-10/set/2026. Alem de consulta, serve de especificacao: e a lista que a
# secao 8 do README manda conferir contra o editor.
#
# Uso:
#   nvim-atalhos.sh              tudo
#   nvim-atalhos.sh telescope    so o que casar com "telescope"
#   nvim-atalhos.sh git          idem, para qualquer termo
#
# O filtro casa tanto no nome da secao quanto na linha, sem diferenciar
# maiusculas, entao "buscar" traz as secoes de busca inteiras.
#
# POSIX sh de proposito: o mesmo arquivo roda no zsh do macOS, no bash do
# Linux e no Git Bash do Windows.
set -eu

# Cor so quando faz sentido: sem cor se a saida for cano/arquivo, se o
# terminal nao souber, ou se NO_COLOR estiver setado (https://no-color.org).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_SEC=$(printf '\033[1;33m')   # secao
    C_KEY=$(printf '\033[36m')     # tecla
    C_DIM=$(printf '\033[2m')      # nota
    C_OFF=$(printf '\033[0m')
else
    C_SEC=''; C_KEY=''; C_DIM=''; C_OFF=''
fi

FILTRO="${1:-}"

# Formato: linha iniciada por '#' abre secao; demais sao  tecla|descricao.
# A tecla lider e a BARRA DE ESPACO (escrita <leader>).
atalhos() {
    cat <<'EOF'
#Telescope - buscar ARQUIVO PELO NOME
<C-p>|busca arquivo por nome (fuzzy: "usrctl" acha user_controller.rb)
<leader>ff|mesma coisa, pela tecla lider
<leader>fa|inclui arquivos ocultos e ignorados pelo git
<leader>gf|so arquivos versionados no git (pula node_modules, build)
<leader><leader>|arquivos recentes - em qual eu estava mexendo?
#Telescope - buscar PELO CONTEUDO
<leader>fg|busca texto dentro dos arquivos (grep)
<leader>fw|identico, atalho nativo do NvChad
<leader>fW|busca a palavra sob o cursor, sem digitar nada
<leader>fW|em modo visual: busca o trecho selecionado
<leader>fz|busca dentro do arquivo atual
#Telescope - DENTRO do buscador (e aqui que a maioria trava)
<C-n> <C-p>|desce e sobe na lista
<CR>|abre o resultado
<C-v> <C-x>|abre em split vertical / horizontal
<C-t>|abre em nova aba
<C-u> <C-d>|rola a PREVIA (nao a lista)
<Tab>|marca varios arquivos
<C-q>|joga TODOS os resultados na quickfix - ouro para refactor
<Esc>|modo normal dentro do buscador (dai "q" fecha)
<C-/>|lista todos os atalhos do buscador - decore so este
#Telescope - o resto que vale a pena
<leader>fr|RETOMA a ultima busca, com o texto que voce digitou
<leader>fb|lista de buffers abertos
<leader>fo|arquivos recentes
<leader>fd|erros e avisos do projeto
<leader>fk|lista de atalhos
<leader>fc|lista de comandos
<leader>fs|simbolos do arquivo (funcoes, classes)
<leader>fS|simbolos do projeto inteiro
<leader>fh|paginas de ajuda
#Arquivos e navegacao
<C-n>|abre/fecha a arvore de arquivos
<leader>e|foca a arvore
-|abre o diretorio como buffer editavel (renomeia editando a linha, :w aplica)
#Buffers e janelas
<Tab> <S-Tab>|proximo / anterior buffer
<leader>x|fecha o buffer
<leader>b|buffer novo
<C-h> <C-j> <C-k> <C-l>|move entre as janelas
<leader>v|terminal em split vertical
<leader>h|terminal em split horizontal
<A-i>|terminal flutuante (liga/desliga)
<C-x>|sai do modo terminal (volta ao normal)
#Codigo (LSP)
gd|vai para a definicao
gD|vai para a declaracao
K|documentacao sob o cursor
<leader>ca|acoes de codigo (corrigir import, extrair variavel...)
<leader>ra|renomeia o simbolo em todo o projeto
<leader>fR|referencias do simbolo, no telescope
<leader>D|vai para a definicao de tipo
<leader>ds|erros do arquivo numa lista
<leader>fm|formata o arquivo
<leader>/|comenta / descomenta (funciona em modo visual)
#Git
<leader>gs|status do git dentro do editor
<leader>gB|blame do arquivo
<leader>gp|previa da alteracao sob o cursor
<leader>gb|blame da linha atual (liga/desliga)
]c [c|proxima / anterior alteracao
<leader>cm|navega pelos commits
<leader>gt|status do git no telescope
#Testes
<leader>tn|roda o teste sob o cursor
<leader>tf|roda os testes do arquivo
<leader>ts|roda a suite inteira
<leader>tl|repete o ultimo teste
<leader>tv|vai para o ultimo arquivo de teste
#Geral
jk|sai do modo insert (alternativa ao Esc)
;|entra no modo de comando (sem apertar Shift)
<C-s>|salva
<Esc>|limpa o destaque da busca
<leader>th|troca o tema
<leader>ch|cola de atalhos embutida do NvChad
<leader>wK|lista todos os mapeamentos
EOF
}

atalhos | awk \
    -v filtro="$FILTRO" \
    -v c_sec="$C_SEC" -v c_key="$C_KEY" -v c_dim="$C_DIM" -v c_off="$C_OFF" '
# Escapa metacaractere para o filtro poder ser "<C-p>" ou "<C-/>" sem virar
# regex. Regex dinamica (string) em vez de literal /.../ de proposito: assim a
# barra entra na classe sem precisar de escape, que awk BSD nem sempre aceita.
function esc(s) {
    gsub("[][(){}.*+?^$\\\\|/-]", "\\\\&", s)
    return s
}

# Casa por PALAVRA, nao por pedaco: senao "git" casa com "digitar".
function casa_palavra(txt, padrao) {
    return match(tolower(txt), "(^|[^a-z0-9])" padrao "([^a-z0-9]|$)") > 0
}

BEGIN {
    f = tolower(filtro)
    f_esc = esc(f)
    n = 0
}
{
    if (substr($0, 1, 1) == "#") { secao = substr($0, 2); next }

    pos = index($0, "|")
    tecla = substr($0, 1, pos - 1)
    desc  = substr($0, pos + 1)

    # casa na linha (por palavra) ou no nome da secao (por pedaco, para
    # "telescope" trazer a secao inteira)
    if (f != "" && !casa_palavra($0, f_esc) && index(tolower(secao), f) == 0) next

    if (secao != ultima) {
        printf "\n%s%s%s\n", c_sec, secao, c_off
        ultima = secao
    }
    printf "  %s%-24s%s %s\n", c_key, tecla, c_off, desc
    n++
}
END {
    if (n == 0) {
        printf "Nenhum atalho casa com \"%s\".\n", filtro
        exit 1
    }
    printf "\n%s<leader> = BARRA DE ESPACO. Aperte espaco e espere: abre o menu.%s\n", c_dim, c_off
    printf "%sDentro do telescope, <C-/> lista o resto.%s\n\n", c_dim, c_off
}
'
