-- panels.lua
-- Per-panel position, size, title, and sub-box geometry for gtex62-clean-suite-e.
-- All coordinates are relative to the chassis frame origin (0, 0).
-- Chassis outer dimensions are in clean-layout.lua.
--
-- Box coordinates are relative to their parent panel origin.
-- "title" is the label drawn in the panel header row.

local panels = {}

----------------------------------------------------------------
-- MONITOR CHASSIS  (420 × 1060)
----------------------------------------------------------------

-- SYS — CPU / RAM / GPU / top processes
panels.sys = {
  title  = "SYS",
  x = 18, y = 24, width = 384, height = 500,
  boxes = {
    cpu       = { x = 12, y =  60, width = 360, height = 160 }, -- slash bars + top label
    ram       = { x = 12, y = 234, width = 360, height =  60 },
    gpu       = { x = 12, y = 306, width = 360, height =  60 },
    processes = { x = 12, y = 380, width = 360, height = 108 }, -- top-5 process rows
  },
}

-- NET — interface, WAN IP, throughput graph, VLAN gateway status
panels.net = {
  title  = "NET",
  x = 18, y = 542, width = 384, height = 494,
  boxes = {
    iface  = { x = 12, y =  48, width = 360, height =  40 }, -- iface name + IP
    wan    = { x = 12, y =  96, width = 360, height =  40 }, -- WAN IP
    graph  = { x = 12, y = 148, width = 360, height =  80 }, -- up/down graph
    status = { x = 12, y = 244, width = 360, height = 220 }, -- VLAN gateway rows
  },
}

----------------------------------------------------------------
-- AMBIENT CHASSIS  (680 × 820)
----------------------------------------------------------------

-- WXR — current conditions, forecast strip, METAR, TAF
panels.wxr = {
  title  = "WXR",
  x = 18, y = 24, width = 644, height = 390,
  boxes = {
    main     = { x = 12, y =  44, width = 620, height = 220 }, -- icon + arc + current
    forecast = { x = 12, y = 274, width = 620, height = 104 }, -- 6-day tile strip
  },
  -- Aviation sub-blocks are drawn inline below the forecast strip
  -- with their own wrap/pad config in the wxr view model.
  aviation = {
    metar = {
      wrap_col  = 43,
      pad_cols  = 15,
      max_lines =  5,
    },
    taf = {
      wrap_col    = 60,
      pad_cols    = 15,
      max_lines   =  4,
      indent_cols =  5,
    },
    advisories = {
      enabled   = false, -- off by default; enable in site config if needed
      wrap_col  = 42,
      pad_cols  = 16,
      max_lines =  3,
    },
  },
}

-- ORB — horizon arc with sun, moon, and visible planets
panels.orb = {
  title  = "ORB",
  x = 18, y = 432, width = 644, height = 220,
  -- Arc geometry relative to panel center.
  -- center_mode = "auto_x" keeps the arc horizontally centered
  -- on the panel regardless of width changes.
  arc = {
    center_mode   = "auto_x",
    center_offset = { x = 0, y = 0 },
    r             = 170,
    start         = 180,
    ["end"]       = 0,
    dy            = 90,   -- vertical offset of arc center from panel top
  },
  horizon_labels = {
    pt    = 12,
    dy    = 24,   -- below arc
  },
  sun_time_labels = {
    pt    = 14,
    dy    = 44,
    sunrise_text = "SR",
    sunset_text  = "SS",
  },
}

-- TME — local clock, UTC, date, month calendar
panels.tme = {
  title  = "TME",
  x = 18, y = 670, width = 644, height = 126,
  boxes = {
    clock    = { x = 12, y =  36, width = 300, height =  72 }, -- local + UTC clocks
    date     = { x = 12, y =  36, width = 300, height =  24 }, -- date line (below clock)
    calendar = { x = 328, y = 10, width = 304, height = 112 }, -- month grid alongside
  },
  -- Calendar cell geometry (drawn by tme.lua via panels.tme.calendar.*)
  calendar = {
    week_start = "SU",
    cell_w     = 40,
    cell_h     = 28,
    col_gap    =  2,
    row_gap    =  3,
    title_h    = 26,
    title_gap  = 14,
  },
}

----------------------------------------------------------------
-- MEDIA CHASSIS  (580 × 1300)
----------------------------------------------------------------

-- MSC — now-playing arc, album art, bars, title/artist/album
panels.msc = {
  title  = "MSC",
  x = 18, y = 24, width = 544, height = 290,
  hide_when_inactive = false,
  idle_hide_after_s  = 10,
  -- Arc geometry relative to panel center
  arc = {
    center_mode = "auto_x",
    dy          = 50,    -- smile arc offset (pushes arc downward)
    r           = 140,
    start       = 200,
    ["end"]     = -20,
  },
  bars = {
    count      = 48,
    width      =  6,
    max_height = 68,
    lift_px    = 48,
    animate_idle = false,
  },
  -- Album art relative to arc anchor center
  art = {
    dx =  0,
    dy = -13,
    w  = 62,
    h  = 60,
  },
  text = {
    title  = { pt = 15, dy =  -6, field_w = 250 },
    album  = { pt = 11, dy =  18, field_w = 280 },
    artist = { pt = 14, dy = 128, field_w = 200 },
  },
}

-- NOTES — sticky notes from flat text file
panels.notes = {
  title  = "NOTES",
  x = 18, y = 332, width = 544, height = 580,
  wrap_chars    = 72,   -- characters per line before wrapping
  max_lines     = 38,   -- maximum lines to display
  line_px       = 14,   -- vertical spacing per line
}

-- LYRICS — current track lyrics
panels.lyrics = {
  title  = "LYRICS",
  x = 18, y = 930, width = 544, height = 346,
  hide_when_inactive    = true,
  idle_hide_after_s     = 10,
  normalize_blank_lines = true,
  max_blank_run         = 1,
  strip_lrc_timestamps  = true,
  padding = { left = 10, top = 10, right = 10, bottom = 10 },
  header = {
    enabled = true,
    format  = "{artist} — {title}",
    pt      = 14,
    bold    = true,
  },
  body = {
    pt      = 12,
    line_px = 15,
  },
}

----------------------------------------------------------------
-- PFSENSE STANDALONE  (660 × 520)
-- VLAN flow arc visualization only.
-- pfBlockerNG / Pi-hole / AP / totals are in the core sitrep utility.
----------------------------------------------------------------
panels.pfsense = {
  title   = "FLOW",
  x = 18, y = 24, width = 624, height = 492,

  -- Arc geometry (concentric arcs for WAN / HOME / IOT / GUEST / INFRA)
  arc = {
    -- Center is auto-computed from frame width; dy positions it vertically.
    center_mode   = "auto_x",
    dy            = 300,        -- pixels from panel top to arc center
    r             = 300,        -- outermost arc radius (WAN)
    start         = 180,
    ["end"]       = 0,
    width         = 2,          -- base arc stroke
    delta_r       = 36,         -- radial gap between concentric arcs
    anchor_strength = 0.5,      -- 0=concentric, 1=apex-anchored
  },

  -- Interface order (outermost to innermost)
  iface_order = { "WAN", "HOME", "IOT", "GUEST", "INFRA" },

  -- Arc end labels
  labels = {
    size     = 12,
    dx_left  =  -8,
    dy_left  =  30,
    dx_right =  -8,
    dy_right =  30,
    text_in  = "DN",
    text_out = "UP",
  },

  -- Arc name labels (dash leader + name at left endpoints)
  arc_names = {
    enabled   = true,
    dash_char = "-",
    dash_gap  =  0,
    dx        =  5,
    dy        =  5,
    size      = 14,
    per_arc   = {
      WAN   = { dash_count = 14, text = "WAN"   },
      HOME  = { dash_count = 18, text = "HOME"  },
      IOT   = { dash_count = 26, text = "IoT"   },
      GUEST = { dash_count = 28, text = "GUEST" },
      INFRA = { dash_count = 34, text = "INFRA" },
    },
  },

  -- Top-of-arc static label
  top_label = {
    enabled = true,
    text    = "100%",
    dy      = 80,      -- below arc apex (px)
    size    = 12,
  },

  -- Center meters (CPU% and MEM% vertical bars under the apex)
  center_meters = {
    enabled  = true,
    dx       =   0,
    dy       = -200,   -- upward from arc center
    height   = 100,
    width    =  50,
    gap      =  40,
    label_size = 14,
    cpu_label  = "CPU%",
    mem_label  = "MEM%",
  },

  -- Nameplate (pfSense model/version, static text)
  nameplate = {
    enabled = true,
    text    = "V1211",
    dy      =  15,
    size    =  13,
  },

  -- Gateway status (ONLINE / OFFLINE)
  gateway_label = {
    enabled   = true,
    size      = 15,
    dy        = 12,   -- above baseline
    text_ok   = "ONLINE",
    text_bad  = "OFFLINE",
  },

  -- Smoothing (EMA) for displayed rates
  smoothing = { alpha = 0.35 },
}

return panels
