-- lua/suite/orb.lua
-- ORB (horizon arc) view model for gtex62-clean-suite-e.
-- Reads the core astro domain cache: shared/astro/[profile]/current.json
-- (canonical altitude_deg / azimuth_deg / rise/set timestamps).
--
-- Replaces the OSA-ported version that read the never-populated
-- suite-local suites/clean-e/orb/ephemeris.vars path.
--
-- ## Arc angle convention (see conversion guide pitfall "Sky/Astronomy")
--
-- The legacy clean-suite arc is a south-facing upper semicircle:
--   East  = RIGHT arc end
--   South = arc apex (top)
--   West  = LEFT arc end
-- This module exposes positions as arc *fractions*: 0.0 = East/right end,
-- 0.5 = apex, 1.0 = West/left end. The renderer maps a fraction to screen
-- coordinates with y-up math (theta = frac·180°; x = cx + r·cos θ,
-- y = cy − r·sin θ), which sidesteps Cairo's y-down/clockwise angle
-- convention entirely. Compass azimuth (0°=N, 90°=E, 180°=S, 270°=W)
-- converts as frac = (azimuth − 90) / 180 — the 90° rotation from the
-- compass frame into the arc frame; anything outside [0,1] (north of the
-- E–W line) is off-arc and hidden.
--
-- Body mapping follows legacy owm.lua exactly:
--   Sun and moon: TIME-mapPED — fraction of the way from rise to set.
--     (Azimuth-mapping the sun is wrong: in summer it rises north of
--     east (az < 90°), which would hide it while it is plainly up.)
--   Planets: AZIMUTH-mapped, hidden when below horizon or off-arc.

local M = {}

local HOME         = os.getenv("HOME") or ""
local SUITE_ID     = os.getenv("GTEX62_SUITE_ID") or "clean-e"
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR")
  or (HOME .. "/.config/gtex62-core")
local CACHE_ROOT   = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR")
  or (HOME .. "/.cache/gtex62-core")

local function read_file(path)
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

-- Astro profile from the suite runtime config (same lookup as tme.lua).
local function astro_profile_id()
  local s = read_file(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml")
  if s then
    local in_profiles = false
    for line in s:gmatch("[^\r\n]+") do
      line = line:gsub("#.*$", "")
      local sec = line:match("^%s*%[([%w_%-]+)%]")
      if sec then in_profiles = (sec == "profiles") end
      if in_profiles then
        local v = line:match('^%s*astro%s*=%s*"?([%w_%-]+)"?')
        if v then return v end
      end
    end
  end
  return "home"
end

local function astro_json_path()
  return string.format("%s/shared/astro/%s/current.json", CACHE_ROOT, astro_profile_id())
end

-- One jq call per minute flattens the bodies into KEY=value pairs:
-- SUN_ALT / SUN_AZ / SUN_UP / SUN_PREV_RISE_TS / ... and same for
-- MOON and each planet.
local ASTRO_JQ = [[
  def body(name; b):
    "\(name)_ALT=\(b.altitude_deg // "")",
    "\(name)_AZ=\(b.azimuth_deg // "")",
    "\(name)_UP=\(if b.is_above_horizon then 1 else 0 end)",
    "\(name)_PREV_RISE_TS=\(b.prev_rise_ts // "")",
    "\(name)_PREV_SET_TS=\(b.prev_set_ts // "")",
    "\(name)_NEXT_RISE_TS=\(b.next_rise_ts // "")",
    "\(name)_NEXT_SET_TS=\(b.next_set_ts // "")";
  body("SUN"; .sun),
  body("MOON"; .moon),
  (.planets | to_entries[]? | body(.key | ascii_upcase; .value))
]]

local DATA = { stamp = nil, kv = {} }

local function minute_stamp()
  return math.floor(os.time() / 60)
end

local function astro_data()
  local stamp = minute_stamp()
  if DATA.stamp == stamp then return DATA.kv end
  DATA.stamp = stamp
  DATA.kv = {}
  local out = command_output(string.format("jq -r %q %q 2>/dev/null", ASTRO_JQ, astro_json_path()))
  if out then
    for line in out:gmatch("[^\r\n]+") do
      local key, value = line:match("^([A-Z_]+)=(.*)$")
      if key and value ~= "" then
        DATA.kv[key] = tonumber(value) or value
      end
    end
  end
  return DATA.kv
end

local function num(kv, key)
  return tonumber(kv[key])
end

----------------------------------------------------------------
-- Rise/set selection for today's labels (kept from previous version)
----------------------------------------------------------------

local function current_day_window()
  local now = os.date("*t")
  local start_ts = os.time { year = now.year, month = now.month, day = now.day, hour = 0, min = 0, sec = 0 }
  return start_ts, start_ts + 86400
end

local function ts_in_window(ts, start_ts, end_ts)
  return ts ~= nil and ts >= start_ts and ts < end_ts
end

local function pick_today_rise_set(kv, key)
  local day_start, day_end = current_day_window()

  local prev_rise = num(kv, key .. "_PREV_RISE_TS")
  local next_rise = num(kv, key .. "_NEXT_RISE_TS")
  local prev_set  = num(kv, key .. "_PREV_SET_TS")
  local next_set  = num(kv, key .. "_NEXT_SET_TS")

  local rise_ts = ts_in_window(prev_rise, day_start, day_end) and prev_rise
               or ts_in_window(next_rise, day_start, day_end) and next_rise
               or nil
  local set_ts  = ts_in_window(prev_set,  day_start, day_end) and prev_set
               or ts_in_window(next_set,  day_start, day_end) and next_set
               or nil

  if rise_ts and set_ts then return rise_ts, set_ts end
  if rise_ts == nil and prev_rise ~= nil and set_ts ~= nil and prev_rise < day_start then
    return prev_rise, set_ts
  end
  if rise_ts ~= nil and set_ts == nil and next_set ~= nil and next_set >= day_end then
    return rise_ts, next_set
  end
  return rise_ts, set_ts
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Compass azimuth → arc fraction (0 = East/right, 1 = West/left).
-- nil when the azimuth falls north of the E–W line (off-arc).
function M.arc_fraction_for_azimuth(azimuth_deg)
  local az = tonumber(azimuth_deg)
  if az == nil then return nil end
  az = (az % 360 + 360) % 360
  local frac = (az - 90) / 180.0
  if frac < 0 or frac > 1 then return nil end
  return frac
end

-- Time-mapped fraction between the body's most recent rise and next set.
-- Two gates, both required:
--   1. Time window (legacy is_day check): now must lie in [rise, set].
--      Robust against a stale cache still reporting daytime altitude
--      after actual sunset.
--   2. Altitude/above-horizon from the provider: hides the moon when it
--      is below the horizon even though now is inside its rise→set span
--      (the span can bridge a below-horizon stretch).
local function time_mapped_fraction(kv, key)
  if num(kv, key .. "_ALT") == nil then
    if kv[key .. "_UP"] ~= 1 then return nil end
  elseif num(kv, key .. "_ALT") < 0 then
    return nil
  end
  local rise_ts = num(kv, key .. "_PREV_RISE_TS")
  local set_ts  = num(kv, key .. "_NEXT_SET_TS")
  if not (rise_ts and set_ts) or set_ts <= rise_ts then return nil end
  local now = os.time()
  if now < rise_ts or now > set_ts then return nil end
  return (now - rise_ts) / (set_ts - rise_ts)
end

function M.sun_arc_fraction()
  return time_mapped_fraction(astro_data(), "SUN")
end

function M.moon_arc_fraction()
  return time_mapped_fraction(astro_data(), "MOON")
end

-- Planets: azimuth-mapped; nil (hidden) below horizon or off-arc.
function M.planet_arc_fractions()
  local kv      = astro_data()
  local planets = { "MERCURY", "VENUS", "MARS", "JUPITER", "SATURN" }
  local result  = {}
  for _, name in ipairs(planets) do
    local alt = num(kv, name .. "_ALT")
    if alt ~= nil and alt >= 0 then
      result[name] = M.arc_fraction_for_azimuth(num(kv, name .. "_AZ"))
    end
  end
  return result
end

function M.sun_rise_set()
  return pick_today_rise_set(astro_data(), "SUN")
end

function M.moon_rise_set()
  return pick_today_rise_set(astro_data(), "MOON")
end

-- Observer latitude sign decides the apex label ("South" for northern
-- hemisphere observers). Memoized — the observer does not move mid-session.
local apex_label_cached
function M.apex_label()
  if apex_label_cached then return apex_label_cached end
  local lat = command_output(string.format(
    "jq -r '.observer.lat // empty' %q 2>/dev/null", astro_json_path()))
  local n = tonumber(lat)
  apex_label_cached = (n and n < 0) and "North" or "South"
  return apex_label_cached
end

return M
