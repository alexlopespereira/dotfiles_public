local wezterm = require("wezterm")
local mux = wezterm.mux

-- A janela inicial (a que abre pelo icone do dock) ja sobe no herdr, pra eu nao
-- esquecer de rodar ele. Abas/janelas novas (Cmd+T/Cmd+N) seguem shell normal.
-- gui-startup dispara so uma vez, na inicializacao do app.
--
-- Lancado pelo dock, o app tem ambiente quase zerado. `zsh -l` carrega o PATH do
-- nix, mas NAO o do homebrew (esse fica no .zshrc interativo, que -c nao le), e o
-- herdr vive em /opt/homebrew/bin. Sem isso a janela subia e fechava na hora
-- (herdr not found). O `brew shellenv` injeta o env do homebrew antes de exec
-- herdr, entao ele e os paineis filhos herdam nix + homebrew no PATH.
wezterm.on("gui-startup", function(cmd)
  local args = {
    "/bin/zsh", "-l", "-c",
    'eval "$(/opt/homebrew/bin/brew shellenv)"; exec herdr',
  }
  if cmd and cmd.args then
    args = cmd.args -- respeita `wezterm start -- <prog>` quando passado
  end
  mux.spawn_window({ args = args })
end)

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
-- Historico: ate 13/ago/2026 isto estava em 0.8, e a janela ficou
-- transparente demais na pratica. 0.95 mantem um veu de transparencia
-- com o maximo de legibilidade; o blur abaixo segue valendo nas bordas.
config.window_background_opacity = 0.95
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

return config
