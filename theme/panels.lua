-- panels.lua
-- Per-panel position, size, title, and sub-box geometry for gtex62-clean-suite-e.
-- All coordinates are relative to the chassis frame origin (0, 0).
-- Chassis outer dimensions are in clean-layout.lua.
--
-- Box coordinates are relative to their parent panel origin.
-- "title" is the label drawn in the panel header row.

local HOME          = os.getenv("HOME") or ""
local SUITE_DIR     = os.getenv("CONKY_SUITE_DIR")
    or (HOME .. "/.config/conky/gtex62-clean-suite-e")

-- Chassis frame geometry — the media panels derive their x-geometry
-- from layout.media.frame.width (see the MEDIA CHASSIS section), so
-- resizing that frame never moves the arc axis or the lyrics column.
local layout        = dofile(SUITE_DIR .. "/theme/clean-layout.lua")

local panels        = {}

----------------------------------------------------------------
-- MONITOR CHASSIS  (568 × 1980, layout.monitor.frame)
-- Legacy sys-info + net-sys stack rendered as one continuous text
-- flow (the accepted conky.text layout, now drawn in Cairo). All
-- metrics below were measured off the running Conky-text widget at
-- this machine's font DPI: mono size=10 rendered 18 px glyphs
-- (char advance ~10.85), 23 px line height, goto 260/185 columns
-- landing at x 368/262. SYS and NET share this grid (x0/line_px/
-- font_px/char_px) but position independently — SYS starts at
-- monitor_grid.first_baseline, NET at its own fixed panels.net.y0
-- (see that field's comment, F3 2026-08-29) — matching the fixed
-- sub-position pattern the ambient and media chassis already use.
----------------------------------------------------------------

-- Shared character grid for the monitor text flow
panels.monitor_grid = {
  x0             = 7,     -- left text margin
  first_baseline = 24,    -- baseline of line 1
  line_px        = 23,    -- vertical advance per text line
  font_px        = 18,    -- mono font size (px)
  char_px        = 10.85, -- mono char advance at font_px
}

-- SYS — OS/host header, disk table, CPU/RAM/GPU slash bars,
-- top-5 process rows, hardware id footer
panels.sys          = {
  title        = "SYS",
  pipe_x       = 368, -- "|" column for process/GPU rows (legacy goto 260)
  name_indent  = 4,   -- chars of indent before process names
  name_max     = 26,  -- process name trim (legacy topname 26)
  disk_val_col = 11,  -- char column where disk table values start
  -- Separator dash count lives in theme.sep.count (suite-wide style
  -- dial, same precedent as theme.slash.count) — was duplicated here
  -- as a dead constant frame.lua never read from theme.
}

-- NET — interface/WAN/LAN/DNS rows, pings, VLAN gateway list,
-- live throughput graphs
panels.net          = {
  title       = "NET",
  -- y0 (F3, 2026-08-29): fixed chassis-relative baseline for NET's
  -- first line, replacing a threaded cursor handed off from SYS.
  -- Before this, draw_monitor ran draw_sys_content and passed its
  -- returned end-of-content cursor into draw_net_content, so NET's
  -- vertical origin was emergent — wherever SYS's text flow happened
  -- to end. mon.disk_rows() turned out NOT to be the live hazard the
  -- scan named (it returns a fixed 2 rows from a hardcoded label list
  -- regardless of what's actually mounted — verified live, see the
  -- runbook), but the coupling itself was still real: SYS's line
  -- count also depends on gpu_present() (5 lines vs 1) and on
  -- top_cpu_rows/top_mem_rows returning fewer than 5 on a
  -- near-idle box, either of which would silently move NET with no
  -- visible cause. Every other combined chassis in this suite
  -- (ambient: wxr+orb+tme; media: msc+lyrics) gives each sub-element
  -- its own fixed, measured position — draw_ambient/draw_media call
  -- their content functions independently, no cursor threading
  -- anywhere else. Monitor's threading was the outlier, not the
  -- convention. Value measured (not guessed): ran draw_sys_content's
  -- exact line sequence against this machine's live caches (GPU
  -- present, 5 top_cpu + 5 top_mem + 2 disk rows) — SYS's content
  -- ends at cursor y 921, plus the 4-line gap NET's header used to
  -- open with (now folded into this fixed value instead of a
  -- draw-time nl() x4) = 1013. Preserves today's "NET follows
  -- immediately after SYS" visual relationship as a snapshot, same
  -- as legacy's own fixed 750px sys-info/net-sys offset — just
  -- measured against this port's grid instead of legacy's.
  y0          = 1013,
  value_x     = 262, -- value column (legacy goto 185)
  vlan_gw_col = 14,  -- char col of "Gateway:" (legacy "%-13s " name field)
  vlan_ip_col = 23,  -- char col of the gateway IP
  vlan_ms_col = 36,  -- char col of the "(N ms)" rtt
  -- graph.width (500) is a literal, NOT derived from
  -- layout.monitor.frame.width (568) — F1 decision (2026-08-29), carried
  -- forward from the prior session's tuning pass (531 -> 500, commit
  -- e09c875), which already deliberately broke this value's former
  -- coincidental equality with lua/suite/monitor_helpers.lua's TP.maxlen
  -- (the throughput ring-buffer sample count, still 531). Confirmed by
  -- re-reading draw_net_content: the buffer can safely hold MORE samples
  -- than the graph draws (older samples just compute an off-panel x and
  -- get skipped), so a wider buffer than the drawn width is harmless —
  -- only a graph WIDER than the buffer would show a permanently blank
  -- strip on the left. Deriving graph.width from the frame was rejected
  -- for two reasons: (1) no clean formula ties either 500 or 531 to 568
  -- (both were tuned by eye, not computed), and (2) monitor_helpers.lua is
  -- a pure data view model that never loads theme/panels.lua (Phase 4 of
  -- the conversion guide keeps data and presentation separate) — wiring
  -- it to panels.lua would cross that line for one constant. If the frame
  -- widens enough that someone wants a wider graph, raise this value AND
  -- TP.maxlen together by hand; they are related by convention, not code.
  graph       = { x = 5, width = 500, height = 112 },
}

----------------------------------------------------------------
-- AMBIENT CHASSIS  (layout.ambient.frame, top_middle)
-- Legacy vertical stack (all coordinates chassis-relative; the
-- chassis top sits at the legacy date-time gap_y=40 position):
--   clock stack   y   0..90   (legacy date-time widget)
--   weather block y  90..745  (legacy weather widget; its internal
--                              offsets are relative to arc center at
--                              y = 90 + 204 = 294, matching legacy
--                              weather.center.y = 204)
-- The calendar is a standalone top_right window (panels.cal),
-- matching the legacy suite — it does not live in this chassis.
--
-- WXR/ORB/TME all derive their width from AMBIENT_W (2026-08-29, F1
-- fix — same pattern commit 2f7573c used for the media chassis) instead
-- of each repeating a hardcoded 680. This closes the gap the compliance
-- scan flagged: panels.msc.arc references panels.orb.arc by value at
-- load time, and the "music arc axis renders at the same x as the
-- ambient arc axis" mirror only holds if BOTH chassis center on
-- width/2 of their OWN frame. Media already tracked its frame
-- automatically; now ambient does too, so resizing
-- layout.ambient.frame.width keeps the mirror aligned instead of
-- silently breaking it. Verified live: temporarily widened
-- layout.ambient.frame.width, relaunched clean-ambient + clean-media,
-- confirmed the ORB and MSC arc axes stayed at the same abs x as each
-- other (just moved together), then reverted.
----------------------------------------------------------------

local AMBIENT_W     = layout.ambient.frame.width

-- WXR — current conditions in arc interior, forecast tiles, METAR, TAF.
-- All main-block offsets are pixels from the ORB arc center (legacy
-- theme.weather.main convention).
panels.wxr          = {
  title = "WXR",
  x = 0,
  y = 90,
  width = AMBIENT_W,
  height = 680,
  -- Main block: current icon + city + temp + humidity inside the arc.
  -- Offsets from arc center — legacy theme.weather.main values.
  main = {
    icon_size   = 90,
    icon_dx     = -65,
    icon_dy     = -30,
    city_dx     = 0,
    city_dy     = -120,
    city_pt     = 12,
    temp_dx     = 15,
    temp_dy     = -28,
    temp_pt     = 44,
    humidity_dx = 26,
    humidity_dy = 0,
    humidity_pt = 20,
  },
  -- Divider lines — legacy theme.weather.hline / vline (dy/dx from arc center)
  hline = { length = 460, width = 0.5, dy = 58 },
  vline = { length = 100, width = 0.5, dx = 0, dy = -80 },
  -- Forecast tile strip — legacy theme.weather.forecast.
  -- origin.y is relative to the weather block top (panel.y).
  forecast = {
    origin_y = 270, -- legacy origin.y 265 + dy 5
    tiles    = 5,
    tile_w   = 64,
    gap      = 22,
    date     = { pt = 14, dy = 0 },
    icon     = { size = 34, dy = 46 },
    temps    = { pt = 22, dy = 98 },
  },
  -- Aviation text blocks. y is relative to the weather block top;
  -- wrap/pad values are the legacy theme.weather.metar/taf values.
  aviation = {
    font_px = 16, -- aviation text size (px)
    line_px = 22, -- line spacing
    -- Shared x nudge for metar/taf (and advisories, once drawn). Base x is
    -- anchored to hline's left edge (cx - hline.length/2), independent of
    -- wrap_col, so re-wrapping the text never moves the block; dx is a pure
    -- fine-tune from that anchor. 0 lines up exactly with hline as-is.
    dx = 0,
    metar = {
      y         = 455,
      wrap_col  = 46,
      max_lines = 5,
    },
    taf = {
      y           = 585,
      wrap_col    = 55,
      max_lines   = 4,
      indent_cols = 5,
    },
    advisories = {
      enabled   = false, -- off in legacy theme as well
      wrap_col  = 42,
      max_lines = 3,
    },
  },
}

-- ORB — horizon arc with sun, moon, and visible planets.
-- Arc geometry is the legacy theme.weather.arc / center convention:
-- center_mode auto_x, center y = panel.y + dy.
panels.orb          = {
  title = "ORB",
  x = 0,
  y = 90,
  width = AMBIENT_W,
  height = 400,
  arc = {
    center_mode   = "auto_x",
    center_offset = { x = 0, y = 0 },
    r             = 170,
    start         = 180, -- West (left end)
    ["end"]       = 0,   -- East (right end)
    dy            = 204, -- arc center below panel top (legacy center.y)
  },
  horizon_labels = {
    pt = 12,
    dy = 24, -- below arc endpoints (legacy horizon_labels.dy)
  },
  sun_time_labels = {
    pt           = 14,
    dy           = 44,   -- below arc endpoints (legacy sun_time_labels.dy)
    sunrise_text = "SR", -- final legacy theme values (older
    sunset_text  = "SS", -- screenshots show "Sunrise"/"Sunset")
  },
}

-- TME — clock stack at chassis top.
panels.tme          = {
  title = "TME",
  x = 0,
  y = 0,
  width = AMBIENT_W,
  height = 770,
  boxes = {
    -- Clock stack, centered on chassis width (legacy date-time widget):
    -- local %H:%M:%S, UTC line, YYYY.MM.DD line.
    clock = { x = 0, y = 0, width = AMBIENT_W, height = 90 },
  },
  clock = {
    time_px = 30, -- legacy font_time 22pt ≈ 30px
    gmt_px  = 14, -- legacy font_gmt 10pt ≈ 13.3px
    date_px = 16, -- legacy font_date 12pt ≈ 16px
    gap_px  = 6,  -- legacy voffset 4 between lines
  },
}

----------------------------------------------------------------
-- CALENDAR STANDALONE  (layout.calendar.frame)
-- Legacy calendar.conky.conf ran as its own top_right window on
-- head 1; kept standalone here for the same reason (its position
-- is disjoint from the ambient chassis footprint).
----------------------------------------------------------------

local CAL_FRAME     = layout.calendar.frame

-- CAL — month grid with nav-arrow title, weekday header, weekend
-- gray, today in accent. Legacy theme.lua cal_* geometry. Box equals
-- layout.calendar's frame at (0,0), derived (2026-08-29, F1 fix) —
-- same standalone-widget pattern as notes/pfsense.
panels.cal          = {
  title = "CAL",
  x = 0,
  y = 0,
  width = CAL_FRAME.width,
  height = CAL_FRAME.height,
  calendar = {
    cell_w       = 50,
    cell_h       = 32,
    col_gap      = 2,
    row_gap      = 3,
    border_lw    = 0, -- legacy cal_border_lw 0 (borderless; see calendar.png)
    title_size   = 20,
    weekday_size = 14,
    day_size     = 16,
    title_h      = 30,
    title_gap    = 18,
    header_h     = 18,
    -- Grid line / weekend-day colors live in theme.cal (palette roles
    -- cal_grid/cal_weekend) — this is geometry, not style (same
    -- precedent as panels.sys's sep_count note above).
  },
}

----------------------------------------------------------------
-- MEDIA CHASSIS  (layout.media.frame, top_middle)
-- One top_middle window covering both legacy windows' measured
-- rendered footprints — see layout.media for the window math.
--
-- Width-independent anchoring: with a top_middle window, widening
-- the frame moves window_left by −ΔW/2 while the frame center moves
-- +ΔW/2 — so anything positioned relative to MEDIA_W/2 stays put on
-- screen no matter the frame width. panels.msc is full-width (arc
-- axis = width/2) and panels.lyrics.x is anchored to the axis, so
-- resizing layout.media.frame only changes edge headroom (e.g. more
-- right-edge room before the window clips wide lyric lines).
----------------------------------------------------------------

local MEDIA_W       = layout.media.frame.width

-- MSC — now-playing "smile" arc, album art, markers, title/album/artist.
--
-- DERIVED GEOMETRY — deliberate legacy relationship, preserved by
-- reference (2026-08-28): the legacy music widget mirrors the weather
-- arc exactly — legacy music.lua's get_arc_geometry_weather() read
-- theme.weather.* (center auto_x, center.y, arc r/start/end) at draw
-- time; theme.music.arc's own r=140/200→-20 values were dead config
-- and are deliberately NOT carried forward. The arc fields below
-- REFERENCE panels.orb.arc (and the baseline length references
-- panels.wxr.hline) instead of repeating numbers, so a future
-- ambient-arc retune propagates here automatically on reload.
-- The arc center x is panel.width/2 (legacy center_mode auto_x): with
-- the chassis top_middle and this panel full-width, the music arc axis
-- renders at the same x as the ambient arc axis (both use the shared
-- panel-width/2 convention; measured 5755 physical for both).
panels.msc          = {
  title              = "MSC",
  x                  = 0,
  y                  = 326,     -- arc center abs y 938 = window_top 408 + y + arc.dy
  width              = MEDIA_W, -- full frame width: arc axis = width/2 lands at abs 1915
  -- (head-rel) for ANY frame width — same rendered x as
  -- the ambient arc axis (panel-width/2 convention)
  height             = 400,   -- same arc band height as panels.orb
  hide_when_inactive = false, -- legacy: music widget always visible
  idle_hide_after_s  = 10,
  inactive_message   = "Play music, feel better",
  arc                = {
    -- Mirrored smile: same values as the horizon arc, by reference.
    r       = panels.orb.arc.r,
    start   = panels.orb.arc.start,  -- 180 = left endpoint (elapsed side)
    ["end"] = panels.orb.arc["end"], -- 0 = right endpoint (remaining side)
    dy      = panels.orb.arc.dy,     -- center-y below panel top (legacy weather.center.y)
  },
  baseline           = {
    dy     = -45,                             -- HR line above arc center (legacy music.baseline.dy)
    length = panels.wxr.hline.length,         -- 460 — mirrors the weather hline, by reference
  },
  time_labels        = { pt = 18, dy = -18 }, -- baselines above arc center (legacy music.time_labels)
  marker             = { d = 20 },            -- progress dot (palette accent)
  volume_marker      = { d = 16 },            -- red by fixed convention (theme.msc)
  -- Idle bar animation: present in the legacy code but disabled in the
  -- final legacy theme (animate_idle = false; music2.png shows it on).
  -- Kept implemented + disabled for easy revival, pfSense-baseline style.
  bars               = {
    animate_idle = false,
    count        = 48,
    width        = 6,
    max_height   = 68,
    lift_px      = 48,
    speed        = 2, -- px per second of phase advance (legacy speed_px_u)
  },
  -- Album art box, centered on the arc axis, aspect-fit. The legacy
  -- theme's art placement (62×60 at arc-center −13) never matched what
  -- ${image} actually rendered (measured 2026-08-28: -p/-s were not
  -- honored as configured; accepted screenshots show ~88px art seated
  -- in the arc bowl between the album and artist lines). The Cairo
  -- port draws that accepted composition deterministically.
  art                = { dy = 68, w = 88, h = 88 }, -- box center at arc-center + dy
  text               = {
    -- Baselines relative to the ARC CENTER (legacy passed arc cy, not
    -- the art anchor, into draw_line_with_marquee); centered on the
    -- arc axis; marquee when wider than field_w (speed = px/second,
    -- legacy speed_px_u at update_interval 1).
    title  = { pt = 15, dy = -6, field_w = 250, speed = 18 },
    album  = { pt = 11, dy = 18, field_w = 280, speed = 4 },
    artist = { pt = 14, dy = 128, field_w = 200, speed = 12 },
  },
}

-- NOTES — sticky notes from flat text file.
-- Standalone top_right window (panels.notes + layout.notes), matching
-- the legacy suite — it does not live in the media chassis.
-- Grid metrics measured off the running legacy widget (DejaVu Sans
-- Mono, Xft size=9 at this machine's DPI): 20.0 px line pitch over
-- 85 lines, 10.0 px char advance (39-char fold width spans 390 px).
-- width/height derive from layout.notes.frame (2026-08-29, F1 fix) —
-- confirmed by reading draw_notes_content that neither field is
-- actually read by the drawing code today (it only uses panel.x/y and
-- panel.grid.*); kept as derived rather than deleted so the box stays
-- an accurate mirror of the window's real size if a future draw path
-- needs it, instead of a stale hardcoded pair silently drifting from
-- layout.notes.frame the way it already had (404×1810 vs the frame's
-- own 404×1810 — currently equal by luck, not by construction).
panels.notes        = {
  title      = "NOTES",
  x          = 0,
  y          = 0,
  width      = layout.notes.frame.width,
  height     = layout.notes.frame.height,
  wrap_chars = 39,         -- fold -s -w 39 (legacy notes_wrap)
  max_lines  = 90,         -- sed -n 1,90p  (legacy notes_lines)
  refresh_s  = 3,          -- legacy execi 3
  grid       = {
    x0             = 7,    -- left text margin in frame
    first_baseline = 21,   -- baseline of line 1
    line_px        = 20,   -- vertical advance per text line
    font_px        = 16.6, -- mono font size (px); advance 10.0 px
  },
}

-- LYRICS — current-track lyrics from the CORE media domain
-- (shared/media/[profile]/lyrics.json; no suite-side fetching — see
-- lua/suite/msc.lua and gtex62-core/docs/lyrics-library-design.md).
-- LRC timestamps are stripped provider-side, so the legacy
-- strip_lrc_timestamps flag has no suite-side equivalent anymore.
-- Position reproduces the measured rendered position of the running
-- legacy music-lyrics window (2026-08-28: window at physical (6201,413)
-- sized 795×1324, text left 6211, header baseline 441 — the conf's
-- gap −600,300 / 560×940 were NOT the rendered truth, same pitfall as
-- calendar/notes/monitor). x is anchored to the arc axis (MEDIA_W/2 +
-- 446; 446 = measured text-left 2371 head-rel − axis 1915 − pad 10),
-- so the column stays put at any frame width. Long lines clip at the
-- window's right edge — frame width is sized so that capacity matches
-- the legacy window's (~785 px from text left; see layout.media).
panels.lyrics       = {
  title              = "LYRICS",
  x                  = MEDIA_W / 2 + 446,
  y                  = 5,
  width              = 780,  -- informational: the legacy window's usable line width
  height             = 1324, -- legacy rendered window height; sets max body lines
  hide_when_inactive = true, -- legacy theme.lyrics (10 s linger after stop)
  idle_hide_after_s  = 10,
  max_blank_run      = 1,    -- collapse blank-line runs (legacy normalize_blank_lines)
  padding            = { left = 10, top = 10, right = 10, bottom = 10 },
  header             = {
    enabled = true, -- "{artist} — {title}" from the live player
    pt      = 18,
    bold    = true,
  },
  body               = {
    pt      = 14,
    line_px = 16,
  },
  more_marker        = "…more…",
  show_saved_path    = true, -- footer when the track was fetched online this cycle
  saved_prefix       = "Saved to: ",
  messages           = {
    inactive     = "Lyrics can make the song, don't you think?",
    offline      = "Offline",
    not_found    = "Lyrics not found",
    instrumental = "Instrumental",
    searching    = "Searching…", -- provider hasn't caught up to a track change yet
  },
}

----------------------------------------------------------------
-- PFSENSE STANDALONE  (layout.pfsense.frame, 840 × 500)
-- VLAN traffic flow arc visualization only (conversion guide §1.4).
-- CPU/MEM meters, gateway label, nameplate, totals, pfBlockerNG /
-- Pi-hole / AP status are all retired to the core sitrep utility.
-- CAM (igc1.50) is new vs the legacy 5-arc widget — the VLAN was
-- added after the legacy suite froze; the core provider serves it.
----------------------------------------------------------------

local PF_FRAME      = layout.pfsense.frame

panels.pfsense      = {
  -- Box equals layout.pfsense's frame at (0,0), DERIVED — the
  -- standalone-widget pattern (same as panels.cal / notes). Until
  -- 2026-08-29 this comment asserted a derivation that didn't exist:
  -- width/height were a hardcoded 840×500 copy that happened to still
  -- match the frame after its post-verify retune (660×520 -> 840×500
  -- around the user-tuned r=400 dome) — exactly the kind of silent
  -- divergence the runbook already recorded once causing an
  -- off-center bug when two boxes for the same window drifted apart.
  -- Now width/height read PF_FRAME directly, so the assertion is
  -- enforced by code, not by remembering to update both places.
  -- The dome self-centers: arc center x is width/2, so it stays
  -- centered at any frame width. Headroom is implicit: side =
  -- width/2 − arc.r, top = arc.dy − arc.r. Keep both ≥ 14px or the
  -- markers (12px radius, riding ON the arc line) clip at the window
  -- edge at idle/full-scale positions.
  x = 0,
  y = 0,
  width = PF_FRAME.width,
  height = PF_FRAME.height,

  -- Arc geometry (concentric dome arcs, outermost = WAN).
  -- Note the legacy theme said r=380, but its 640px window clamped the
  -- rendered radius to ~312 — the theme value never drew; r here is
  -- sized to taste with the frame sized around it.
  arc = {
    dy              = 424, -- arc center below panel top (= r + 24px apex headroom)
    r               = 400, -- outermost arc radius (WAN); keep ≤ width/2 − 14
    width           = 2,   -- base arc stroke
    delta_r         = 36,  -- radial gap between concentric arcs
    anchor_strength = 0.5, -- 0=concentric, 1=apex-anchored (legacy 0.5)
  },

  -- Interface order (outermost to innermost)
  iface_order = { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" },

  -- DN/UP labels at the outermost arc's base endpoints
  labels = {
    size     = 12,
    dx_left  = -8,
    dy_left  = 30,
    dx_right = -8,
    dy_right = 30,
    text_in  = "DN",
    text_out = "UP",
  },

  -- Arc name labels: dash leader + name, drawn inward from each arc's
  -- left endpoint ("-----WAN"). dash_count grows inward so the names
  -- roughly align; CAM extends the legacy 14..34 progression.
  arc_names = {
    enabled   = true,
    dash_char = "-",
    dx        = 5,
    dy        = 5,
    size      = 16, -- legacy arc_names size
    per_arc   = {
      WAN   = { dash_count = 14, text = "WAN" },
      HOME  = { dash_count = 18, text = "HOME" },
      IOT   = { dash_count = 26, text = "IoT" },
      GUEST = { dash_count = 28, text = "GUEST" },
      INFRA = { dash_count = 34, text = "INFRA" },
      CAM   = { dash_count = 36, text = "CAM" }, -- capped so the name clears CAM's resting OUT ring
    },
  },

  -- Static scale label under the arc apex
  top_label = {
    enabled = true,
    text    = "100%",
    -- Legacy dy 94 assumed 5 arcs; the 6th (CAM) arc's apex sits lower,
    -- so 116 keeps the same ~22px clearance below the innermost apex.
    dy      = 116,
    size    = 12,
  },

  -- Marker shape shared across arcs (per-VLAN color/radius in
  -- theme.pf_markers; IN is filled, OUT is a hollow ring)
  marker = { out_stroke = 3 },

  -- Baseline under the dome (legacy pf.hline) — dropped by choice:
  -- with the status text that hung off it retired to sitrep, the
  -- bare line wasn't earning its place. Flip enabled to bring it back.
  baseline = {
    enabled = false,
    dy      = 50,  -- below arc center (legacy pf.hline.dy)
    width   = 1,
    length  = 800, -- full panel width, flush with the dome ends
  },

  -- Rate → arc-fraction response (ported legacy scale block: sqrt
  -- curve, per-direction link caps in Mbps, no idle floors).
  -- CAM caps are new: 100/100 matching the other internal VLANs.
  scale = {
    mode = "sqrt",
    sqrt = { gamma = 0.35 },
    floors_mbps = {},
  },
  link_mbps_in = {
    WAN   = 600,
    HOME  = 100,
    IOT   = 100,
    GUEST = 50,
    INFRA = 100,
    CAM   = 100,
  },
  link_mbps_out = {
    WAN   = 50,
    HOME  = 100,
    IOT   = 100,
    GUEST = 100,
    INFRA = 100,
    CAM   = 100,
  },

  -- Smoothing (EMA) applied to the scaled fraction
  smoothing = { alpha = 0.35 },
}

return panels
