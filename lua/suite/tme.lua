-- lua/suite/tme.lua
-- TME domain view model for gtex62-clean-suite-e.
-- Ported from gtex62-osa/lua/suite/tme.lua; suite-specific changes:
--   SUITE_ID "clean-e", suite config path suites/clean-e.toml
--
-- 2026-08-29 dead-code sweep (compliance-scan F5): the OSA-inherited
-- status-line/clock-table/calendar-table API (status_lines, clock_*,
-- calendar_title/weeks/today/events/event_dates, local_time, utc_time,
-- local_date) was never wired into frame.lua — the legacy display path
-- below (local_time_hms/utc_line/date_line/calendar_view) is what's
-- actually drawn. Removed those 12 functions and everything that existed
-- only to feed them (core/calendar-events/astro-events readers, the
-- TZ=... date shell call in tz_date_parts, the suite-config/TOML parsing
-- used only to resolve calendar/astro/time cache profiles). build_weeks/
-- days_in_month/weekday_su0 survive — calendar_view (live) uses them too.

local M = {}

local HOME              = os.getenv("HOME") or ""
local DEFAULT_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local SUITE_ID          = os.getenv("GTEX62_SUITE_ID") or "clean-e"

local function days_in_month(y, m)
  local nm, ny = m + 1, y
  if nm == 13 then nm, ny = 1, y + 1 end
  return os.date("*t", os.time { year = ny, month = nm, day = 0 }).day
end

local function weekday_su0(y, m, d)
  return os.date("*t", os.time { year = y, month = m, day = d }).wday - 1
end

local function build_weeks(y, m)
  local dim = days_in_month(y, m)
  local pm = (m == 1) and 12 or (m - 1)
  local py = (m == 1) and (y - 1) or y
  local prev_dim = days_in_month(py, pm)
  local nm = (m == 12) and 1 or (m + 1)
  local ny = (m == 12) and (y + 1) or y
  local first_col = weekday_su0(y, m, 1)
  local weeks, row = {}, {}

  for i = first_col, 1, -1 do
    row[#row + 1] = { day = prev_dim - i + 1, in_month = false, year = py, month = pm }
  end
  for d = 1, dim do
    row[#row + 1] = { day = d, in_month = true, year = y, month = m }
    if #row == 7 then weeks[#weeks + 1] = row; row = {} end
  end

  local next_day = 1
  if #row > 0 then
    while #row < 7 do
      row[#row + 1] = { day = next_day, in_month = false, year = ny, month = nm }
      next_day = next_day + 1
    end
    weeks[#weeks + 1] = row
  end

  local fill_month, fill_year = nm, ny
  while #weeks < 6 do
    local fill = {}
    for _ = 1, 7 do
      fill[#fill + 1] = { day = next_day, in_month = false, year = fill_year, month = fill_month }
      next_day = next_day + 1
      if next_day > days_in_month(fill_year, fill_month) then
        next_day = 1
        if fill_month == 12 then fill_month = 1; fill_year = fill_year + 1
        else fill_month = fill_month + 1 end
      end
    end
    weeks[#weeks + 1] = fill
  end

  return weeks
end

----------------------------------------------------------------
-- Legacy clean-suite display formats (date-time + calendar widgets)
----------------------------------------------------------------

function M.local_time_hms()
  return tostring(os.date("%H:%M:%S"))
end

-- "UTC 18:26 (CST -6)" — legacy date-time UTC line.
-- Offset formatted like the legacy awk: hours only, ":MM" when non-zero.
function M.utc_line()
  local zone = tostring(os.date("%Z"))
  local off  = tostring(os.date("%z"))  -- e.g. "-0600"
  local sign, hh, mm = off:match("^([%+%-])(%d%d)(%d%d)$")
  local off_txt = ""
  if sign then
    local h = tonumber(hh) or 0
    local m = tonumber(mm) or 0
    off_txt = (m == 0) and string.format("%s%d", sign, h)
      or string.format("%s%d:%02d", sign, h, m)
  end
  return string.format("UTC %s (%s %s)", tostring(os.date("!%H:%M")), zone, off_txt)
end

-- "2025.11.20" — legacy date-time date line.
function M.date_line()
  return tostring(os.date("%Y.%m.%d"))
end

-- Calendar month navigation offset — suite-local state, ported as-is
-- from the legacy cal_offset.txt (guide pitfall: Calendar Navigation Offset).
local function calendar_nav_offset()
  local f = io.open(DEFAULT_CACHE_ROOT .. "/suites/" .. SUITE_ID .. "/tme/cal_offset", "r")
  if not f then return 0 end
  local v = tonumber(f:read("*l")) or 0
  f:close()
  return v
end

-- Month view honoring the navigation offset.
-- Returns { title, weeks, today_day } where today_day is -1 when the
-- displayed month is not the current month.
function M.calendar_view()
  local now    = os.date("*t")
  local offset = calendar_nav_offset()
  local y, m   = now.year, now.month + offset
  while m > 12 do m = m - 12; y = y + 1 end
  while m <  1 do m = m + 12; y = y - 1 end
  return {
    title     = tostring(os.date("%B %Y", os.time { year = y, month = m, day = 1 })),
    weeks     = build_weeks(y, m),
    today_day = (y == now.year and m == now.month) and now.day or -1,
  }
end

return M
