-- lua/suite/msc.lua
-- MSC domain view model for gtex62-clean-suite-e.
-- Suite-local only: no core provider. Reads playerctl directly at draw time
-- for live music state; lyrics from suite cache. (Notes moved to its own
-- standalone view model, lua/suite/notes.lua.)

local M = {}

local HOME       = os.getenv("HOME") or ""
local SUITE_ID   = os.getenv("GTEX62_SUITE_ID") or "clean-e"
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local SUITE_CACHE_DIR = string.format("%s/suites/%s/msc", CACHE_ROOT, SUITE_ID)
local COVER_CACHE_DIR = SUITE_CACHE_DIR .. "/covers"

local PLAYER_CACHE = { tick = nil, data = nil }

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

local function read_file(path)
  if not path or path == "" then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function half_second_stamp()
  return math.floor(os.time() / 0.5)
end

local function read_player_state()
  local tick = half_second_stamp()
  if PLAYER_CACHE.tick == tick and PLAYER_CACHE.data ~= nil then
    return PLAYER_CACHE.data
  end

  local status = command_output("playerctl status 2>/dev/null")
  if not status or (status ~= "Playing" and status ~= "Paused") then
    PLAYER_CACHE.data  = { active = false, status = status or "Stopped" }
    PLAYER_CACHE.tick  = tick
    return PLAYER_CACHE.data
  end

  local meta_out = command_output(
    "playerctl metadata --format '{{title}}\t{{artist}}\t{{album}}\t{{position}}\t{{mpris:length}}' 2>/dev/null"
  )
  local title, artist, album, position_us, length_us = "", "", "", "0", "0"
  if meta_out then
    local parts = {}
    for field in (meta_out .. "\t"):gmatch("([^\t]*)\t") do
      parts[#parts + 1] = field
    end
    title      = normalize_spaces(parts[1] or "")
    artist     = normalize_spaces(parts[2] or "")
    album      = normalize_spaces(parts[3] or "")
    position_us = parts[4] or "0"
    length_us   = parts[5] or "0"
  end

  local position_s = (tonumber(position_us) or 0) / 1e6
  local length_s   = (tonumber(length_us) or 0)   / 1e6

  local volume_raw = command_output("playerctl volume 2>/dev/null")
  local volume_pct = math.floor(((tonumber(volume_raw) or 1.0) * 100) + 0.5)

  local data = {
    active       = true,
    status       = status,
    playing      = status == "Playing",
    title        = title  ~= "" and title  or "Unknown",
    artist       = artist ~= "" and artist or "Unknown",
    album        = album  ~= "" and album  or "Unknown",
    position_s   = position_s,
    length_s     = length_s,
    progress     = length_s > 0 and math.min(1.0, position_s / length_s) or 0,
    volume_pct   = volume_pct,
  }

  PLAYER_CACHE.data = data
  PLAYER_CACHE.tick = tick
  return data
end

local function cover_art_source_path()
  return command_output("playerctl metadata mpris:artUrl 2>/dev/null | sed 's|^file://||'")
end

local function mtime_str(path)
  return command_output(string.format("stat -c %%Y %q 2>/dev/null", path))
end

----------------------------------------------------------------
-- Public API: music
----------------------------------------------------------------

function M.is_active()
  return read_player_state().active
end

function M.player_status()
  return read_player_state().status or "Stopped"
end

function M.is_playing()
  return read_player_state().playing == true
end

function M.title()
  return read_player_state().title or ""
end

function M.artist()
  return read_player_state().artist or ""
end

function M.album()
  return read_player_state().album or ""
end

function M.progress_fraction()
  return read_player_state().progress or 0
end

function M.volume_percent()
  return read_player_state().volume_pct or 100
end

function M.position_seconds()
  return read_player_state().position_s or 0
end

function M.length_seconds()
  return read_player_state().length_s or 0
end

-- Returns the path of a uniquely-named cover copy that forces Conky's
-- ${image} directive to reload when the track changes.
-- Falls back to the suite's default icon if no cover art is available.
local LAST_COVER_MTIME = nil
local LAST_COVER_COPY  = nil

function M.cover_art_path()
  local src = cover_art_source_path()
  local fallback = HOME .. "/.config/conky/gtex62-shared-assets/icons/horn-of-odin.png"

  if not src or src == "" then
    return read_file(fallback) and fallback or nil
  end

  local mt = mtime_str(src)
  if mt and mt ~= LAST_COVER_MTIME then
    local dest = string.format("%s/cover_%s.png", COVER_CACHE_DIR, mt)
    command_output(string.format("mkdir -p %q && cp %q %q 2>/dev/null", COVER_CACHE_DIR, src, dest))
    -- Prune old copies asynchronously.
    command_output(string.format(
      "find %q -name 'cover_*.png' -not -name 'cover_%s.png' -delete 2>/dev/null &",
      COVER_CACHE_DIR, mt
    ))
    LAST_COVER_MTIME = mt
    LAST_COVER_COPY  = dest
  end

  return LAST_COVER_COPY or src
end

----------------------------------------------------------------
-- Public API: lyrics
----------------------------------------------------------------

local LYRICS_CACHE = { tick = nil, lines = nil, artist = nil, title = nil }

local function lyrics_cache_path(artist, title)
  if not artist or artist == "" or not title or title == "" then return nil end
  local safe = (artist .. "_" .. title):gsub("[^%w%-_]", "_"):gsub("_+", "_"):lower()
  return string.format("%s/lyrics/%s.txt", SUITE_CACHE_DIR, safe)
end

local function normalize_lyrics(lines, max_blank_run)
  local max_run = tonumber(max_blank_run) or 1
  local out, blank_run = {}, 0
  for _, line in ipairs(lines) do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
      blank_run = blank_run + 1
      if blank_run <= max_run then out[#out + 1] = "" end
    else
      blank_run = 0
      -- Strip LRC timestamps like [00:12.34]
      trimmed = trimmed:gsub("%[%d+:%d+%.%d+%]", ""):gsub("^%s+", "")
      out[#out + 1] = trimmed
    end
  end
  return out
end

function M.lyrics_lines(max_lines)
  local limit  = tonumber(max_lines) or 60
  local state  = read_player_state() or {}
  local active = state.active or false
  local artist = state.artist or ""
  local title  = state.title  or ""
  if not active then return { "(not playing)" } end
  local tick   = math.floor(os.time() / 30)

  if LYRICS_CACHE.tick == tick
    and LYRICS_CACHE.artist == artist
    and LYRICS_CACHE.title  == title
    and LYRICS_CACHE.lines  ~= nil then
    return LYRICS_CACHE.lines
  end

  local path = lyrics_cache_path(artist, title)
  local content = path and read_file(path) or nil

  local lines
  if content then
    local raw = {}
    for line in (content .. "\n"):gmatch("([^\r\n]*)\r?\n") do raw[#raw + 1] = line end
    lines = normalize_lyrics(raw, 1)
  else
    lines = { "(lyrics not found)" }
  end

  if #lines > limit then
    local truncated = {}
    for i = 1, limit do truncated[i] = lines[i] end
    lines = truncated
  end

  LYRICS_CACHE.tick   = tick
  LYRICS_CACHE.artist = artist
  LYRICS_CACHE.title  = title
  LYRICS_CACHE.lines  = lines
  return lines
end

function M.lyrics_header()
  local state  = read_player_state() or {}
  local active = state.active or false
  local artist = state.artist or ""
  local title  = state.title  or ""
  if not active then return "" end
  local a = artist ~= "" and artist or nil
  local t = title  ~= "" and title  or nil
  if a and t then return string.format("%s — %s", a, t) end
  return t or a or ""
end

return M
