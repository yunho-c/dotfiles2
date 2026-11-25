-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = {}

-- In newer versions of Wezterm, use the config_builder
if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- 1. Enable the macOS native background blur (Acrylic/Vibrancy effect)
-- A value of 20-30 is usually a good starting point.
config.macos_window_background_blur = 25

-- 2. Set the OVERALL window opacity. This is crucial.
-- This makes the entire window semi-transparent, allowing you to see the
-- blurred desktop/windows behind it.
config.window_background_opacity = 0.9

-- Add the wallpaper layer when the image is available on this Mac.
local wallpaper_dir = wezterm.home_dir .. '/Wallpaper'
local wallpaper_path = wallpaper_dir .. '/Abstract/pawel-czerwinski-prMn9KINLtI-unsplash.jpg'
local wallpaper_file = io.open(wallpaper_path, 'rb')
if wallpaper_file then
  wallpaper_file:close()
else
  wallpaper_path = nil
end

local function background(path, is_light)
  local layers = {}
  if path then
    table.insert(layers, {
      source = { File = path },
      opacity = 0.60,
      height = "Cover",
      hsb = { hue = 1.0, saturation = 1.0, brightness = 0.7 },
    })
  end
  table.insert(layers, {
    source = { Color = is_light and '#f9f5d7' or '#282c35' },
    opacity = is_light and 0.90 or 0.10,
    width = "100%",
    height = "100%",
  })
  return layers
end

config.background = background(wallpaper_path, false)

-- 4. Set your desired color scheme
-- config.color_scheme = "Catppuccin Mocha"
config.color_scheme = "Gruvbox dark, hard (base16)"

-- For good measure, let's add a font
config.font = wezterm.font 'JetBrains Mono'
-- config.font = wezterm.font 'Geist Mono'

config.window_decorations = "RESIZE"
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true

config.colors = {
  tab_bar = {
    background = 'rgba(0,0,0,0)'
  },
  selection_bg = "rgba:50% 50% 50% 50%"
}
config.window_frame = {
        inactive_titlebar_bg = "none",
        active_titlebar_bg = "none",
}

local light = 'Gruvbox light, hard (base16)'

local function current_wallpaper(current)
  local layer = current.background[1]
  local file = layer and layer.source.File
  return type(file) == 'table' and file.path or file
end

local function set_background(overrides, path, is_light)
  if path == wallpaper_path and not is_light then
    overrides.background = nil
  else
    overrides.background = background(path, is_light)
  end
end

wezterm.on('toggle-theme', function(window)
  local current = window:effective_config()
  local is_light = current.color_scheme ~= light
  local overrides = window:get_config_overrides() or {}
  overrides.color_scheme = is_light and light or nil
  set_background(overrides, current_wallpaper(current), is_light)
  window:set_config_overrides(overrides)
end)

local apply_wallpaper = wezterm.action_callback(function(window, _, path)
  if path then
    local overrides = window:get_config_overrides() or {}
    set_background(overrides, path, window:effective_config().color_scheme == light)
    window:set_config_overrides(overrides)
  end
end)

-- Other images in ~/Wallpaper appear under their relative filenames.
local wallpaper_names = {
  ['Abstract/pawel-czerwinski-prMn9KINLtI-unsplash.jpg'] = 'Abstract / Blue swirls',
  ['Nature/josefin-WS5yjFjycNY-unsplash.jpg'] = 'Nature / Monstera leaves',
  ['Space/benjamin-voros-phIFdC6lA4E-unsplash_opt.jpg'] = 'Space / Milky Way over mountains',
  ['Space/ngc4654-1-v5f-final_opt.jpg'] = 'Space / NGC 4654 galaxy',
}

wezterm.on('choose-wallpaper', function(window, pane)
  local current = current_wallpaper(window:effective_config())
  local files = wezterm.glob('**/*', wallpaper_dir)
  table.sort(files)
  local choices = {}
  for _, file in ipairs(files) do
    local name = file:lower()
    if name:match('%.jpe?g$') or name:match('%.png$') or name:match('%.webp$') then
      local path = wallpaper_dir .. '/' .. file
      local label = wallpaper_names[file] or file
      if path == current then label = label .. ' (current)' end
      table.insert(choices, { id = path, label = label })
    end
  end
  if #choices == 0 then
    window:toast_notification('WezTerm', 'Add a JPG, PNG, or WebP image to ' .. wallpaper_dir, nil, 4000)
    return
  end
  window:perform_action(wezterm.action.InputSelector {
    title = 'Choose wallpaper',
    choices = choices,
    action = apply_wallpaper,
  }, pane)
end)

config.keys = {
  { key = 'B', mods = 'CMD|SHIFT', action = wezterm.action.EmitEvent 'choose-wallpaper' },
  { key = 'L', mods = 'CMD|SHIFT', action = wezterm.action.EmitEvent 'toggle-theme' },
  { key = 'LeftArrow', mods = 'CMD|SHIFT', action = wezterm.action.MoveTabRelative(-1) },
  { key = 'RightArrow', mods = 'CMD|SHIFT', action = wezterm.action.MoveTabRelative(1) },
}

return config
