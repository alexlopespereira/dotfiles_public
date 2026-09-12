require("nvchad.configs.lspconfig").defaults() -- ja habilita e configura o lua_ls

-- API de LSP moderna do Neovim 0.11+ (vim.lsp.config/enable) — e por isso que a
-- secao 2 do nvim/README.md exige 0.11 ou maior.
-- Instale os servidores com :Mason; os que nao estiverem instalados
-- simplesmente nao anexam, sem erro.
local servers = {
  "html",
  "cssls",
  "jsonls",
  "yamlls",
  "bashls",
  "ts_ls",
  "pyright",
  "nil_ls", -- nix
}

vim.lsp.enable(servers)

-- read :h vim.lsp.config para mudar opcoes de um servidor
