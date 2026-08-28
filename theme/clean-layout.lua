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
-- Tall narrow panel on the left edge of the SECONDARY monitor,
-- matching the legacy suite (theme.monitor_head = 1, sys-info at
-- gap 40,30 and net-sys stacked below at 40,780).
-- Legacy footprint: sys-info 360×600 + net-sys 310×400, stacked.
----------------------------------------------------------------
layout.monitor = {
  -- Window size measured off the accepted Conky-text rendering at this
  -- machine's font DPI (mono size=10 → 18 px glyphs, 23 px lines); the
  -- Cairo port draws the same character grid (panels.monitor_grid).
  frame         = { x = 0, y = 0, width = 568, height = 1980 },
  margin        = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 1, -- secondary monitor (legacy monitor_head = 1)
  alignment     = "top_left",
  -- Legacy conf said gap 40,30, but the legacy Conky-text window
  -- rendered its first glyph at head-relative (57, 45) (window
  -- autosize + inner margin — same pitfall as the calendar). The
  -- Cairo window draws at gap + (7, 10), so gap 55,40 reproduces
  -- the *visible* legacy position, audited per the runbook's
  -- "audit the rendered position" note.
  gap_x         = 55,
  gap_y         = 40,
}

----------------------------------------------------------------
-- Ambient chassis  (TME clock + WXR/ORB weather stack)
-- Matches the legacy stack on the SECONDARY monitor:
--   date-time.conky.conf  top_middle head 1, 640 wide, gap_y 40
--   weather.conky.conf    top_middle head 1, 640 wide, gap_y 130
-- The chassis window starts at the legacy date-time position; the
-- weather block begins 90px below the chassis top (130 - 40).
-- The calendar is NOT in this chassis — legacy ran it as its own
-- top_right window, disjoint from this footprint, so it is a
-- standalone instance (layout.calendar below).
----------------------------------------------------------------
layout.ambient = {
  frame         = { x = 0, y = 0, width = 680, height = 770 },
  margin        = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 1,  -- secondary monitor (legacy monitor_head = 1)
  alignment     = "top_middle",
  gap_x         = 0,  -- legacy date-time gap_x
  gap_y         = 40, -- legacy date-time gap_y
}

----------------------------------------------------------------
-- Calendar standalone  (CAL month grid)
-- Legacy calendar.conky.conf: its own window, top_right head 1.
-- gap values are the measured on-screen position of the running
-- legacy widget (grid at head-relative x 3411..3773, content top
-- y 41), not the legacy conf's raw gap 0,30 — the legacy window
-- autosized wider than its minimum_width and drew at
-- cal_origin_x = 78, which baked a 67px right inset into the
-- visible position. This frame is snug (no draw offset), so the
-- inset moves into gap_x/gap_y.
----------------------------------------------------------------
layout.calendar = {
  frame         = { x = 0, y = 0, width = 362, height = 273 },
  margin        = { top = 0, left = 0, right = 0, gap = 0 },
  xinerama_head = 1, -- secondary monitor (legacy monitor_head = 1)
  alignment     = "top_right",
  gap_x         = 67,
  gap_y         = 41,
}

----------------------------------------------------------------
-- Media chassis  (MSC + LYRICS)
-- Tall panel on the secondary monitor (or right edge of primary).
-- Legacy footprint: music 640×270 + lyrics 560×940.
-- NOTES is a standalone top_right window (layout.notes), matching
-- the legacy suite — it does not live in this chassis.
-- UNCONVERTED: geometry below is still the OSA leftover; audit
-- against legacy music/lyrics confs (top_middle gap 0,530 / -600,300)
-- during the msc/lyrics conversions.
----------------------------------------------------------------
layout.media = {
  frame         = { x = 0, y = 0, width = 580, height = 1300 },
  margin        = { top = 24, left = 18, right = 18, gap = 18 },
  xinerama_head = 1, -- secondary monitor
  alignment     = "top_middle",
  gap_x         = 0,
  gap_y         = 1000,
}

----------------------------------------------------------------
-- Notes standalone  (NOTES sticky-notes text)
-- Legacy notes.conky.conf ran as its own top_right window on head 1;
-- kept standalone because that position is disjoint from the media
-- chassis footprint (top_middle), same reasoning as the calendar.
-- gap_x reproduces the measured on-screen position of the running
-- legacy widget (text left at head-relative x 3407), not the legacy
-- conf's raw gap 0,210 — the legacy window rendered at y 287 and
-- autosized to 445px wide, ignoring its own maximum_width 310.
-- Cairo window sits at gap-5 with a frame+10 window, so: text left =
-- 3840-gap_x+5-(width+10)+x0, baseline1 = gap_y-5+first_baseline.
-- gap_y was measured as 292 (legacy match) but later moved to 350 by
-- preference (2026-08-27) — the vertical position is no longer a
-- legacy reproduction.
----------------------------------------------------------------
layout.notes = {
  frame         = { x = 0, y = 0, width = 404, height = 1810 },
  margin        = { top = 0, left = 0, right = 0, gap = 0 },
  xinerama_head = 1, -- secondary monitor (legacy monitor_head = 1)
  alignment     = "top_right",
  gap_x         = 31,
  gap_y         = 350,
}

----------------------------------------------------------------
-- pfSense standalone  (VLAN flow arcs only)
-- Sized for arcs + arc name labels + in/out markers (the legacy
-- baseline hline is present but disabled in panels.pfsense).
-- CPU/MEM meters, nameplate, gateway label, totals table, and
-- pfBlockerNG/Pi-hole status are NOT included here — retired to
-- the core sitrep utility (conversion guide §1.4).
-- Legacy footprint (full widget): 640×720. Arcs-only is shorter.
-- Position is deliberately NOT audited from the legacy conf's
-- top_middle gap_y 740: the legacy suite predates correct monitor
-- targeting (it offset from monitor 0 to land on monitor 1), so
-- that value encodes the bug, not intent. bottom_middle head 1 with
-- gap_y lifting the window off the bottom edge was set and confirmed
-- by direct observation instead.
----------------------------------------------------------------
layout.pfsense = {
  -- Snug frame, zero margins — same pattern as the calendar and notes
  -- standalones: panels.pfsense's box equals this frame at (0,0) and the
  -- dome centers itself inside it (headroom is built into arc.r vs
  -- width/2 and arc.dy vs r; see the note on panels.pfsense).
  frame         = { x = 0, y = 0, width = 840, height = 500 },
  margin        = { top = 0, left = 0, right = 0, gap = 0 },
  xinerama_head = 1, -- secondary monitor
  alignment     = "bottom_middle",
  gap_x         = 0,
  gap_y         = 150,
}

return layout
