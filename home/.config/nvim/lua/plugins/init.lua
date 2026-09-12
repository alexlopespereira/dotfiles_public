-- Acrescimos a config base (secao 4 do nvim/README.md). O que a base ja resolve
-- fica de fora de proposito: arvore de arquivos, tela inicial, tema e
-- integracao com multiplexador de terminal.
return {
  {
    "stevearc/conform.nvim",
    opts = require "configs.conform",
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- Treesitter: sobrescreve a spec do NvChad, que aponta para a linha ANTIGA.
  -- `branch` e `config` proprios sao o "fixe explicitamente a linha usada" da
  -- secao 5 — sem isso a config escrita para uma linha falha em silencio na
  -- outra.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("configs.treesitter").setup()
    end,
  },

  -- Diretorio como buffer editavel: renomear/mover/apagar editando linhas.
  {
    "stevearc/oil.nvim",
    lazy = false,
    opts = {
      default_file_explorer = false, -- o nvim-tree da base continua o padrao
      view_options = { show_hidden = true },
    },
  },

  -- Camada de git completa (status, diff, blame, historico). O gitsigns da base
  -- cobre so o sinal na margem e o hunk.
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gclog", "Gwrite", "Gread" },
  },

  -- Menus nativos (vim.ui.select) dentro do telescope: code actions do LSP
  -- aparecem no buscador, nao num prompt cru.
  {
    "nvim-telescope/telescope-ui-select.nvim",
    lazy = false,
    config = function()
      require("telescope").setup {
        extensions = {
          ["ui-select"] = { require("telescope.themes").get_dropdown {} },
        },
      }
      require("telescope").load_extension "ui-select"
    end,
  },

  -- Linters/formatadores externos entregues como se fossem servidor de
  -- linguagem. Fonte cujo executavel nao esta no PATH e ignorada em silencio.
  --
  -- `none-ls-extras` nao e enfeite: o none-ls tirou do nucleo as fontes que
  -- dependem de binario de terceiro, e `diagnostics.shellcheck` foi uma delas.
  -- Sem o extras, a config sobe com "failed to load builtin shellcheck" e o
  -- diagnostico de shell simplesmente nao existe. Medido em 10/set/2026.
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvimtools/none-ls-extras.nvim" },
    event = "User FilePost",
    config = function()
      local null_ls = require "null-ls"
      null_ls.setup {
        sources = {
          require "none-ls.diagnostics.shellcheck",
          require "none-ls.code_actions.shellcheck",
        },
      }
    end,
  },

  -- Executor de testes: sob o cursor / arquivo / suite, no terminal do editor.
  {
    "vim-test/vim-test",
    cmd = { "TestNearest", "TestFile", "TestSuite", "TestLast", "TestVisit" },
    init = function()
      -- "neovim" = terminal embutido do proprio editor (criterio da secao 4).
      -- Nao usamos estrategia de multiplexador: a secao 4 diz que so faz
      -- sentido onde o multiplexador existe.
      vim.g["test#strategy"] = "neovim"
      vim.g["test#neovim#term_position"] = "vert botright 80"
    end,
  },
}
