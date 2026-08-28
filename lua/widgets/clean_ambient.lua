---@diagnostic disable: undefined-global, lowercase-global
-- lua/widgets/clean_ambient.lua
-- Lua draw entrypoint for the Ambient chassis (WXR + ORB + TME).
-- Loaded by widgets/clean-ambient.conky.conf via lua_load.
-- conky_draw_ambient() is called each frame via lua_draw_hook_pre.

require "cairo"

local HOME      = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR")
  or (HOME .. "/.config/conky/gtex62-clean-suite-e")

local frame, theme, panels, wxr, orb, tme

local function ensure_loaded()
  if frame ~= nil then return end
  frame  = dofile(SUITE_DIR .. "/lua/ui/frame.lua")
  theme  = dofile(SUITE_DIR .. "/theme/clean-theme.lua")
  panels = dofile(SUITE_DIR .. "/theme/panels.lua")
  wxr    = dofile(SUITE_DIR .. "/lua/suite/wxr.lua")
  orb    = dofile(SUITE_DIR .. "/lua/suite/orb.lua")
  tme    = dofile(SUITE_DIR .. "/lua/suite/tme.lua")
end

function conky_draw_ambient()
  if conky_window == nil then return end
  ensure_loaded()

  local w = conky_window.width
  local h = conky_window.height
  local surface = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(surface)

  frame.draw_ambient(cr, theme, panels, { wxr = wxr, orb = orb, tme = tme })

  cairo_destroy(cr)
  cairo_surface_destroy(surface)
end
