---@diagnostic disable: need-check-nil, param-type-mismatch
-- lua/suite/msc.lua
-- MSC + LYRICS view model for gtex62-clean-suite-e.
-- Split domain (audited 2026-08-28, see the recovery runbook):
--   • Playback state, volume/mute, cover art — suite-local: read from
--     playerctl/pactl at draw time (no core provider; conversion guide
--     §1.2 keeps media-player state suite-local).
--   • Lyrics — CORE media domain: providers/media/fetch_lyrics.py
--     writes shared/media/[profile]/lyrics.json with display-ready
--     lines (LRC timestamps already stripped provider-side). This
--     module only READS that file — no fetching, no library access;
--     gtex62-core/docs/lyrics-library-design.md owns all of that.
--
-- Album Art Image Reload pitfall (conversion guide) — resolved
-- differently here: the legacy mtime-named-copy workaround existed
-- only to defeat Conky's ${image} no-hot-reload. The Cairo port has
-- no ${image} (blank conky.text), so a single reused cache filename
-- is fine; the new constraint is that Cairo loads PNG only, so the
-- cover (often JPEG via mpris:artUrl) is converted with ImageMagick
-- when the track's art changes, into covers/current.png.

local M = {}

local HOME               = os.getenv("HOME") or ""
local SUITE_ID           = os.getenv("GTEX62_SUITE_ID") or "clean-e"
local DEFAULT_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local RUNTIME_ROOT       = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local ASSETS_DIR         = os.getenv("GTEX62_SHARED_ASSETS_DIR") or (HOME .. "/.config/conky/gtex62-shared-assets")

local FALLBACK_ART       = ASSETS_DIR .. "/icons/horn-of-odin.png"

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

-- Media profile: launcher default is "local" (gtex62-core-launch
-- MEDIA_PROFILE fallback); suites/clean-e.toml [profiles] media
-- overrides it if present.
local MEDIA_PROFILE = (parse_simple_toml(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml").profiles or {}).media or "local"
local LYRICS_JSON   = string.format("%s/shared/media/%s/lyrics.json", DEFAULT_CACHE_ROOT, MEDIA_PROFILE)

local SUITE_CACHE_DIR = string.format("%s/suites/%s/msc", DEFAULT_CACHE_ROOT, SUITE_ID)
local COVER_DIR       = SUITE_CACHE_DIR .. "/covers"
local COVER_PNG       = COVER_DIR .. "/current.png"

----------------------------------------------------------------
-- Player state (playerctl; 1 s tick cache — legacy update_interval 1)
----------------------------------------------------------------

local PLAYER_CACHE = { tick = nil, data = nil }

local function read_player_state()
  local tick = os.time()
  if PLAYER_CACHE.tick == tick and PLAYER_CACHE.data ~= nil then
    return PLAYER_CACHE.data
  end

  -- One playerctl call for everything it can format; fails (nil) when
  -- no MPRIS player exists.
  local out = command_output(
    "playerctl metadata --format '{{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{position}}\t{{mpris:length}}\t{{volume}}\t{{mpris:artUrl}}' 2>/dev/null"
  )

  local status = ""
  local parts  = {}
  if out then
    for field in (out .. "\t"):gmatch("([^\t]*)\t") do
      parts[#parts + 1] = field
    end
    status = parts[1] or ""
  end

  if status ~= "Playing" and status ~= "Paused" then
    -- Volume/mute still shown while idle (legacy drew the red marker
    -- from the pactl fallback with no player running — see music1.png)
    local volume_frac = nil
    local pac = command_output("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null")
    local pct = pac and pac:match("(%d+)%%")
    if pct then volume_frac = math.max(0, math.min(1, tonumber(pct) / 100)) end
    local muted = nil
    local mo = command_output("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null")
    if mo then
      if mo:match("yes") then muted = true elseif mo:match("no") then muted = false end
    end
    PLAYER_CACHE.data = {
      active      = false,
      status      = (status ~= "" and status) or "Stopped",
      volume_frac = volume_frac,
      muted       = muted,
    }
    PLAYER_CACHE.tick = tick
    return PLAYER_CACHE.data
  end

  local title       = normalize_spaces(parts[2] or "")
  local artist      = normalize_spaces(parts[3] or "")
  local album       = normalize_spaces(parts[4] or "")
  local position_us = tonumber(parts[5]) or 0
  local length_us   = tonumber(parts[6]) or 0
  local volume_raw  = tonumber(parts[7])
  local art_url     = parts[8] or ""

  -- System output volume (pactl) is the source of truth — it's what the
  -- idle path below shows and what actually moves when the user changes
  -- volume via system controls. A player's own MPRIS `volume` is that
  -- player's internal software gain, which can silently diverge from
  -- the sink volume (verified live: VLC's reported volume held constant
  -- across three different pactl sink levels) — use it only as a
  -- fallback when pactl itself is unavailable.
  local volume_frac = nil
  local pac = command_output("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null")
  local pct = pac and pac:match("(%d+)%%")
  if pct then
    volume_frac = math.max(0, math.min(1, tonumber(pct) / 100))
  elseif volume_raw then
    if volume_raw > 1 then volume_raw = volume_raw / 100 end
    volume_frac = math.max(0, math.min(1, volume_raw))
  end

  -- Mute state (legacy get_is_muted; nil = unknown)
  local muted = nil
  local mo = command_output("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null")
  if mo then
    if mo:match("yes") then muted = true elseif mo:match("no") then muted = false end
  end

  local position_s = position_us / 1e6
  local length_s   = length_us / 1e6
  if length_s < position_s then length_s = position_s end -- legacy guard

  local data = {
    active      = true,
    status      = status,
    playing     = status == "Playing",
    title       = title,
    artist      = artist,
    album       = album,
    position_s  = position_s,
    length_s    = length_s,
    progress    = length_s > 0 and math.min(1.0, position_s / length_s) or 0,
    volume_frac = volume_frac,
    muted       = muted,
    art_url     = art_url,
  }

  PLAYER_CACHE.data = data
  PLAYER_CACHE.tick = tick
  return data
end

function M.player()
  return read_player_state()
end

-- Format seconds as M:SS (legacy fmt_clock_ms)
function M.fmt_clock(sec)
  sec = tonumber(sec)
  if not sec or sec <= 0 or sec ~= sec then return "0:00" end
  local s = math.floor(sec + 0.5)
  local m = math.floor(s / 60); s = s % 60
  return string.format("%d:%02d", m, s)
end

----------------------------------------------------------------
-- Visibility linger (legacy conky_music_visible / conky_lyrics_visible:
-- visible while Playing/Paused, stays for idle_hide_after_s after stop)
----------------------------------------------------------------

local LAST_SEEN = os.time()

function M.seen_within(idle_hide_after_s)
  local now = os.time()
  if read_player_state().active then
    LAST_SEEN = now
    return true
  end
  return (now - LAST_SEEN) < (tonumber(idle_hide_after_s) or 10)
end

----------------------------------------------------------------
-- Cover art (suite-local). Converts the current track's art to PNG
-- (Cairo can only load PNG) at covers/current.png, re-converting only
-- when the art source changes. Returns a PNG path, the fallback icon
-- when idle / artless / conversion failed.
----------------------------------------------------------------

local COVER_STATE = { key = nil, path = nil }

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function M.cover_path()
  local p = read_player_state()
  if not p.active then return FALLBACK_ART end

  local url = p.art_url or ""
  if url == "" then return FALLBACK_ART end

  local key = url
  local src = nil
  if url:match("^file://") then
    src = url_decode(url:gsub("^file://", ""))
    -- include mtime so an in-place art file update re-converts
    local mt = command_output(string.format("stat -c %%Y %q 2>/dev/null", src))
    key = url .. "@" .. (mt or "")
  end

  if COVER_STATE.key == key then
    return COVER_STATE.path or FALLBACK_ART
  end

  command_output(string.format("mkdir -p %q 2>/dev/null; echo ok", COVER_DIR))
  local ok = nil
  if src then
    -- local file (any format) → small PNG
    ok = command_output(string.format(
      "convert %q -resize '128x128>' png:%q 2>/dev/null && echo ok", src, COVER_PNG))
  elseif url:match("^https?://") then
    local tmp = COVER_DIR .. "/download.tmp"
    ok = command_output(string.format(
      "curl -LfsS --max-time 8 %q -o %q 2>/dev/null && convert %q -resize '128x128>' png:%q 2>/dev/null && rm -f %q && echo ok",
      url, tmp, tmp, COVER_PNG, tmp))
  end

  COVER_STATE.key  = key
  COVER_STATE.path = (ok == "ok") and COVER_PNG or FALLBACK_ART
  return COVER_STATE.path
end

----------------------------------------------------------------
-- Lyrics (core media domain). One jq call per tick against
-- lyrics.json; blank runs collapsed to max_blank_run at display time
-- (legacy normalize_blank_lines behavior — cheap and idempotent even
-- if the provider already collapsed them).
----------------------------------------------------------------

local LYRICS_CACHE = { tick = nil, data = nil }

local function collapse_blanks(lines, max_run)
  max_run = tonumber(max_run) or 1
  local out, run = {}, 0
  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      run = run + 1
      if run <= max_run then out[#out + 1] = "" end
    else
      run = 0
      out[#out + 1] = line
    end
  end
  -- drop leading/trailing blanks
  while out[1] == "" do table.remove(out, 1) end
  while out[#out] == "" do table.remove(out) end
  return out
end

-- Returns { state, artist, title, source, library_path, lines }.
-- state passes through the provider's values (ok / inactive / no_track /
-- not_found / offline / instrumental), plus "searching" when the live
-- player track doesn't match lyrics.json's track yet (the provider's
-- refresh cadence lags a track change; legacy showed "Searching…" while
-- its own fetch was throttled — same user-facing meaning).
function M.lyrics(max_blank_run)
  local tick = math.floor(os.time() / 2)
  local data
  if LYRICS_CACHE.tick == tick and LYRICS_CACHE.data ~= nil then
    data = LYRICS_CACHE.data
  else
    data = { state = "inactive", artist = "", title = "", source = "", library_path = "", lines = {} }
    -- Parens around the @tsv pipe matter: jq's comma binds tighter than
    -- an unparenthesized trailing pipe target, so without them .lines
    -- gets applied to the constructed header array (an error).
    local out = command_output(string.format(
      "jq -r '([.state // \"\", .track.artist // \"\", .track.title // \"\", .source // \"\", .library_path // \"\"] | @tsv), (.lines[]? | tostring)' %q 2>/dev/null",
      LYRICS_JSON))
    if out then
      local first = true
      local lines = {}
      for line in (out .. "\n"):gmatch("([^\n]*)\n") do
        if first then
          local f = {}
          for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
          data.state        = f[1] or ""
          data.artist       = f[2] or ""
          data.title        = f[3] or ""
          data.source       = f[4] or ""
          data.library_path = f[5] or ""
          first = false
        else
          lines[#lines + 1] = line
        end
      end
      data.lines = collapse_blanks(lines, max_blank_run or 1)
    end
    LYRICS_CACHE.tick = tick
    LYRICS_CACHE.data = data
  end

  -- Track-change lag detection against the live player: whatever state
  -- lyrics.json is in, if it isn't about the track playing NOW (covers
  -- "inactive" right after playback starts, and a previous track's
  -- ok/not_found), the provider just hasn't caught up yet.
  local p = read_player_state()
  if p.active
      and (data.artist ~= (p.artist or "") or data.title ~= (p.title or "")) then
    local copy = {}
    for k, v in pairs(data) do copy[k] = v end
    copy.state = "searching"
    copy.lines = {}
    return copy
  end
  return data
end

-- Header text from the LIVE player metadata (legacy fmt_header on
-- playerctl meta — not from lyrics.json, so it is current even while
-- the provider is catching up to a track change).
function M.lyrics_header()
  local p = read_player_state()
  if not p.active then return "" end
  local a = (p.artist ~= "" and p.artist) or nil
  local t = (p.title ~= "" and p.title) or nil
  if a and t then return string.format("%s — %s", a, t) end
  return t or a or ""
end

return M
