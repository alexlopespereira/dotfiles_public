-- Treesitter: a LINHA NOVA do plugin (branch `main`), fixada explicitamente.
--
-- Secao 5 do nvim/README.md: o plugin tem duas linhas incompativeis e o padrao
-- mudou, entao deixar implicito falha em silencio. Aqui vale a regra 1 — o
-- compilador nativo da plataforma ja existe (Apple clang, do CommandLineTools),
-- entao usamos a linha cujas queries seguem mantidas para o Neovim atual. Com
-- ela a secao 6 (re-registrar diretivas de injecao) NAO se aplica: as diretivas
-- quebradas sao da linha antiga, congelada em 2024.
--
-- A linha nova nao compila sozinha: delega ao CLI `tree-sitter`, que por isso e
-- declarado em home.nix junto com o resto do sistema.
--
-- Consequencia de API: nada de `nvim-treesitter.configs`. Highlight e indent
-- passam a ser ligados por autocmd, como manda a `main`.

local M = {}

-- Lista declarada de linguagens (criterio de aceite: TODAS compilam).
-- markdown_inline entra junto com markdown: e ele que destaca o conteudo dos
-- blocos de codigo embutidos.
M.languages = {
  "bash",
  "c",
  "css",
  "diff",
  "git_config",
  "gitcommit",
  "gitignore",
  "html",
  "javascript",
  "json",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "nix",
  "python",
  "query",
  "regex",
  "ruby",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
}

function M.setup()
  local ts = require "nvim-treesitter"
  ts.setup {}

  -- Instala o que faltar, sem bloquear a abertura do editor. Ja instalado, sai
  -- na hora.
  local faltando = {}
  local instalados = {}
  for _, lang in ipairs(ts.get_installed "parsers") do
    instalados[lang] = true
  end
  for _, lang in ipairs(M.languages) do
    if not instalados[lang] then
      table.insert(faltando, lang)
    end
  end
  if #faltando > 0 then
    ts.install(faltando)
  end

  -- Na linha nova o highlight nao vem de `opts`: e vim.treesitter.start() por
  -- buffer. pcall porque filetype sem parser instalado nao pode derrubar a
  -- abertura do arquivo.
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
    callback = function(args)
      local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
      if not lang or not vim.treesitter.language.add(lang) then
        return
      end
      pcall(vim.treesitter.start, args.buf, lang)
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  })
end

return M
