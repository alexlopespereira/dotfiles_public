-- Formatadores por filetype. Sao ferramentas externas: as que faltarem no PATH
-- o conform simplesmente pula, e o <leader>fm cai no LSP (lsp_fallback).
-- `stylua` vem do nix (home.nix); os de npm o mason instala sob demanda.
return {
  formatters_by_ft = {
    lua = { "stylua" },
    sh = { "shfmt" },
    bash = { "shfmt" },
    nix = { "nixfmt" },
    json = { "prettier" },
    yaml = { "prettier" },
    markdown = { "prettier" },
    html = { "prettier" },
    css = { "prettier" },
    javascript = { "prettier" },
    typescript = { "prettier" },
    python = { "ruff_format" },
  },
}
