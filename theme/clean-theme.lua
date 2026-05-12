-- clean-theme.lua
-- Loads the active palette and exposes non-geometric suite-wide settings:
-- fonts, stroke widths, frame effects, status colors, and fixed domain
-- constants (astronomy markers, planet colors) that do not vary by palette.

local HOME      = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR")
               or (HOME .. "/.config/conky/gtex62-clean-suite-e")
local PAL_ID    = os.getenv("GTEX62_PALETTE") or "default"

local catalog = dofile(SUITE_DIR .. "/theme/clean-palettes.lua")
local palette  = catalog[PAL_ID] or catalog["default"]

local theme = {}

-- Active palette (all role tables available as theme.palette.*)
theme.palette = palette

-- Convenience shortcuts
theme.colors = {
  bg     = palette.bg,
  fg     = palette.fg,
  ink    = palette.ink,
  dim    = palette.dim,
  accent = palette.accent,
}
theme.status = {
  ok   = palette.ok,
  warn = palette.warn,
  err  = palette.err,
}
theme.net = {
  up   = palette.net_up,
  down = palette.net_down,
}
theme.pf = {
  arc_base = palette.pf_arc_base,
  arc_in   = palette.pf_arc_in,
  arc_out  = palette.pf_arc_out,
}

----------------------------------------------------------------
-- Typography
----------------------------------------------------------------
theme.fonts = {
  -- UI chrome
  title  = "Inter Bold",
  label  = "Inter",
  -- Data readouts (monospace)
  data   = "JetBrainsMono Nerd Font Mono",
  mono   = "DejaVu Sans Mono",
  -- Fallback
  base   = "DejaVu Sans",
  -- Clock (large)
  time   = "DejaVu Sans Mono",
}
theme.sizes = {
  title   = 11,
  label   = 10,
  data    = 10,
  small   =  9,
  time    = 22,
  date    = 12,
  gmt     = 10,
}

----------------------------------------------------------------
-- Strokes and geometry constants
----------------------------------------------------------------
theme.strokes = {
  line   = 0.5,  -- separator / hline
  frame  = 1.5,  -- panel border
  meter  = 8.0,  -- bar/meter thickness
  arc    = 2.0,  -- thin arc outlines
}
theme.alpha = {
  panel_bg   = 0.72,
  separator  = 0.35,
  inactive   = 0.45,
}

-- Slash-bar style (SYS panel CPU/RAM/GPU)
theme.slash = {
  count       = 20,
  fill_color  = palette.accent,
  empty_color = { 0.35, 0.35, 0.35, 1.00 }, -- #5A5A5A
  char        = "/",
}

-- Separator line style
theme.sep = {
  char  = "-",
  count = 50,
}

----------------------------------------------------------------
-- Frame effects
----------------------------------------------------------------
theme.frame_shadow = {
  enabled     = true,
  alpha_scale = 0.18,
}
theme.frame_lights = {
  enabled = false,
}

----------------------------------------------------------------
-- Astronomy — fixed colors (not palette-dependent)
-- Sun and moon are physical objects; their marker colors are
-- conventional and do not change with the color scheme.
----------------------------------------------------------------
theme.astro = {
  sun = {
    diameter = 36,
    stroke   = 10.0,
    color    = { 1.00, 0.78, 0.10, 1.00 }, -- golden-orange
  },
  moon = {
    diameter = 26,
    stroke   = 10.0,
    color    = { 0.75, 0.75, 0.80, 1.00 }, -- grayish-white
  },
  arc_day   = { 0.65, 0.65, 0.65, 1.00 }, -- daytime arc stroke  (gray65)
  arc_night = { 0.14, 0.14, 0.14, 1.00 }, -- nighttime arc stroke (gray14)
  -- Visible planets: radius + RGBA color
  planets = {
    VENUS   = { r =  12, color = { 1.00, 0.95, 0.70, 1.00 } }, -- cream-yellow
    MARS    = { r =  15, color = { 0.95, 0.45, 0.20, 1.00 } }, -- red-orange
    JUPITER = { r =  13, color = { 0.90, 0.82, 0.65, 1.00 } }, -- pale tan
    SATURN  = { r =  12, color = { 0.85, 0.75, 0.50, 1.00 } }, -- pale gold
    MERCURY = { r =   9, color = { 0.78, 0.80, 0.86, 1.00 } }, -- gray-silver
  },
}

----------------------------------------------------------------
-- pfSense VLAN per-arc marker colors
-- WAN gets the accent/err color; VLANs use decreasing grays so
-- the concentric arcs read at a glance by brightness.
-- These are fixed visual conventions, not palette-dependent.
----------------------------------------------------------------
theme.pf_markers = {
  WAN   = { r = 12, color = { 1.00, 0.00, 0.00, 1.00 } }, -- red (most prominent)
  HOME  = { r = 12, color = { 0.60, 0.60, 0.60, 1.00 } }, -- medium gray
  IOT   = { r = 12, color = { 0.40, 0.40, 0.40, 1.00 } }, -- dark gray
  GUEST = { r = 12, color = { 0.25, 0.25, 0.25, 1.00 } }, -- very dark gray
  INFRA = { r = 12, color = { 1.00, 1.00, 1.00, 1.00 } }, -- white
}

return theme
