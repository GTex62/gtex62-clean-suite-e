---@diagnostic disable: undefined-global, lowercase-global
-- lua/widgets/clean_pfsense.lua
-- Lua draw entrypoint for the pfSense standalone chassis (VLAN flow arcs).
-- Loaded by widgets/clean-pfsense.conky.conf via lua_load.
-- conky_draw_pfsense() is called each frame via lua_draw_hook_pre.
--
-- providers.pfsense.ifaces disabled -> exit before the first real draw
-- (pf.M.enabled(), core.toml-gated) rather than rendering a flat, silent,
-- empty arc indistinguishable from genuine zero traffic (confirmed gap,
-- see docs/doctor-design.md's Open Questions in gtex62-core, and pf.lua's
-- own header comment here for the full writeup). own_window_transparent
-- means a window that draws nothing is already invisible, but it would
-- otherwise keep running a 1s-interval no-op draw loop forever; exiting
-- the process outright means the widget genuinely doesn't load, not just
-- render blank. Checked once, on the very first frame, before any
-- cairo/surface work — if the provider is enabled this check never runs
-- again for the life of the process, same as every other suite here only
-- picking up a core.toml change on its next launch, not while running.

require "cairo"

local HOME      = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR")
  or (HOME .. "/.config/conky/gtex62-clean-suite-e")

local frame, theme, panels, pf
local checked_enabled = false

local function ensure_loaded()
  if frame ~= nil then return end
  frame  = dofile(SUITE_DIR .. "/lua/ui/frame.lua")
  theme  = dofile(SUITE_DIR .. "/theme/clean-theme.lua")
  panels = dofile(SUITE_DIR .. "/theme/panels.lua")
  pf     = dofile(SUITE_DIR .. "/lua/suite/pf.lua")
end

function conky_draw_pfsense()
  if conky_window == nil then return end
  ensure_loaded()

  if not checked_enabled then
    checked_enabled = true
    if not pf.enabled() then
      os.exit(0)
    end
  end

  local w = conky_window.width
  local h = conky_window.height
  local surface = cairo_xlib_surface_create(
    conky_window.display, conky_window.drawable, conky_window.visual, w, h)
  local cr = cairo_create(surface)

  frame.draw_pfsense(cr, theme, panels, { pf = pf })

  cairo_destroy(cr)
  cairo_surface_destroy(surface)
end
