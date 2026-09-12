require "nvchad.options"

local o = vim.o

o.relativenumber = true
o.cursorlineopt = "both"
o.scrolloff = 8
o.confirm = true -- pergunta em vez de recusar quando ha buffer nao salvo

-- Secao 7 do nvim/README.md (shell e terminal embutido): DELIBERADAMENTE VAZIA
-- nesta maquina. O problema que ela descreve — caminho do interpretador com
-- espaco, guardado entre aspas, que serve para executar comando mas nao para
-- gerar processo — e do Windows com Git Bash. Aqui 'shell' herda o $SHELL do
-- WezTerm (/etc/profiles/per-user/alex/bin/zsh, sem espaco) e as duas coisas
-- que a secao exige ao mesmo tempo ja funcionam: :! devolve saida E o terminal
-- embutido abre. Fixar 'shell' aqui so trocaria o zsh do usuario por sh no
-- terminal embutido, sem resolver problema nenhum. Se um dia isto mudar, troque
-- o CONJUNTO de opcoes (shellcmdflag, shellredir, shellpipe, shellquote,
-- shellxquote) junto — mexer so em 'shell' quebra :! em silencio, devolvendo
-- vazio em vez de erro.
