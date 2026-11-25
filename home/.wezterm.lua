-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = {}

-- In newer versions of Wezterm, use the config_builder
if wezterm.config_builder then
  config = wezterm.config_builder()
end

local act = wezterm.action
local macos = wezterm.target_triple:find('apple%-darwin') ~= nil
local default_dark = 'Gruvbox dark, hard (base16)'
local default_light = 'Gruvbox light, hard (base16)'
config.color_scheme = default_dark
local defaults = {
  brightness = 70, opacity = 60, saturation = 100,
  dark_tint = 10, light_tint = 90, blur = 25, desktop_dim = 45,
}
config.macos_window_background_blur = defaults.blur
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

local function tint_key(is_light)
  return is_light and 'light_tint' or 'dark_tint'
end

local builtin_schemes
local function schemes()
  if not builtin_schemes then builtin_schemes = wezterm.color.get_builtin_schemes() end
  return builtin_schemes
end

local function theme_appearance(name)
  -- Keep the original wallpaper tints for the two Gruvbox defaults.
  if name == default_dark then return false, '#282c35' end
  if name == default_light then return true, '#f9f5d7' end
  local palette = schemes()[name]
  if not palette or not palette.background then return false, '#282c35' end
  local background_lightness = wezterm.color.parse(palette.background):laba()
  local foreground_lightness = wezterm.color.parse(palette.foreground or 'white'):laba()
  return background_lightness > foreground_lightness, palette.background
end

local function background(path, scheme, settings)
  local is_light, tint_color = theme_appearance(scheme)
  local tint = tint_key(is_light)
  local layers = {}
  local desktop_dim = settings.desktop_dim or defaults.desktop_dim
  if desktop_dim > 0 then
    table.insert(layers, {
      source = { Color = '#000000' }, opacity = desktop_dim / 100,
      width = '100%', height = '100%',
    })
  end
  if path then
    table.insert(layers, {
      source = { File = path },
      opacity = (settings.opacity or defaults.opacity) / 100,
      height = "Cover",
      hsb = {
        saturation = (settings.saturation or defaults.saturation) / 100,
        brightness = (settings.brightness or defaults.brightness) / 100,
      },
    })
  end
  table.insert(layers, {
    source = { Color = tint_color },
    opacity = (settings[tint] or defaults[tint]) / 100,
    width = "100%",
    height = "100%",
  })
  return layers
end

config.background = background(wallpaper_path, default_dark, {})

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

local function current_wallpaper(current)
  for _, layer in ipairs(current.background) do
    local file = layer.source.File
    if file then return type(file) == 'table' and file.path or file end
  end
end

-- Each GUI window keeps its adjustments across config reloads.
local function state_key(window)
  return 'background-settings-' .. window:window_id()
end

local function settings_for(window)
  return wezterm.GLOBAL[state_key(window)] or {}
end

local function apply_background(window, overrides, path, scheme, settings)
  local custom_image = settings.brightness or settings.saturation or settings.opacity
  local custom_background = custom_image or settings.dark_tint or settings.desktop_dim
  if path == wallpaper_path and scheme == default_dark and not custom_background then
    overrides.background = nil
  else
    overrides.background = background(path, scheme, settings)
  end
  if macos then overrides.macos_window_background_blur = settings.blur end
  window:set_config_overrides(overrides)
end

local function switch_theme(window, scheme)
  local current = window:effective_config()
  local overrides = window:get_config_overrides() or {}
  local settings = settings_for(window)
  local pair = settings.themes or {}
  if scheme then
    local mode = theme_appearance(scheme) and 'light' or 'dark'
    pair[mode] = scheme
    settings.themes = pair
    wezterm.GLOBAL[state_key(window)] = settings
  elseif theme_appearance(current.color_scheme) then
    scheme = pair.dark or default_dark
  else
    scheme = pair.light or default_light
  end
  overrides.color_scheme = scheme ~= default_dark and scheme or nil
  apply_background(window, overrides, current_wallpaper(current), scheme, settings)
end

wezterm.on('toggle-theme', function(window)
  switch_theme(window)
end)

local controls = {
  { key = 'brightness', label = 'Wallpaper brightness', max = 150, image = true },
  { key = 'opacity', label = 'Wallpaper opacity', max = 100, image = true },
  { key = 'saturation', label = 'Wallpaper saturation', max = 200, image = true },
  { key = 'tint', label = 'Theme tint strength', max = 100 },
  { key = 'blur', label = 'Desktop blur', max = 100 },
  { key = 'desktop_dim', label = 'Dim desktop behind window', max = 100 },
}

local function control_key(control, is_light)
  return control.key == 'tint' and tint_key(is_light) or control.key
end

local function control_label(control, settings, is_light)
  local key = control_key(control, is_light)
  local unit = key == 'blur' and '' or '%'
  return control.label .. '  ' .. (settings[key] or defaults[key]) .. unit
end

local function preview(window, pane, settings, is_light)
  local label = control_label(controls[settings.editing], settings, is_light)
  window:set_left_status('  ' .. label .. '    ← / → adjust    Esc done   ')
  -- Applying overrides clears the active key table on WezTerm 20240203.
  window:perform_action(act.ActivateKeyTable {
    name = 'adjust_background', one_shot = false, replace_current = true, prevent_fallback = true,
  }, pane)
end

wezterm.on('window-config-reloaded', function(window, pane)
  if not settings_for(window).editing or window:active_key_table() == 'adjust_background' then return end
  local is_light = theme_appearance(window:effective_config().color_scheme)
  local settings = settings_for(window)
  if settings.editing then preview(window, pane, settings, is_light) end
end)

local function step(delta)
  return wezterm.action_callback(function(window, pane)
    local current = window:effective_config()
    local overrides = window:get_config_overrides() or {}
    local settings = settings_for(window)
    local control = controls[settings.editing]
    if not control then return end
    local is_light = theme_appearance(current.color_scheme)
    local key = control_key(control, is_light)
    local value = math.max(0, math.min(control.max, (settings[key] or defaults[key]) + delta))
    if value == defaults[key] then
      settings[key] = nil
    else
      settings[key] = value
    end
    wezterm.GLOBAL[state_key(window)] = settings
    apply_background(window, overrides, current_wallpaper(current), current.color_scheme, settings)
    preview(window, pane, settings, is_light)
  end)
end

local finish = wezterm.action_callback(function(window, pane)
  local overrides = window:get_config_overrides() or {}
  local settings = settings_for(window)
  overrides.hide_tab_bar_if_only_one_tab = settings.previous_hide
  settings.editing, settings.previous_hide = nil, nil
  wezterm.GLOBAL[state_key(window)] = settings
  window:set_left_status('')
  window:perform_action(act.PopKeyTable, pane)
  window:set_config_overrides(overrides)
end)

config.key_tables = {
  adjust_background = {
    { key = 'LeftArrow', action = step(-5) },
    { key = 'RightArrow', action = step(5) },
    { key = 'Escape', action = finish },
    { key = 'Enter', action = finish },
  },
}

local select_control = wezterm.action_callback(function(window, pane, id)
  if not id then return end
  local overrides = window:get_config_overrides() or {}
  local current = window:effective_config()
  local is_light = theme_appearance(current.color_scheme)
  local settings = settings_for(window)
  if id == 'reset' then
    settings = { themes = settings.themes }
  elseif id == 'frosted' then
    settings.blur = 45
    settings.opacity = 15
    settings[tint_key(is_light)] = is_light and 45 or 35
  else
    settings.editing = tonumber(id)
    settings.previous_hide = overrides.hide_tab_bar_if_only_one_tab
    overrides.hide_tab_bar_if_only_one_tab = false
    wezterm.GLOBAL[state_key(window)] = settings
    window:set_config_overrides(overrides)
    preview(window, pane, settings, is_light)
    return
  end
  wezterm.GLOBAL[state_key(window)] = settings
  apply_background(window, overrides, current_wallpaper(current), current.color_scheme, settings)
end)

local function show_controls(window, pane)
  local current = window:effective_config()
  local settings = settings_for(window)
  local has_image = current_wallpaper(current) ~= nil
  local is_light = theme_appearance(current.color_scheme)
  local choices = {}
  for i, control in ipairs(controls) do
    if (has_image or not control.image) and (macos or control.key ~= 'blur') then
      table.insert(choices, { id = tostring(i), label = control_label(control, settings, is_light) })
    end
  end
  if macos then table.insert(choices, { id = 'frosted', label = 'Frosted glass preset' }) end
  table.insert(choices, { id = 'reset', label = 'Reset adjustments to defaults' })
  window:perform_action(act.InputSelector {
    title = 'Adjust background', choices = choices, action = select_control,
  }, pane)
end

local featured_themes = {
  default_dark, default_light,
  'Catppuccin Mocha', 'Catppuccin Latte',
  'Tokyo Night', 'Tokyo Night Day',
  'Rosé Pine (Gogh)', 'Rosé Pine Dawn (Gogh)',
}

local show_themes
local select_theme = wezterm.action_callback(function(window, pane, name)
  if name == 'browse-all' then
    show_themes(window, pane, true)
  elseif name then
    switch_theme(window, name)
  end
end)

show_themes = function(window, pane, browse_all)
  local palettes = schemes()
  local names = featured_themes
  if browse_all then
    names = {}
    for name in pairs(palettes) do table.insert(names, name) end
    table.sort(names)
  end
  local current = window:effective_config().color_scheme
  local choices = {}
  for _, name in ipairs(names) do
    local palette = palettes[name]
    if palette then
      local label = name == current and (name .. ' (current)') or name
      if palette.background and palette.foreground and palette.ansi then
        label = wezterm.format {
          { Text = label .. '  ' },
          { Background = { Color = palette.background } },
          { Foreground = { Color = palette.foreground } }, { Text = ' Aa ' },
          { Foreground = { Color = palette.ansi[2] } }, { Text = '●' },
          { Foreground = { Color = palette.ansi[3] } }, { Text = '●' },
          { Foreground = { Color = palette.ansi[5] } }, { Text = '● ' },
        }
      end
      table.insert(choices, { id = name, label = label })
    end
  end
  if not browse_all then table.insert(choices, { id = 'browse-all', label = 'Browse all themes…' }) end
  window:perform_action(act.InputSelector {
    title = 'Color theme', choices = choices, action = select_theme,
    fuzzy = browse_all, fuzzy_description = 'Find a color theme: ',
  }, pane)
end

local apply_wallpaper = wezterm.action_callback(function(window, pane, path)
  if path == 'adjust' then
    show_controls(window, pane)
  elseif path == 'themes' then
    show_themes(window, pane, false)
  elseif path then
    local overrides = window:get_config_overrides() or {}
    local scheme = window:effective_config().color_scheme
    apply_background(window, overrides, path, scheme, settings_for(window))
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
  local other_wallpapers = {}
  for _, file in ipairs(files) do
    local name = file:lower()
    if name:match('%.jpe?g$') or name:match('%.png$') or name:match('%.webp$') then
      local path = wallpaper_dir .. '/' .. file
      local label = wallpaper_names[file] or file
      if path == current then
        label = label .. ' (current)'
      else
        table.insert(other_wallpapers, path)
      end
      table.insert(choices, { id = path, label = label })
    end
  end
  local empty_hint = #choices == 0 and 'Add JPG, PNG, or WebP images to ~/Wallpaper, or adjust the background.' or nil
  local can_shuffle = #choices > 1
  table.insert(choices, { id = 'adjust', label = 'Adjust background…' })
  table.insert(choices, { id = 'themes', label = 'Color theme…' })
  if can_shuffle then
    local next_wallpaper = other_wallpapers[math.random(#other_wallpapers)]
    table.insert(choices, { id = next_wallpaper, label = 'Shuffle wallpaper' })
  end
  window:perform_action(wezterm.action.InputSelector {
    title = 'Appearance',
    description = empty_hint,
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
