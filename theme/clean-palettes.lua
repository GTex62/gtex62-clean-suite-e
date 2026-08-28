-- clean-palettes.lua
-- Color scheme catalog for gtex62-clean-suite-e.
-- Each palette defines named RGBA roles consumed by clean-theme.lua.
-- Selected at launch via GTEX62_PALETTE env var (default: "default").

local palettes = {}

-- Original clean-suite color identity: white/gray on near-black, golden accent.
palettes["default"] = {
  name    = "Default",

  -- Base UI roles
  bg      = { 0.05, 0.05, 0.07, 0.82 },  -- near-black panel background
  fg      = { 1.00, 1.00, 1.00, 0.90 },  -- primary text (white)
  ink     = { 0.63, 0.63, 0.63, 0.80 },  -- secondary text / labels (gray)
  dim     = { 0.35, 0.35, 0.35, 0.80 },  -- de-emphasized text (dark gray)
  accent  = { 1.00, 0.84, 0.29, 1.00 },  -- golden #FFD54A — bars, markers, highlights

  -- Status roles
  ok      = { 0.00, 1.00, 0.00, 0.85 },  -- #00FF00
  warn    = { 1.00, 0.65, 0.00, 0.90 },  -- #FFA500
  err     = { 1.00, 0.33, 0.33, 0.90 },  -- #FF5555

  -- Network throughput graph
  net_up   = { 1.00, 0.69, 0.00, 1.00 }, -- #FFB000 upload
  net_down = { 0.00, 0.84, 1.00, 1.00 }, -- #00D7FF download

  -- Slash-bar unfilled segments (SYS panel CPU/RAM/GPU meters)
  slash_empty = { 0.35, 0.35, 0.35, 1.00 }, -- #5A5A5A (legacy bar_empty_color)

  -- pfSense VLAN flow arcs. Direction is encoded by marker shape
  -- (filled IN / hollow OUT), per-VLAN marker colors are fixed
  -- conventions in clean-theme.lua (theme.pf_markers) — so the only
  -- palette role here is the base arc stroke.
  pf_arc_base = { 0.65, 0.65, 0.65, 1.00 }, -- base arc stroke (gray65)
}

-- Dark variant: cooler, more blue-shifted background with teal accent.
palettes["dark"] = {
  name    = "Dark",

  bg      = { 0.03, 0.04, 0.08, 0.88 },
  fg      = { 0.92, 0.95, 1.00, 0.90 },
  ink     = { 0.55, 0.58, 0.65, 0.80 },
  dim     = { 0.30, 0.32, 0.38, 0.80 },
  accent  = { 0.20, 0.90, 0.80, 1.00 },  -- teal

  ok      = { 0.20, 0.90, 0.45, 0.90 },
  warn    = { 1.00, 0.70, 0.15, 0.90 },
  err     = { 0.95, 0.28, 0.28, 0.90 },

  net_up   = { 1.00, 0.69, 0.00, 1.00 },
  net_down = { 0.20, 0.90, 0.80, 1.00 },

  slash_empty = { 0.30, 0.32, 0.38, 1.00 }, -- blue-shifted gray, matches dim ramp

  pf_arc_base = { 0.55, 0.55, 0.60, 1.00 },
}

return palettes
