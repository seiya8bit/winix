local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- Shell & IME
config.default_prog = { "pwsh.exe" }
config.use_ime = true

-- Appearance
config.color_scheme = "Tokyo Night"
config.font = wezterm.font("HackGen35 Console NF")
config.font_size = 12
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

wezterm.on("gui-startup", function()
  local _, _, window = wezterm.mux.spawn_window({})
  window:gui_window():maximize()
end)

-- Leader key
config.leader = { key = "s", mods = "CTRL", timeout_milliseconds = 1000 }

-- Mouse: auto copy on selection
config.selection_word_boundary = " \t\n{}[]()\"'"
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = act.CompleteSelection("ClipboardAndPrimarySelection"),
  },
}

-- Helper for LEADER keybindings
local function leader(key, action)
  return { key = key, mods = "LEADER", action = action }
end

-- Keybindings
config.keys = {
  { key = "v", mods = "CTRL", action = act.PasteFrom("Clipboard") },
  -- Pane split
  leader("\\", act.SplitHorizontal({ domain = "CurrentPaneDomain" })),
  leader("-", act.SplitVertical({ domain = "CurrentPaneDomain" })),
  -- Pane navigation
  leader("h", act.ActivatePaneDirection("Left")),
  leader("j", act.ActivatePaneDirection("Down")),
  leader("k", act.ActivatePaneDirection("Up")),
  leader("l", act.ActivatePaneDirection("Right")),
  -- Pane resize
  { key = "LeftArrow", mods = "CTRL", action = act.AdjustPaneSize({ "Left", 2 }) },
  { key = "DownArrow", mods = "CTRL", action = act.AdjustPaneSize({ "Down", 2 }) },
  { key = "UpArrow", mods = "CTRL", action = act.AdjustPaneSize({ "Up", 2 }) },
  { key = "RightArrow", mods = "CTRL", action = act.AdjustPaneSize({ "Right", 2 }) },
  -- Pane/Tab management
  leader("q", act.CloseCurrentPane({ confirm = true })),
  leader("c", act.SpawnTab("CurrentPaneDomain")),
  leader("z", act.TogglePaneZoomState),
  -- Tab navigation
  leader("n", act.ActivateTabRelative(1)),
  leader("p", act.ActivateTabRelative(-1)),
  leader("1", act.ActivateTab(0)),
  leader("2", act.ActivateTab(1)),
  leader("3", act.ActivateTab(2)),
  leader("4", act.ActivateTab(3)),
  leader("5", act.ActivateTab(4)),
}

return config
