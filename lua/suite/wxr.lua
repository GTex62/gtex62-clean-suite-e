-- lua/suite/wxr.lua
-- WXR domain view model for gtex62-clean-suite-e.
-- Port of gtex62-osa/lua/suite/wxr.lua; SUITE_ID changed to "clean-e",
-- theme loading removed (wrap/max params accepted from caller instead).
--
-- 2026-08-29 dead-code sweep (compliance-scan F5): the OSA-inherited
-- tabular display API (status_lines, current_box_title/headers/row,
-- forecast_box_title/headers/rows, station_model_box_title, station_model)
-- was never wired into frame.lua — the legacy composition below
-- (legacy_current/legacy_forecast + the METAR/TAF wrappers) is what's
-- actually drawn. Removed those 9 functions and everything that existed
-- only to feed them: the whole METAR/TAF station-model parser (wind/vis/
-- temp/altimeter/cloud/remarks decoding, tendency/wx glyph mapping),
-- decode_current's OWM sky/wx glyph lookup, decode_forecast_rows, and the
-- weather-status/aviation-status "DATA // NOMINAL" state machine. This
-- also removes the only two consumers of `dofile lua/lib/weather_codes.lua`
-- (a path that doesn't exist in this suite — it silently pcall-failed to
-- WEATHER_CODES = false) and of load_weather_codes/utf8_char, so both go
-- with it; the dofile call is gone, not just dead-ended.

local M = {}

local HOME               = os.getenv("HOME") or ""
local SUITE_ID           = os.getenv("GTEX62_SUITE_ID") or "clean-e"
local DEFAULT_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local RUNTIME_ROOT       = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")

local read_aviation_text

local CACHE = {
  stamp        = nil,
  metar_lines  = nil,
  taf_lines    = nil,
  -- wrap params that produced the current cached lines
  metar_wrap   = nil,
  metar_max    = nil,
  taf_wrap     = nil,
  taf_max      = nil,
  taf_indent   = nil,
}

local function read_file(path)
  if not path or path == "" then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function command_output(cmd)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

local function normalize_spaces(s)
  return (s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function minute_stamp()
  return math.floor(os.time() / 60)
end

local function parse_simple_toml(path)
  local out     = {}
  local section = nil
  local s       = read_file(path)
  if not s then return out end
  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local sec = line:match("^%[([%w_%-]+)%]$")
      if sec then
        section      = sec
        out[section] = out[section] or {}
      else
        local key, value = line:match("^([%w_%-]+)%s*=%s*(.+)$")
        if key and value then
          value = value:gsub('^"', ""):gsub('"$', "")
          if section then
            out[section][key] = value
          else
            out[key] = value
          end
        end
      end
    end
  end
  return out
end

local function engine_config()
  local cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  if next(cfg) ~= nil then return cfg end
  return parse_simple_toml(RUNTIME_ROOT .. "/engine.toml")
end

local function suite_config()
  return parse_simple_toml(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml")
end

local function profile_config(domain, fallback)
  local profile_id = ((suite_config().profiles or {})[domain]) or fallback
  return profile_id, parse_simple_toml(string.format("%s/profiles/%s/%s.toml", RUNTIME_ROOT, domain, profile_id))
end

local function engine_cache_root()
  local cfg = engine_config()
  return (((cfg or {}).paths or {}).cache_root) or DEFAULT_CACHE_ROOT
end

local function weather_profile_id()
  local profile_id = profile_config("weather", "home")
  return profile_id
end

local function aviation_profile_id()
  local profile_id = profile_config("aviation", "home")
  return profile_id
end

local function aviation_station(kind)
  local _, cfg   = profile_config("aviation", "home")
  local stations = cfg.stations or {}
  if stations[kind] then return string.upper(stations[kind]) end
  if kind == "station_model" then
    local site = parse_simple_toml(string.format("%s/site.toml", RUNTIME_ROOT))
    local av   = (site.aviation or {})
    local id   = av.station_model or av.metar or av.primary
    if id and id ~= "" then return string.upper(id) end
  end
  return string.upper(stations.primary or "KMEM")
end

local function weather_shared_dir()
  return string.format("%s/shared/weather/%s", engine_cache_root(), weather_profile_id())
end

local function aviation_shared_dir()
  return string.format("%s/shared/aviation/%s", engine_cache_root(), aviation_profile_id())
end

local function weather_current_path()    return weather_shared_dir()  .. "/current.json" end
local function weather_forecast_path()   return weather_shared_dir()  .. "/forecast_daily.json" end
local function aviation_current_path()   return aviation_shared_dir() .. "/current.json" end

local function json_query(path, filter)
  if not read_file(path) then return nil end
  local out = command_output(string.format("jq -r %q %q 2>/dev/null", filter, path))
  if not out or out == "null" or out == "" then return nil end
  return out
end

local function extract_ob_line(raw)
  if not raw or raw == "" then return "" end
  for line in raw:gmatch("[^\r\n]+") do
    local ob = line:match("^ob:%s*(.+)$")
    if ob and ob ~= "" then return normalize_spaces(ob) end
    local icao = line:match("^METAR%s+(.+)$") or line:match("^SPECI%s+(.+)$")
    if icao and icao ~= "" then return normalize_spaces(icao) end
  end
  return normalize_spaces(raw)
end

local function wrap_lines(text, width, max_lines)
  local lines    = {}
  local wrap_col = math.max(8, tonumber(width) or 43)
  local limit    = math.max(1, tonumber(max_lines) or 5)

  local function emit_segment(segment)
    local s = normalize_spaces(segment)
    while s ~= "" do
      if #s <= wrap_col then
        lines[#lines + 1] = s; return
      end
      local split = wrap_col
      for i = wrap_col, 2, -1 do
        if s:sub(i, i) == " " then split = i - 1; break end
      end
      lines[#lines + 1] = s:sub(1, split)
      s = s:sub(split + 1):gsub("^%s+", "")
    end
  end

  local rmk_pos = text and text:find(" RMK ", 1, true) or nil
  if rmk_pos then
    emit_segment(text:sub(1, rmk_pos - 1))
    emit_segment(text:sub(rmk_pos + 1))
  else
    emit_segment(text or "")
  end

  if #lines > limit then
    lines[limit] = (lines[limit] or "") .. "..."
    while #lines > limit do table.remove(lines) end
  end

  return lines
end

read_aviation_text = function(kind)
  local json_path = aviation_current_path()
  local filter
  if     kind == "metar"         then filter = ".metar_raw // .metar // .current.metar_raw // .current.metar // empty"
  elseif kind == "station_model" then filter = ".station_model_raw // .metar_raw // .metar // .current.metar_raw // .current.metar // empty"
  else                                filter = ".taf_raw // .taf // .current.taf_raw // .current.taf // empty"
  end
  local value = json_query(json_path, filter)
  if value and value ~= "" then return value end
  return read_file(string.format("%s/%s.txt", aviation_shared_dir(), kind))
end

local function decode_metar_lines(wrap_col, max_lines)
  local raw = read_aviation_text("metar") or ""
  raw = raw:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then return { "METAR UNAVAILABLE" } end
  local ob = extract_ob_line(raw)
  if ob == "" then ob = string.format("%s METAR UNAVAILABLE", aviation_station("metar")) end
  return wrap_lines(ob, tonumber(wrap_col) or 43, tonumber(max_lines) or 5)
end

local function decode_taf_lines(wrap_col, max_lines, indent_cols)
  local raw = read_aviation_text("taf") or ""
  raw = raw:gsub("\r", ""):gsub("\n=%s*$", ""):gsub("\n=", "")
  if raw == "" then return { "TAF UNAVAILABLE" } end

  local one_line = raw:gsub("\n", " "):gsub("%s+", " "):gsub("%s+$", "")
  one_line = one_line:gsub("^.*%f[%w]TAF%s+", "")

  local marked = one_line
    :gsub("%s+(FM%d%d%d%d%d%d)", "\n%1")
    :gsub("%s+(TEMPO)",           "\n%1")
    :gsub("%s+(PROB%d%d)",        "\n%1")
    :gsub("%s+(BECMG)",           "\n%1")

  local segments = {}
  for line in marked:gmatch("[^\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then segments[#segments + 1] = trimmed end
  end

  local col    = math.max(8, tonumber(wrap_col) or 60)
  local limit  = math.max(1, tonumber(max_lines) or 4)
  local indent = string.rep(" ", math.max(0, tonumber(indent_cols) or 5))
  local lines  = {}

  local function emit_wrapped(text, prefix)
    local s = text
    while s ~= "" do
      local available = col - #prefix
      if #s <= available then
        lines[#lines + 1] = prefix .. s; return
      end
      local split = available
      for i = available, 2, -1 do
        if s:sub(i, i) == " " then split = i - 1; break end
      end
      lines[#lines + 1] = prefix .. s:sub(1, split)
      s = s:sub(split + 1):gsub("^%s+", "")
      if #lines >= limit then return end
      prefix = indent
    end
  end

  for i, segment in ipairs(segments) do
    emit_wrapped(segment, i == 1 and "" or indent)
    if #lines >= limit then break end
  end

  if #lines == 0 then return { "TAF UNAVAILABLE" } end
  if #lines > limit then
    lines[limit] = (lines[limit] or "") .. "..."
    while #lines > limit do table.remove(lines) end
  end

  return lines
end

local function refresh(wrap_col, max_lines, taf_wrap, taf_max, taf_indent)
  local stamp = minute_stamp()
  if CACHE.stamp == stamp
    and CACHE.metar_wrap  == wrap_col   and CACHE.metar_max == max_lines
    and CACHE.taf_wrap    == taf_wrap   and CACHE.taf_max   == taf_max
    and CACHE.taf_indent  == taf_indent
  then
    return
  end
  CACHE.metar_lines   = decode_metar_lines(wrap_col, max_lines)
  CACHE.taf_lines     = decode_taf_lines(taf_wrap, taf_max, taf_indent)
  CACHE.stamp         = stamp
  CACHE.metar_wrap    = wrap_col
  CACHE.metar_max     = max_lines
  CACHE.taf_wrap      = taf_wrap
  CACHE.taf_max       = taf_max
  CACHE.taf_indent    = taf_indent
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- wrap_col / max_lines are optional; caller may pass panels.wxr.aviation config values.
function M.current_metar_lines(wrap_col, max_lines)
  refresh(wrap_col, max_lines, CACHE.taf_wrap, CACHE.taf_max, CACHE.taf_indent)
  return CACHE.metar_lines or { "METAR UNAVAILABLE" }
end

function M.forecast_taf_lines(wrap_col, max_lines, indent_cols)
  refresh(CACHE.metar_wrap, CACHE.metar_max, wrap_col, max_lines, indent_cols)
  return CACHE.taf_lines or { "TAF UNAVAILABLE" }
end

----------------------------------------------------------------
-- Legacy clean-suite display accessors (main block + forecast tiles)
-- Read the same core weather cache; formatted per legacy owm.lua.
----------------------------------------------------------------

local LEGACY = { stamp = nil, current = nil, forecast = nil }

local function legacy_refresh()
  local stamp = minute_stamp()
  if LEGACY.stamp == stamp then return end
  LEGACY.stamp = stamp

  local cur = json_query(weather_current_path(),
    '[(.location.name // .name // ""), (.temp_f // .main.temp // ""), (.humidity_pct // .main.humidity // ""), (.icon // .weather[0].icon // "")] | @tsv')
  if cur then
    local city, temp, hum, icon = cur:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    local t = tonumber(temp)
    local h = tonumber(hum)
    LEGACY.current = {
      city     = city ~= "" and city or nil,
      temp     = t and string.format("%.0f°", t) or nil,
      humidity = h and string.format("%.0f%%", h) or nil,
      icon     = icon ~= "" and icon or nil,
    }
  else
    LEGACY.current = nil
  end

  local rows = {}
  local fc = json_query(weather_forecast_path(),
    'def rows: if type == "array" then . elif .days then .days elif .daily then .daily else [] end; rows | .[:6][] | [(.icon // .weather[0].icon // ""), (.high_f // .high // ""), (.low_f // .low // "")] | @tsv')
  if fc then
    for line in fc:gmatch("[^\r\n]+") do
      local icon, hi, lo = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
      local h  = tonumber(hi)
      local l  = tonumber(lo)
      rows[#rows + 1] = {
        icon = icon ~= "" and icon or nil,
        hi   = h and string.format("%.0f", h) or "--",
        lo   = l and string.format("%.0f", l) or "--",
      }
    end
  end
  LEGACY.forecast = rows
end

-- Main-block values: { city, temp = "94°", humidity = "59%", icon = "01d" }
function M.legacy_current()
  legacy_refresh()
  return LEGACY.current or {}
end

-- Forecast tile rows (today first): { { icon, hi, lo }, ... }
function M.legacy_forecast()
  legacy_refresh()
  return LEGACY.forecast or {}
end

return M
