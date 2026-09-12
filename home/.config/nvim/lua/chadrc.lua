-- Estrutura espelha nvconfig.lua do NvChad/ui (v3.0), que lista todas as opcoes.
---@type ChadrcConfig
local M = {}

M.base46 = {
  -- Tema do base46, nao plugin novo: a secao 4 do nvim/README.md manda preferir
  -- um da colecao da base a instalar concorrente. `rosepine` e o equivalente do
  -- tema que a config anterior deste repo usava, entao a troca de config nao
  -- muda a cara do editor.
  theme = "rosepine",
}

M.ui = {
  -- Abas sempre visiveis: <Tab>/<S-Tab> circulam buffers (ver nvim-atalhos).
  tabufline = { lazyload = false },
}

return M
