-- clean-layout.lua
-- Chassis frame geometry and monitor targeting for gtex62-clean-suite-e.
-- Defines the outer window size and margin structure for each Conky process.
-- Per-panel positions and sub-box geometry live in panels.lua.
--
-- Monitor targeting uses xinerama_head in each .conky.conf rather than
-- absolute gap_x pixel offsets, so layout survives resolution changes.
-- gap_x / gap_y here are intra-monitor offsets only.

local layout = {}

----------------------------------------------------------------
-- Monitor chassis  (SYS + NET)
-- Tall narrow panel on the left edge of the primary monitor.
-- Legacy footprint: sys-info 360×600 + net-sys 310×400, stacked.
----------------------------------------------------------------
layout.monitor = {
  frame  = { x = 0, y = 0, width = 420, height = 1060 },
  margin = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 0,     -- primary monitor
  alignment     = "top_left",
  gap_x         = 0,
  gap_y         = 0,
}

----------------------------------------------------------------
-- Ambient chassis  (WXR + ORB + TME)
-- Wide panel sized to hold the horizon arc (min 640px) plus the
-- calendar alongside or below.
-- Legacy footprint: weather 640×350 + date-time 640×90 + calendar 380×280.
----------------------------------------------------------------
layout.ambient = {
  frame  = { x = 0, y = 0, width = 680, height = 820 },
  margin = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 0,     -- primary monitor; position via gap_x/gap_y
  alignment     = "top_right",
  gap_x         = 0,
  gap_y         = 0,
}

----------------------------------------------------------------
-- Media chassis  (MSC + NOTES + LYRICS)
-- Tall panel on the secondary monitor (or right edge of primary).
-- Legacy footprint: music 640×270 + notes 310×1260 + lyrics 560×940.
-- Arranged vertically: MSC on top, LYRICS mid, NOTES fills remainder.
----------------------------------------------------------------
layout.media = {
  frame  = { x = 0, y = 0, width = 580, height = 1300 },
  margin = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 1,     -- secondary monitor
  alignment     = "top_left",
  gap_x         = 0,
  gap_y         = 0,
}

----------------------------------------------------------------
-- pfSense standalone  (VLAN flow arcs only)
-- Sized for arcs + arc labels + in/out markers + nameplate.
-- Status block / totals table / pfBlockerNG are NOT included
-- here — those live in the core sitrep utility.
-- Legacy footprint (full widget): 640×720. Arcs-only is shorter.
----------------------------------------------------------------
layout.pfsense = {
  frame  = { x = 0, y = 0, width = 660, height = 520 },
  margin = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 1,     -- secondary monitor
  alignment     = "top_right",
  gap_x         = 0,
  gap_y         = 0,
}

return layout
