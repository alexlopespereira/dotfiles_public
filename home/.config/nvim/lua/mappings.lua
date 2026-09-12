require "nvchad.mappings" -- PRESERVA os atalhos da base; os daqui vao ao lado

-- Fonte da verdade desta lista: nvim/nvim-atalhos.sh, no repo (comando
-- `nvim-atalhos`). Secao 8 do nvim/README.md.
--
-- Duas regras que valem para tudo aqui:
--  1. Onde um atalho popular de tutorial colide com o da base, o da base fica e
--     o novo entra como apelido (ex.: <leader>fg como apelido de <leader>fw).
--  2. Todo mapeamento leva `desc`. Sem descricao ele nao aparece no menu do
--     which-key (aquele que abre segurando a tecla lider) e some da vista.

local map = vim.keymap.set

-- Geral -------------------------------------------------------------------
map("n", ";", ":", { desc = "general enter command mode" })
map("i", "jk", "<ESC>", { desc = "general escape insert mode" })

-- Telescope: buscar ARQUIVO PELO NOME ---------------------------------------
map("n", "<C-p>", "<cmd>Telescope find_files<CR>", { desc = "telescope find files" })
map("n", "<leader>gf", "<cmd>Telescope git_files<CR>", { desc = "telescope git tracked files" })
map("n", "<leader><leader>", "<cmd>Telescope oldfiles<CR>", { desc = "telescope recent files" })

-- Telescope: buscar PELO CONTEUDO -------------------------------------------
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "telescope live grep (alias de fw)" })
map("n", "<leader>fW", "<cmd>Telescope grep_string<CR>", { desc = "telescope grep word under cursor" })
map("v", "<leader>fW", "<cmd>Telescope grep_string<CR>", { desc = "telescope grep selection" })

-- Telescope: o resto ---------------------------------------------------------
map("n", "<leader>fr", "<cmd>Telescope resume<CR>", { desc = "telescope resume last search" })
map("n", "<leader>fd", "<cmd>Telescope diagnostics<CR>", { desc = "telescope project diagnostics" })
map("n", "<leader>fk", "<cmd>Telescope keymaps<CR>", { desc = "telescope keymaps" })
map("n", "<leader>fc", "<cmd>Telescope commands<CR>", { desc = "telescope commands" })
map("n", "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", { desc = "telescope document symbols" })
map("n", "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<CR>", { desc = "telescope workspace symbols" })

-- Arquivos e navegacao -------------------------------------------------------
-- <C-n> (arvore) e <leader>e (foco) vem da base.
map("n", "-", "<cmd>Oil<CR>", { desc = "oil open parent directory as buffer" })

-- Codigo (LSP) ---------------------------------------------------------------
-- gd, gD, <leader>ra, <leader>D e <leader>ds vem do nvchad.configs.lspconfig.
-- K e fixado aqui, e nao deixado no default do Neovim 0.11+, por dois motivos
-- medidos: o default so nasce quando um servidor com hoverProvider anexa (logo
-- nao existe em buffer sem LSP), e nasce sem `desc`, o que o esconde do menu do
-- which-key — a secao 8 do nvim/README.md pede o contrario das duas coisas.
map("n", "K", vim.lsp.buf.hover, { desc = "LSP hover documentation" })
map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })
map("v", "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })
map("n", "<leader>fR", "<cmd>Telescope lsp_references<CR>", { desc = "LSP references (telescope)" })

-- Git ------------------------------------------------------------------------
map("n", "<leader>gs", "<cmd>Git<CR>", { desc = "git status (fugitive)" })
map("n", "<leader>gB", "<cmd>Git blame<CR>", { desc = "git blame file" })
map("n", "<leader>gp", function()
  require("gitsigns").preview_hunk()
end, { desc = "git preview hunk" })
map("n", "<leader>gb", function()
  require("gitsigns").toggle_current_line_blame()
end, { desc = "git toggle line blame" })
map("n", "]c", function()
  require("gitsigns").nav_hunk "next"
end, { desc = "git next hunk" })
map("n", "[c", function()
  require("gitsigns").nav_hunk "prev"
end, { desc = "git prev hunk" })

-- Testes ---------------------------------------------------------------------
map("n", "<leader>tn", "<cmd>TestNearest<CR>", { desc = "test nearest" })
map("n", "<leader>tf", "<cmd>TestFile<CR>", { desc = "test file" })
map("n", "<leader>ts", "<cmd>TestSuite<CR>", { desc = "test suite" })
map("n", "<leader>tl", "<cmd>TestLast<CR>", { desc = "test last" })
map("n", "<leader>tv", "<cmd>TestVisit<CR>", { desc = "test visit last test file" })
