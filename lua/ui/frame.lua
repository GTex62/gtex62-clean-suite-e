---@diagnostic disable: undefined-global
-- lua/ui/frame.lua
-- Cairo frame renderer for gtex62-clean-suite-e.
-- Four chassis entry points: draw_monitor, draw_ambient, draw_media, draw_pfsense.
-- All panel coordinates are chassis-relative (0,0) origin — no layout.frame offset.

local M = {}

----------------------------------------------------------------
-- Cairo primitive helpers
----------------------------------------------------------------

local function set_rgb(cr, c)
  cairo_set_source_rgb(cr, c[1], c[2], c[3])
end

local function fill_rect(cr, x, y, w, h, c)
  set_rgb(cr, c)
  cairo_rectangle(cr, x, y, w, h)
  cairo_fill(cr)
end

local function draw_rect(cr, x, y, w, h, lw, c)
  cairo_set_line_width(cr, lw)
  set_rgb(cr, c)
  cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1, h - 1)
  cairo_stroke(cr)
end

local function clamp01(v)
  return math.max(0, math.min(1, tonumber(v) or 0))
end

----------------------------------------------------------------
-- Text helpers
----------------------------------------------------------------

local function draw_text_left(cr, x, y, txt, face, pt, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, pt)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, txt)
end

local function draw_text_left_mid(cr, x, y, txt, face, pt, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, pt)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x, y + ext.height / 2)
  cairo_show_text(cr, txt)
end

local function draw_text_center_mid(cr, x, y, txt, face, pt, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, pt)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + ext.height / 2)
  cairo_show_text(cr, txt)
end

local function draw_text_center_mid_alpha(cr, x, y, txt, face, pt, color, alpha, weight)
  if not txt or txt == "" then return end
  cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, pt)
  cairo_set_source_rgba(cr, color[1], color[2], color[3], alpha or 1.0)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + ext.height / 2)
  cairo_show_text(cr, txt)
end

local function draw_text_right_mid(cr, x, y, txt, face, pt, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL, weight or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, pt)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y + ext.height / 2)
  cairo_show_text(cr, txt)
end

local function draw_text_block_left(cr, x, y, lines, face, pt, color, step, weight)
  if type(lines) ~= "table" then return end
  local s = tonumber(step) or pt
  for i, line in ipairs(lines) do
    draw_text_left(cr, x, y + (i - 1) * s, line, face, pt, color, weight)
  end
end

----------------------------------------------------------------
-- Bar and table helpers
----------------------------------------------------------------

local function draw_hbar(cr, x, y, w, h, ratio, color)
  local fw = math.floor(w * clamp01(ratio) + 0.5)
  if fw <= 0 then return end
  fill_rect(cr, x, y, fw, h, color)
end

----------------------------------------------------------------
-- SYS + NET content (Monitor chassis)
--
-- Legacy clean-suite sys-info + net-sys stack rendered as one
-- continuous character-grid text flow (the same layout the accepted
-- conky.text version produced, now drawn in Cairo from the core
-- caches via the monitor_helpers view model). Grid metrics live in
-- panels.monitor_grid; column constants in panels.sys / panels.net.
----------------------------------------------------------------

local function grid_cursor(panels)
  local g = panels.monitor_grid or {}
  return {
    x0      = g.x0 or 7,
    y       = g.first_baseline or 24,
    line_px = g.line_px or 23,
    font_px = g.font_px or 18,
    char_px = g.char_px or 10.85,
  }
end

local function draw_sys_content(cr, theme, panels, data)
  local mon  = data and data.mon
  local sysp = panels.sys
  if not (mon and sysp) then return nil end

  local cur     = grid_cursor(panels)
  local colors  = theme.colors
  local mono    = theme.fonts.mono or "DejaVu Sans Mono"
  local px      = cur.font_px
  local ink, fg = colors.ink, colors.fg

  local slash   = theme.slash or {}
  local sl_n    = tonumber(slash.count) or 20
  local sl_fill = slash.fill_color or colors.accent
  local sl_mt   = slash.empty_color or colors.dim
  local sl_ch   = slash.char or "/"
  local sep_str = string.rep((theme.sep and theme.sep.char) or "-", sysp.sep_count or 50)

  local function col(n) return cur.x0 + n * cur.char_px end
  local function text(x, s, c) draw_text_left(cr, x, cur.y, s, mono, px, c) end
  local function nl(n) cur.y = cur.y + cur.line_px * (n or 1) end
  local function sep()
    text(cur.x0, sep_str, fg); nl()
  end

  -- Slash-bar line: label + fixed-count slash bar + percent (legacy
  -- slash_fixed_auto / pct 3). Bar starts one char after the 3-char label.
  local function slash_line(label, pct)
    local p = tonumber(pct) or 0
    text(cur.x0, label, ink)
    local filled = math.floor(clamp01(p / 100) * sl_n)
    local bx = col(4)
    for i = 1, sl_n do
      draw_text_left(cr, bx + (i - 1) * cur.char_px, cur.y, sl_ch, mono, px,
        (i <= filled) and sl_fill or sl_mt)
    end
    text(bx + (sl_n + 1) * cur.char_px, string.format("%.3f%%", p), fg)
    nl()
  end

  -- Indented name + pipe-column value row (legacy top-process rows)
  local function pipe_row(name, value, name_ink)
    text(col(sysp.name_indent or 4), name, name_ink and ink or fg)
    text(sysp.pipe_x or 368, "| " .. (value or ""), fg)
    nl()
  end

  -- OS / host header
  text(cur.x0, "Mint", ink)
  text(col(5), mon.os_name(), fg)
  nl()
  local host, user = mon.hostname(), mon.user()
  text(cur.x0, host, ink)
  text(col(#host + 2), user, fg)
  text(col(#host + 2 + #user + 3), "Kernel", ink)
  text(col(#host + 2 + #user + 3 + 7), mon.kernel(), fg)
  nl(2)

  -- Disk table
  local dcol = sysp.disk_val_col or 11
  text(cur.x0, "Disk", ink)
  text(col(dcol), string.format("%7s | %7s | %7s | %s", "Size", "Used", "Avail", "Use%"), ink)
  nl()
  for _, row in ipairs(mon.disk_rows()) do
    text(cur.x0, row.label, ink)
    text(col(dcol), row.values, fg)
    nl()
  end
  sep()
  nl()

  -- CPU: slash bar + top-5 by CPU
  slash_line("CPU", mon.cpu_percent())
  for _, row in ipairs(mon.top_cpu_rows(5, sysp.name_max)) do
    pipe_row(row.name, row.value)
  end
  nl()
  sep()
  nl()

  -- RAM: slash bar + top-5 by resident memory
  slash_line("RAM", mon.ram_percent())
  for _, row in ipairs(mon.top_mem_rows(5, sysp.name_max)) do
    pipe_row(row.name, row.value)
  end
  nl()
  sep()
  nl()

  -- GPU: slash bar + driver/temp/power rows + VRAM bar
  if mon.gpu_present() then
    slash_line("GPU", mon.gpu_percent())
    pipe_row("Driver", mon.gpu_driver())
    pipe_row("Temp", string.format("%d°C", math.floor(mon.gpu_temp() + 0.5)))
    pipe_row("Power", string.format("%.2f W", mon.gpu_power()))
    slash_line("VRM", mon.vram_percent())
  else
    slash_line("GPU", 0)
  end
  sep()
  nl()

  -- Hardware id footer
  for _, row in ipairs({
    { "CPU",  mon.cpu_model() },
    { "GPU",  mon.gpu_model() },
    { "MBD",  mon.mbd() },
    { "BIOS", mon.bios() },
  }) do
    text(cur.x0, row[1], ink)
    text(col(5), row[2], fg)
    nl()
  end
  nl()
  sep()

  return cur
end

local function draw_net_content(cr, theme, panels, data, cur)
  local mon  = data and data.mon
  local netp = panels.net
  if not (mon and netp and cur) then return end

  local colors          = theme.colors
  local mono            = theme.fonts.mono or "DejaVu Sans Mono"
  local px              = cur.font_px
  local ink, fg, accent = colors.ink, colors.fg, colors.accent
  local sep_str         = string.rep((theme.sep and theme.sep.char) or "-",
    (panels.sys and panels.sys.sep_count) or 50)
  local right_x         = (panels.monitor_grid and panels.monitor_grid.x0 or 7)
      + ((panels.sys and panels.sys.sep_count or 50) + 4) * cur.char_px

  local function col(n) return cur.x0 + n * cur.char_px end
  local function text(x, s, c) draw_text_left(cr, x, cur.y, s, mono, px, c) end
  local function nl(n) cur.y = cur.y + cur.line_px * (n or 1) end
  local function sep()
    text(cur.x0, sep_str, fg); nl()
  end

  -- Label at x0 (ink) + value at the legacy goto column (fg)
  local function kv(label, value)
    text(cur.x0, label, ink)
    text(netp.value_x or 262, value or "—", fg)
    nl()
  end

  nl()
  nl()
  nl()
  nl()

  -- Header: suite nameplate + updated clock (right-aligned pair)
  text(cur.x0, "GOnion Network", ink)
  local updated = mon.net_updated()
  local upd_lbl = "Updated: "
  draw_text_left(cr, right_x - (#upd_lbl + #updated) * cur.char_px, cur.y, upd_lbl, mono, px, ink)
  draw_text_left(cr, right_x - #updated * cur.char_px, cur.y, updated, mono, px, fg)
  nl()
  sep()
  nl()

  kv("Network Interface:", mon.net_iface_title())
  nl()
  kv("WAN Status:", mon.net_wan_status())
  kv("WAN IP:", mon.net_wan_ip())
  kv("LAN Status:", mon.net_lan_status())
  kv("LAN IP Address:", mon.net_lan_ip())
  nl()
  kv("DNS Server:", mon.net_dns())
  kv("Subnet Mask:", mon.net_subnet())
  nl()

  text(cur.x0, "Pings:", ink)
  nl()
  kv("1.1.1.1", mon.net_ping("1.1.1.1"))
  kv("8.8.8.8", mon.net_ping("8.8.8.8"))
  nl()

  -- VLAN gateway rows; the home VLAN's IP gets the accent color
  text(cur.x0, "VLAN Gateways:", ink)
  nl()
  local vlan_rows = mon.net_vlan_rows()
  if #vlan_rows == 0 then
    text(cur.x0, "VLAN data unavailable", ink)
    nl()
  end
  for _, row in ipairs(vlan_rows) do
    text(cur.x0, row.name, ink)
    text(col(netp.vlan_gw_col or 13), "Gateway:", ink)
    text(col(netp.vlan_ip_col or 22), row.gateway, row.is_home and accent or fg)
    text(col(netp.vlan_ms_col or 35), row.rtt, fg)
    nl()
  end
  sep()
  nl()

  -- Live throughput: rate lines + bordered histogram graphs
  -- (legacy ${upspeedgraph}/${downspeedgraph} look, fg on transparent)
  text(cur.x0, "Live Throughput", ink)
  nl(2)

  local g  = netp.graph or {}
  local gx = g.x or 5
  local gw = g.width or 531
  local gh = g.height or 112
  local tp = mon.throughput()

  local function graph_block(hist)
    local top = cur.y - cur.font_px + 2
    draw_rect(cr, gx, top, gw, gh, 1, fg)
    local n = #hist
    local vmax = 1.0
    for i = 1, n do
      if hist[i] > vmax then vmax = hist[i] end
    end
    for i = 1, n do
      local x = gx + gw - 1 - (n - i)
      if x > gx then
        local bh = math.floor((gh - 2) * clamp01(hist[i] / vmax) + 0.5)
        if bh > 0 then
          fill_rect(cr, x, top + gh - 1 - bh, 1, bh, fg)
        end
      end
    end
    cur.y = top + gh + cur.line_px
  end

  kv("Up", string.format("%.1f KiB/s", tp.up))
  graph_block(tp.up_hist)
  kv("Down", string.format("%.1f KiB/s", tp.down))
  graph_block(tp.down_hist)
end

----------------------------------------------------------------
-- WXR content (Ambient chassis)
----------------------------------------------------------------

-- Shared-assets OWM icon directory (legacy suite carried its own copy of
-- the same icon set in icons/owm; shared-assets/icons/owm is bit-identical).
local ASSETS_DIR = os.getenv("GTEX62_SHARED_ASSETS_DIR")
    or ((os.getenv("HOME") or "") .. "/.config/conky/gtex62-shared-assets")
local OWM_ICON_DIR = ASSETS_DIR .. "/icons/owm"

-- Draw a PNG centered at (cx, cy) scaled to `size` on its longest side.
-- Port of legacy owm.lua draw_png_centered_cairo_local.
local function draw_png_centered(cr, path, cx, cy, size)
  local img = cairo_image_surface_create_from_png(path)
  if (not img) or (cairo_surface_status(img) ~= 0) then
    if img then cairo_surface_destroy(img) end
    return false
  end
  local w = cairo_image_surface_get_width(img)
  local h = cairo_image_surface_get_height(img)
  if (not w or w == 0) or (not h or h == 0) then
    cairo_surface_destroy(img)
    return false
  end
  local scale = size / math.max(w, h)
  cairo_save(cr)
  cairo_translate(cr, cx - (w * scale / 2), cy - (h * scale / 2))
  cairo_scale(cr, scale, scale)
  cairo_set_source_surface(cr, img, 0, 0)
  cairo_paint(cr)
  cairo_restore(cr)
  cairo_surface_destroy(img)
  return true
end

-- Legacy clean-suite WXR: current conditions inside the horizon arc (icon,
-- city, temp, humidity, divider lines), 5-tile forecast strip, and METAR/TAF
-- text blocks. Port of legacy owm.lua draw_main / draw_forecast_placeholder /
-- conky_metar / conky_taf, wired to the core weather + aviation caches.
local function draw_wxr_content(cr, theme, panels, data)
  local panel = panels.wxr
  local wxr   = data and data.wxr
  if not (panel and wxr) then return end

  local colors  = theme.colors
  local fonts   = theme.fonts
  local mono    = fonts.mono or "DejaVu Sans Mono"

  -- Arc center is the shared anchor for the whole weather block
  -- (single source of truth: panels.orb.arc).
  local orb_cfg = (panels.orb and panels.orb.arc) or {}
  local cx      = panel.x + panel.width / 2 + ((orb_cfg.center_offset or {}).x or 0)
  local cy      = (panels.orb and panels.orb.y or panel.y) + (tonumber(orb_cfg.dy) or 204)

  local cur     = type(wxr.legacy_current) == "function" and wxr.legacy_current() or {}

  -- Main block: city, icon, temp, humidity (offsets from arc center)
  local mc      = panel.main or {}
  if cur.city then
    draw_text_center_mid(cr, cx + (mc.city_dx or 0), cy + (mc.city_dy or -120),
      cur.city, mono, mc.city_pt or 12, colors.ink)
  end
  if cur.icon then
    draw_png_centered(cr, OWM_ICON_DIR .. "/" .. cur.icon .. ".png",
      cx + (mc.icon_dx or -65), cy + (mc.icon_dy or -30), mc.icon_size or 90)
  end
  if cur.temp then
    draw_text_left(cr, cx + (mc.temp_dx or 15), cy + (mc.temp_dy or -28),
      cur.temp, mono, mc.temp_pt or 44, colors.fg)
  end
  if cur.humidity then
    draw_text_left(cr, cx + (mc.humidity_dx or 26), cy + (mc.humidity_dy or 0),
      cur.humidity, mono, mc.humidity_pt or 20, colors.ink)
  end

  -- Divider lines (legacy hline/vline, offsets from arc center)
  local vl = panel.vline or {}
  set_rgb(cr, colors.ink)
  cairo_set_line_width(cr, vl.width or 0.5)
  cairo_move_to(cr, cx + (vl.dx or 0), cy + (vl.dy or -80))
  cairo_rel_line_to(cr, 0, vl.length or 100)
  cairo_stroke(cr)

  local hl = panel.hline or {}
  cairo_set_line_width(cr, hl.width or 0.5)
  cairo_move_to(cr, cx - (hl.length or 460) / 2, cy + (hl.dy or 58))
  cairo_rel_line_to(cr, hl.length or 460, 0)
  cairo_stroke(cr)

  -- Forecast tile strip (dates computed today+i, legacy style)
  local fc         = panel.forecast or {}
  local tiles_n    = tonumber(fc.tiles) or 5
  local tile_w     = tonumber(fc.tile_w) or 64
  local gap        = tonumber(fc.gap) or 16
  local rows       = type(wxr.legacy_forecast) == "function" and wxr.legacy_forecast() or {}
  local strip_w    = tiles_n * tile_w + (tiles_n - 1) * gap
  local ox         = cx - strip_w / 2
  local oy         = panel.y + (tonumber(fc.origin_y) or 270)

  local date_c     = fc.date or {}
  local icon_c     = fc.icon or {}
  local temps_c    = fc.temps or {}
  local date_pt    = tonumber(date_c.pt) or 14
  local dow_pt     = date_pt + 2

  local now        = os.date("*t")
  local noon_today = os.time { year = now.year, month = now.month, day = now.day, hour = 12 }

  for i = 0, tiles_n - 1 do
    local tx    = ox + i * (tile_w + gap) + tile_w / 2
    local ts    = noon_today + i * 86400
    local d     = rows[i + 1]

    -- Two-line date label: weekday slightly larger, then "Mon DD"
    local top_y = oy + (tonumber(date_c.dy) or 0) + dow_pt
    draw_text_center_mid(cr, tx, top_y - dow_pt / 2 + 2,
      tostring(os.date("%a", ts)), mono, dow_pt, colors.fg)
    draw_text_center_mid(cr, tx, top_y + date_pt / 2 + 4,
      tostring(os.date("%b %e", ts)), mono, date_pt, colors.fg)

    -- Icon PNG; hollow circle fallback (legacy behavior)
    local ic_size = tonumber(icon_c.size) or 34
    local ic_y    = oy + (tonumber(icon_c.dy) or 46) + ic_size / 2
    local ok      = d and d.icon
        and draw_png_centered(cr, OWM_ICON_DIR .. "/" .. d.icon .. ".png", tx, ic_y, ic_size)
    if not ok then
      cairo_set_line_width(cr, 1.5)
      cairo_set_source_rgba(cr, 0.8, 0.8, 0.8, 0.6)
      cairo_new_sub_path(cr)
      cairo_arc(cr, tx, ic_y, ic_size / 2, 0, 2 * math.pi)
      cairo_stroke(cr)
    end

    -- High / low temps
    local t_pt = tonumber(temps_c.pt) or 22
    local t_y  = oy + (tonumber(temps_c.dy) or 98)
    draw_text_center_mid(cr, tx, t_y, d and d.hi or "--", mono, t_pt, colors.fg)
    draw_text_center_mid(cr, tx, t_y + t_pt + 2, d and d.lo or "--", mono, t_pt, colors.ink)
  end

  -- METAR / TAF blocks (wrapped by the view model from core aviation cache)
  local avi         = panel.aviation or {}
  local avi_px      = tonumber(avi.font_px) or 14
  local line_px     = tonumber(avi.line_px) or 22
  local char_px     = tonumber(avi.char_px) or 8

  local m           = avi.metar or {}
  local metar_lines = type(wxr.current_metar_lines) == "function"
      and wxr.current_metar_lines(m.wrap_col, m.max_lines) or {}
  local metar_x     = cx - ((m.wrap_col or 43) * char_px) / 2
  local metar_y     = panel.y + (tonumber(m.y) or 455)
  for i, line in ipairs(metar_lines) do
    draw_text_left(cr, metar_x, metar_y + (i - 1) * line_px, line, mono, avi_px, colors.fg)
  end

  local t = avi.taf or {}
  local taf_lines = type(wxr.forecast_taf_lines) == "function"
      and wxr.forecast_taf_lines(t.wrap_col, t.max_lines, t.indent_cols) or {}
  local taf_x = metar_x
  local taf_y = panel.y + (tonumber(t.y) or 585)
  for i, line in ipairs(taf_lines) do
    draw_text_left(cr, taf_x, taf_y + (i - 1) * line_px, line, mono, avi_px, colors.fg)
  end
end

----------------------------------------------------------------
-- ORB content (Ambient chassis)
----------------------------------------------------------------

-- Map an arc fraction (0 = East = RIGHT end, 0.5 = apex, 1 = West = LEFT
-- end — the legacy south-facing arc) to screen coordinates.
--
-- Angle convention pitfall (conversion guide, "Sky/Astronomy"): Cairo's
-- cairo_arc measures 0° at 3 o'clock going CLOCKWISE (y-down), while
-- compass azimuth is 0° at north — north is 270° in Cairo terms. We avoid
-- mixing frames by working in y-up math angles (theta = frac·180°;
-- y = cy − r·sin θ), the same convention as legacy owm.lua pt_on_arc().
-- The view model (orb.lua) applies the compass→arc rotation
-- (frac = (azimuth − 90) / 180); this function only maps frac→pixels.
local function orb_arc_xy(cx, cy, r, frac)
  local theta = frac * math.pi -- 0 → right, π/2 → apex, π → left
  return cx + r * math.cos(theta), cy - r * math.sin(theta)
end

-- Legacy clean-suite ORB: horizon arc (day gray / night gray14), West/South/
-- East labels, time-mapped hollow sun + moon markers, azimuth-mapped planet
-- dots, and SR/SS time labels at the arc feet (flipped at night).
-- Port of legacy owm.lua draw_horizon + sun_labels.
local function draw_orb_content(cr, theme, panels, data)
  local panel = panels.orb
  local orb   = data and data.orb
  if not (panel and orb) then return end

  local colors  = theme.colors
  local fonts   = theme.fonts
  local mono    = fonts.mono or "DejaVu Sans Mono"
  local astro   = theme.astro or {}
  local arc_cfg = panel.arc or {}

  local r       = tonumber(arc_cfg.r) or 170
  local dy      = tonumber(arc_cfg.dy) or 204
  local cx      = panel.x + panel.width / 2 + ((arc_cfg.center_offset or {}).x or 0)
  local cy      = panel.y + dy + ((arc_cfg.center_offset or {}).y or 0)

  -- Day/night from today's sun rise/set
  local sun_rise_ts, sun_set_ts
  if type(orb.sun_rise_set) == "function" then
    sun_rise_ts, sun_set_ts = orb.sun_rise_set()
  end
  local now       = os.time()
  local is_day    = sun_rise_ts and sun_set_ts and now >= sun_rise_ts and now <= sun_set_ts

  -- Horizon arc: upper semicircle. In Cairo's y-down clockwise frame the
  -- upper half runs π → 2π (through 3π/2 = top) — same point set as
  -- orb_arc_xy's y-up thetas 0..π.
  local arc_color = is_day and (astro.arc_day or colors.fg) or (astro.arc_night or colors.dim)
  set_rgb(cr, arc_color)
  cairo_set_line_width(cr, 1.5) -- legacy owm.lua arc stroke
  cairo_new_sub_path(cr)
  cairo_arc(cr, cx, cy, r, math.pi, 2 * math.pi)
  cairo_stroke(cr)

  -- Sun marker: hollow circle, time-mapped (only drawn while sun is up)
  local sun_frac = type(orb.sun_arc_fraction) == "function" and orb.sun_arc_fraction() or nil
  if sun_frac ~= nil then
    local sx2, sy2 = orb_arc_xy(cx, cy, r, sun_frac)
    local sc       = astro.sun or {}
    set_rgb(cr, sc.color or colors.accent)
    cairo_set_line_width(cr, tonumber(sc.stroke) or 10.0)
    cairo_new_sub_path(cr)
    cairo_arc(cr, sx2, sy2, (tonumber(sc.diameter) or 36) / 2, 0, 2 * math.pi)
    cairo_stroke(cr)
  end

  -- Moon marker: hollow circle, time-mapped (only drawn while moon is up)
  local moon_frac = type(orb.moon_arc_fraction) == "function" and orb.moon_arc_fraction() or nil
  if moon_frac ~= nil then
    local mx, my = orb_arc_xy(cx, cy, r, moon_frac)
    local mc     = astro.moon or {}
    set_rgb(cr, mc.color or colors.ink)
    cairo_set_line_width(cr, tonumber(mc.stroke) or 10.0)
    cairo_new_sub_path(cr)
    cairo_arc(cr, mx, my, (tonumber(mc.diameter) or 26) / 2, 0, 2 * math.pi)
    cairo_stroke(cr)
  end

  -- Planet markers: filled dots, azimuth-mapped
  local planet_fracs = type(orb.planet_arc_fractions) == "function" and orb.planet_arc_fractions() or {}
  local planet_cfg   = astro.planets or {}
  for name, frac in pairs(planet_fracs) do
    if frac ~= nil then
      local px2, py2 = orb_arc_xy(cx, cy, r, frac)
      local pc       = planet_cfg[name] or {}
      set_rgb(cr, pc.color or colors.dim)
      cairo_new_sub_path(cr)
      cairo_arc(cr, px2, py2, tonumber(pc.r) or 8, 0, 2 * math.pi)
      cairo_fill(cr)
    end
  end

  -- Cardinal labels below the arc: West left, apex label, East right
  -- (legacy used the "Sans" face here, not the mono font)
  local hl    = panel.horizon_labels or {}
  local hl_pt = tonumber(hl.pt) or 12
  local hl_dy = tonumber(hl.dy) or 24
  local apex  = type(orb.apex_label) == "function" and orb.apex_label() or "South"
  draw_text_center_mid(cr, cx - r, cy + hl_dy, "West", "Sans", hl_pt, colors.fg)
  draw_text_center_mid(cr, cx, cy - r + hl_dy, apex, "Sans", hl_pt, colors.fg)
  draw_text_center_mid(cr, cx + r, cy + hl_dy, "East", "Sans", hl_pt, colors.fg)

  -- Sun rise/set time labels at the arc feet.
  -- Day: left = sunset (where the sun is heading), right = sunrise.
  -- Night: flipped (legacy sun_labels behavior).
  local stl         = panel.sun_time_labels or {}
  local stl_pt      = tonumber(stl.pt) or 14
  local stl_dy      = tonumber(stl.dy) or 44
  local sr_txt      = stl.sunrise_text or "SR"
  local ss_txt      = stl.sunset_text or "SS"
  local sr_label    = sr_txt .. " " .. (sun_rise_ts and os.date("%H:%M", sun_rise_ts) or "--:--")
  local ss_label    = ss_txt .. " " .. (sun_set_ts and os.date("%H:%M", sun_set_ts) or "--:--")
  local left_label  = is_day and ss_label or sr_label
  local right_label = is_day and sr_label or ss_label
  draw_text_center_mid(cr, cx - r, cy + stl_dy, left_label, mono, stl_pt, colors.ink)
  draw_text_center_mid(cr, cx + r, cy + stl_dy, right_label, mono, stl_pt, colors.ink)
end

----------------------------------------------------------------
-- TME content (Ambient chassis)
----------------------------------------------------------------

-- Legacy clean-suite TME: centered clock stack (local %H:%M:%S, UTC line,
-- YYYY.MM.DD) at the chassis top. Port of legacy date-time.conky.conf text.
-- The month calendar is NOT drawn here — it is the CAL standalone window
-- (draw_cal_content), matching the legacy suite's separate calendar widget.
local function draw_tme_content(cr, theme, panels, data)
  local panel = panels.tme
  local tme   = data and data.tme
  if not (panel and tme) then return end

  local boxes   = panel.boxes or {}
  local clk_c   = panel.clock or {}
  local colors  = theme.colors
  local fonts   = theme.fonts
  local mono    = fonts.time or fonts.mono or "DejaVu Sans Mono"

  -- Clock stack, centered on the chassis width
  local clk_box = boxes.clock
  if clk_box then
    local cx       = panel.x + clk_box.x + clk_box.width / 2
    local time_px  = tonumber(clk_c.time_px) or 30
    local gmt_px   = tonumber(clk_c.gmt_px) or 14
    local date_px  = tonumber(clk_c.date_px) or 16
    local gap      = tonumber(clk_c.gap_px) or 6

    local time_txt = type(tme.local_time_hms) == "function" and tme.local_time_hms()
        or tostring(os.date("%H:%M:%S"))
    local utc_txt  = type(tme.utc_line) == "function" and tme.utc_line() or ""
    local date_txt = type(tme.date_line) == "function" and tme.date_line()
        or tostring(os.date("%Y.%m.%d"))

    local y        = panel.y + clk_box.y + time_px
    draw_text_center_mid(cr, cx, y - time_px / 2 + 4, time_txt, mono, time_px, colors.fg)
    y = y + gap + gmt_px
    draw_text_center_mid(cr, cx, y - gmt_px / 2 + 2, utc_txt, mono, gmt_px, colors.fg)
    y = y + gap + date_px
    draw_text_center_mid(cr, cx, y - date_px / 2 + 2, date_txt, mono, date_px, colors.fg)
  end
end

----------------------------------------------------------------
-- CAL content (Calendar standalone)
----------------------------------------------------------------

-- Legacy full-size month calendar (nav title, weekday header, 7×6 grid,
-- weekend gray, today in accent). Port of legacy lua/calendar.lua drawing;
-- window position comes from layout.calendar (legacy top_right widget).
local function draw_cal_content(cr, theme, panels, data)
  local panel = panels.cal
  local tme   = data and data.tme
  if not (panel and tme) then return end

  local cal_c  = panel.calendar or {}
  local colors = theme.colors
  local fonts  = theme.fonts
  local mono   = fonts.time or fonts.mono or "DejaVu Sans Mono"

  do
    local cell_w    = tonumber(cal_c.cell_w) or 50
    local cell_h    = tonumber(cal_c.cell_h) or 32
    local col_gap   = tonumber(cal_c.col_gap) or 2
    local row_gap   = tonumber(cal_c.row_gap) or 3
    local border_w  = tonumber(cal_c.border_lw) or 1
    local title_sz  = tonumber(cal_c.title_size) or 20
    local wday_sz   = tonumber(cal_c.weekday_size) or 12
    local day_sz    = tonumber(cal_c.day_size) or 16
    local title_h   = tonumber(cal_c.title_h) or 30
    local title_gp  = tonumber(cal_c.title_gap) or 18
    local header_h  = tonumber(cal_c.header_h) or 18

    local grid_w    = 7 * cell_w + 6 * col_gap
    local origin_x  = panel.x + math.floor((panel.width - grid_w) / 2)
    local origin_y  = panel.y

    local grid_col  = cal_c.grid_color or { 0.35, 0.35, 0.35, 0.55 }
    local wkend_col = cal_c.weekend_color or { 0.47, 0.47, 0.47, 1.00 }

    local view      = type(tme.calendar_view) == "function" and tme.calendar_view() or nil
    local title_str = view and view.title or tostring(os.date("%B %Y"))
    local weeks     = view and view.weeks or {}
    local today_day = view and view.today_day or -1

    -- Title with nav arrows (fixed baseline, legacy style)
    draw_text_center_mid(cr, origin_x + grid_w / 2, origin_y + title_h - 4 - title_sz / 3,
      "< <<  " .. title_str .. "  >> >", mono, title_sz, colors.fg)

    -- Weekday header
    local labels       = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
    local header_y     = origin_y + title_h + title_gp
    local cell_y_start = header_y + header_h
    for c = 1, 7 do
      local x = origin_x + (c - 1) * (cell_w + col_gap)
      draw_text_center_mid(cr, x + cell_w / 2, header_y + header_h / 2,
        labels[c], mono, wday_sz, colors.ink)
    end

    -- Grid + day numbers (always 6 rows; only in-month days shown, legacy style)
    for r = 1, 6 do
      local row = weeks[r] or {}
      for c = 1, 7 do
        local x = origin_x + (c - 1) * (cell_w + col_gap)
        local y = cell_y_start + (r - 1) * (cell_h + row_gap)

        if border_w > 0 then
          cairo_set_line_width(cr, border_w)
          cairo_set_source_rgba(cr, grid_col[1], grid_col[2], grid_col[3], grid_col[4] or 0.55)
          cairo_rectangle(cr, x + border_w / 2, y + border_w / 2,
            cell_w - border_w, cell_h - border_w)
          cairo_stroke(cr)
        end

        local cell = row[c]
        local day  = type(cell) == "table" and cell.day or 0
        local in_m = type(cell) == "table" and (cell.in_month ~= false)
        if day ~= 0 and in_m then
          local is_weekend = (c == 1 or c == 7)
          local col = is_weekend and wkend_col or colors.fg
          if day == today_day then col = colors.accent end
          draw_text_center_mid(cr, x + cell_w / 2, y + cell_h / 2,
            tostring(day), mono, day_sz, col)
        end
      end
    end
  end
end

----------------------------------------------------------------
-- MSC content (Media chassis)
----------------------------------------------------------------

local function draw_msc_content(cr, theme, panels, data)
  local panel = panels.msc
  local msc   = data and data.msc
  if not (panel and msc) then return end

  local colors    = theme.colors
  local fonts     = theme.fonts
  local arc_cfg   = panel.arc or {}

  local r         = tonumber(arc_cfg.r) or 140
  local dy        = tonumber(arc_cfg.dy) or 50
  local cx        = panel.x + panel.width / 2
  local cy        = panel.y + dy

  local is_active = type(msc.is_active) == "function" and msc.is_active()
  local progress  = type(msc.progress_fraction) == "function" and msc.progress_fraction() or 0

  -- Smile arc base (cairo_arc_negative: CW from 200° to -20° through 270°)
  set_rgb(cr, is_active and colors.fg or colors.dim)
  cairo_set_line_width(cr, theme.strokes.arc or 2.0)
  cairo_new_sub_path(cr)
  cairo_arc_negative(cr, cx, cy, r, math.rad(200), math.rad(-20))
  cairo_stroke(cr)

  -- Progress marker on arc
  -- arc_negative sweeps from 200° to -20° (=340°) CW, total 220°
  -- fraction 0 → 200°, fraction 1 → -20°
  if is_active and progress and progress > 0 then
    local angle_deg = 200 - progress * 220
    local angle_rad = math.rad(angle_deg)
    local mx = cx + r * math.cos(angle_rad)
    local my = cy + r * math.sin(angle_rad)
    set_rgb(cr, colors.accent or colors.fg)
    cairo_new_sub_path(cr)
    cairo_arc(cr, mx, my, 5, 0, 2 * math.pi)
    cairo_fill(cr)
  end

  -- Text labels
  local txt_cfg   = panel.text or {}
  local title_cfg = txt_cfg.title or {}
  local album_cfg = txt_cfg.album or {}
  local art_cfg   = txt_cfg.artist or {}
  local art_xy    = panel.art or {}

  local art_cx    = cx + (tonumber(art_xy.dx) or 0)
  local art_cy    = cy + (tonumber(art_xy.dy) or -13)

  if is_active then
    local title  = type(msc.title) == "function" and msc.title() or ""
    local album  = type(msc.album) == "function" and msc.album() or ""
    local artist = type(msc.artist) == "function" and msc.artist() or ""

    draw_text_center_mid(cr, art_cx, art_cy + (tonumber(title_cfg.dy) or -6),
      title, fonts.data, tonumber(title_cfg.pt) or 15, colors.fg)
    draw_text_center_mid(cr, art_cx, art_cy + (tonumber(album_cfg.dy) or 18),
      album, fonts.data, tonumber(album_cfg.pt) or 11, colors.dim)
    draw_text_center_mid(cr, art_cx, art_cy + (tonumber(art_cfg.dy) or 128),
      artist, fonts.data, tonumber(art_cfg.pt) or 14, colors.fg)

    -- Progress bar at panel bottom
    local bar_w = panel.width - 36
    local bar_x = panel.x + 18
    local bar_y = panel.y + panel.height - 16
    draw_rect(cr, bar_x, bar_y, bar_w, 4, theme.strokes.line, colors.dim)
    draw_hbar(cr, bar_x, bar_y, bar_w, 4, progress, colors.fg)
  else
    draw_text_center_mid(cr, cx, cy + 24, "IDLE", fonts.data, theme.sizes.data, colors.dim)
  end
end

----------------------------------------------------------------
-- NOTES content (standalone window)
-- Legacy notes.conky.conf: plain wrapped text lines, DejaVu Sans
-- Mono size 9 (16.6 px here), default_color FFFFFF -> colors.fg.
-- Grid metrics in panels.notes.grid were measured off the running
-- legacy widget (20 px pitch, baseline 21 in-window).
----------------------------------------------------------------

local function draw_notes_content(cr, theme, panels, data)
  local panel = panels.notes
  local notes = data and data.notes
  if not (panel and notes) then return end

  local g     = panel.grid or {}
  local lines = type(notes.lines) == "function"
      and notes.lines({ wrap = panel.wrap_chars, max = panel.max_lines, refresh = panel.refresh_s })
      or {}
  local x     = panel.x + (g.x0 or 7)
  local y0    = panel.y + (g.first_baseline or 21)
  local lh    = g.line_px or 20
  for i, line in ipairs(lines) do
    draw_text_left(cr, x, y0 + (i - 1) * lh, line, theme.fonts.mono, g.font_px or 16.6, theme.colors.fg)
  end
end

----------------------------------------------------------------
-- LYRICS content (Media chassis)
----------------------------------------------------------------

local function draw_lyrics_content(cr, theme, panels, data)
  local panel = panels.lyrics
  local msc   = data and data.msc
  if not (panel and msc) then return end

  local colors  = theme.colors
  local fonts   = theme.fonts
  local pad     = panel.padding or {}
  local hdr_cfg = panel.header or {}
  local body_c  = panel.body or {}

  local pt_hdr  = tonumber(hdr_cfg.pt) or 14
  local pt_body = tonumber(body_c.pt) or 12
  local line_px = tonumber(body_c.line_px) or 15

  local x       = panel.x + (tonumber(pad.left) or 10)
  local y       = panel.y + (tonumber(pad.top) or 10)

  if hdr_cfg.enabled ~= false and type(msc.lyrics_header) == "function" then
    local hdr = msc.lyrics_header()
    if hdr and hdr ~= "" then
      draw_text_left(cr, x, y + pt_hdr, hdr, fonts.data, pt_hdr, colors.fg, CAIRO_FONT_WEIGHT_BOLD)
      y = y + pt_hdr + 8
    end
  end

  local avail_h = panel.height - (y - panel.y) - (tonumber(pad.bottom) or 10)
  local max_l   = math.max(1, math.floor(avail_h / line_px))
  local lines   = type(msc.lyrics_lines) == "function" and msc.lyrics_lines(max_l) or {}
  for i, line in ipairs(lines) do
    draw_text_left(cr, x, y + (i - 1) * line_px + pt_body, line, fonts.data, pt_body, colors.fg)
  end
end

----------------------------------------------------------------
-- pfSense FLOW content (standalone; VLAN traffic arcs only, guide §1.4 —
-- CPU/MEM/gateway/status content is retired to the core sitrep utility)
--
-- Legacy composition (pf_widget.lua): concentric dome arcs, one per VLAN,
-- with anchor_strength lifting each inner arc's center so the endpoints
-- stair-step inward. Rate markers travel from the base ends toward the
-- apex (IN sweeps 180°→90° from the left, OUT sweeps 0°→90° from the
-- right; apex = 100% of the link cap). IN is a filled dot, OUT a hollow
-- ring, colored per VLAN (theme.pf_markers); idle markers rest visibly
-- at the endpoints.
----------------------------------------------------------------

-- Angles are y-up math angles (0 = right, π/2 = apex, π = left); Cairo's
-- y-down frame is handled by subtracting the sine term.
local function pf_point(cx, cy, r, angle)
  return cx + r * math.cos(angle), cy - r * math.sin(angle)
end

local function draw_pf_content(cr, theme, panels, data)
  local panel = panels.pfsense
  local pf    = data and data.pf
  if not (panel and pf) then return end

  local colors     = theme.colors
  local fonts      = theme.fonts
  local arc_cfg    = panel.arc or {}
  local pf_theme   = theme.pf or {}
  local markers    = theme.pf_markers or {}

  local r_outer    = tonumber(arc_cfg.r) or 300
  local delta_r    = tonumber(arc_cfg.delta_r) or 36
  local arc_lw     = tonumber(arc_cfg.width) or 2
  local anchor_k   = clamp01(arc_cfg.anchor_strength)
  local cx         = panel.x + panel.width / 2
  local cy         = panel.y + (tonumber(arc_cfg.dy) or 300)

  local order      = panel.iface_order or { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }
  local arc_base_c = pf_theme.arc_base or colors.dim

  -- Smoothed, curve-scaled fractions (0..1) per VLAN/direction; the panel
  -- table itself carries the scale/cap/smoothing config the view model needs.
  local flow = type(pf.flow_fractions) == "function" and pf.flow_fractions(panel) or {}

  -- Per-arc geometry: radius shrinks by delta_r; anchor_strength lifts each
  -- inner center by a fraction of that decrement (legacy nesting behavior).
  local geo = {}
  for i, vlan in ipairs(order) do
    local r_v = r_outer - (i - 1) * delta_r
    if r_v <= 4 then break end
    geo[#geo + 1] = { vlan = vlan, r = r_v, cy = cy - anchor_k * (i - 1) * delta_r }
  end
  if #geo == 0 then return end

  local A_LEFT, A_APEX, A_RIGHT = math.pi, math.pi / 2, 0

  -- Base arcs (upper semicircle)
  set_rgb(cr, arc_base_c)
  cairo_set_line_width(cr, arc_lw)
  for _, g in ipairs(geo) do
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, g.cy, g.r, math.pi, 2 * math.pi)
    cairo_stroke(cr)
  end

  -- Static scale label under the outer arc apex
  local top_lbl = panel.top_label or {}
  if top_lbl.enabled ~= false and top_lbl.text then
    draw_text_center_mid(cr, cx, geo[1].cy - geo[1].r + (tonumber(top_lbl.dy) or 94),
      top_lbl.text, fonts.label, tonumber(top_lbl.size) or 12, colors.ink)
  end

  -- Arc name labels: dash leader + name drawn inward from each arc's left
  -- endpoint ("-----WAN" in the legacy dash..text order)
  local names_cfg = panel.arc_names or {}
  if names_cfg.enabled ~= false then
    local per_arc   = names_cfg.per_arc or {}
    local name_pt   = tonumber(names_cfg.size) or 16
    local dash_char = names_cfg.dash_char or "-"
    local name_dx   = tonumber(names_cfg.dx) or 5
    local name_dy   = tonumber(names_cfg.dy) or 5
    for _, g in ipairs(geo) do
      local nc  = per_arc[g.vlan] or {}
      local txt = string.rep(dash_char, tonumber(nc.dash_count) or 14) .. (nc.text or g.vlan)
      draw_text_left(cr, cx - g.r + name_dx, g.cy + name_dy,
        txt, fonts.data, name_pt, colors.fg)
    end
  end

  -- DN / UP labels below the outermost arc's base endpoints
  local lbl_cfg = panel.labels or {}
  do
    local lbl_pt   = tonumber(lbl_cfg.size) or 12
    local text_in  = lbl_cfg.text_in or "DN"
    local text_out = lbl_cfg.text_out or "UP"
    local g1       = geo[1]
    draw_text_left(cr,
      cx - g1.r + (tonumber(lbl_cfg.dx_left) or -8),
      g1.cy + (tonumber(lbl_cfg.dy_left) or 30),
      text_in, fonts.label, lbl_pt, colors.ink, CAIRO_FONT_WEIGHT_BOLD)
    draw_text_left(cr,
      cx + g1.r + (tonumber(lbl_cfg.dx_right) or -8),
      g1.cy + (tonumber(lbl_cfg.dy_right) or 30),
      text_out, fonts.label, lbl_pt, colors.ink, CAIRO_FONT_WEIGHT_BOLD)
  end

  -- Rate markers: IN filled from the left end toward the apex, OUT hollow
  -- from the right end toward the apex. Always drawn — idle markers rest
  -- at the endpoints, matching the legacy widget.
  local out_stroke = tonumber((panel.marker or {}).out_stroke) or 3
  for _, g in ipairs(geo) do
    local f     = flow[g.vlan] or {}
    local mc    = markers[g.vlan] or {}
    local m_col = mc.color or colors.fg
    local m_r   = tonumber(mc.r) or 12

    local in_a  = A_LEFT + (A_APEX - A_LEFT) * clamp01(f.in_frac)
    local out_a = A_RIGHT + (A_APEX - A_RIGHT) * clamp01(f.out_frac)

    local ix, iy = pf_point(cx, g.cy, g.r, in_a)
    set_rgb(cr, m_col)
    cairo_new_sub_path(cr)
    cairo_arc(cr, ix, iy, m_r, 0, 2 * math.pi)
    cairo_fill(cr)

    local ox, oy = pf_point(cx, g.cy, g.r, out_a)
    cairo_set_line_width(cr, out_stroke)
    cairo_new_sub_path(cr)
    cairo_arc(cr, ox, oy, m_r, 0, 2 * math.pi)
    cairo_stroke(cr)
  end

  -- Baseline under the dome
  local bl = panel.baseline or {}
  if bl.enabled ~= false then
    local len = tonumber(bl.length) or panel.width
    local by  = cy + (tonumber(bl.dy) or 50)
    set_rgb(cr, colors.fg)
    cairo_set_line_width(cr, tonumber(bl.width) or 1)
    cairo_move_to(cr, cx - len / 2, by)
    cairo_line_to(cr, cx + len / 2, by)
    cairo_stroke(cr)
  end
end

----------------------------------------------------------------
-- Public chassis entry points
----------------------------------------------------------------

function M.draw_monitor(cr, theme, panels, data)
  local cur = draw_sys_content(cr, theme, panels, data)
  draw_net_content(cr, theme, panels, data, cur)
end

function M.draw_ambient(cr, theme, panels, data)
  draw_wxr_content(cr, theme, panels, data)
  draw_orb_content(cr, theme, panels, data)
  draw_tme_content(cr, theme, panels, data)
end

function M.draw_calendar(cr, theme, panels, data)
  draw_cal_content(cr, theme, panels, data)
end

function M.draw_media(cr, theme, panels, data)
  draw_msc_content(cr, theme, panels, data)
  draw_lyrics_content(cr, theme, panels, data)
end

function M.draw_notes(cr, theme, panels, data)
  draw_notes_content(cr, theme, panels, data)
end

function M.draw_pfsense(cr, theme, panels, data)
  draw_pf_content(cr, theme, panels, data)
end

return M
