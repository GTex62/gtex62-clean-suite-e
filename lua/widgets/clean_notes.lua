---@diagnostic disable: undefined-global, lowercase-global
-- lua/widgets/clean_notes.lua
-- Lua draw entrypoint for the Notes standalone window (NOTES text).
-- Loaded by widgets/clean-notes.conky.conf via lua_load.
-- conky_draw_notes() is called each frame via lua_draw_hook_pre.

require "cairo"

local HOME      = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR")
  or (HOME .. "/.config/conky/gtex62-clean-suite-e")

local frame, theme, panels, notes

local function ensure_loaded()
  if frame ~= nil then return end
  frame  = dofile(SUITE_DIR .. "/lua/ui/frame.lua")
  theme  = dofile(SUITE_DIR .. "/theme/clean-theme.lua")
  panels = dofile(SUITE_DIR .. "/theme/panels.lua")
  notes  = dofile(SUITE_DIR .. "/lua/suite/notes.lua")
end

function conky_draw_notes()
  if conky_window == nil then return end
  ensure_loaded()

  local w = conky_window.width
  local h = conky_window.height
  local surface = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(surface)

  frame.draw_notes(cr, theme, panels, { notes = notes })

  cairo_destroy(cr)
  cairo_surface_destroy(surface)
end
