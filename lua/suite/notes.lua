-- lua/suite/notes.lua
-- NOTES view model for gtex62-clean-suite-e.
-- Suite-local only: no core provider (per the conversion guide, notes
-- reads directly from a local flat text file, same as the legacy widget).
-- Legacy pipeline was:  fold -s -w 39 file | sed -n "1,90p"  via execi 3.
-- Reproduced here in pure Lua: word wrap at wrap_chars columns breaking
-- after the last blank (hard break when a segment has no blank), first
-- max_lines lines only, re-read every refresh_s seconds.
-- The notes file is ASCII with no tabs; tab-stop column arithmetic from
-- fold(1) is intentionally not reproduced.

local M = {}

local HOME       = os.getenv("HOME") or ""
local NOTES_FILE = os.getenv("CLEAN_NOTES_FILE") or (HOME .. "/Documents/conky-notes.txt")

local CACHE = { tick = nil, lines = nil }

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- fold -s -w width semantics for one raw line: break so each output
-- segment is <= width columns, splitting after the last blank in the
-- segment; the blank stays at the end of the broken segment. Hard
-- break at width when the segment contains no blank.
local function fold_line(line, width, out, limit)
  while #line > width do
    if #out >= limit then return end
    local seg = line:sub(1, width)
    local brk = seg:match("^.*()[ \t]") -- position of last blank, or nil
    if brk and brk > 1 then
      out[#out + 1] = line:sub(1, brk)
      line = line:sub(brk + 1)
    else
      out[#out + 1] = seg
      line = line:sub(width + 1)
    end
  end
  if #out < limit then out[#out + 1] = line end
end

-- Returns up to opts.max wrapped lines from the notes file.
-- opts = { wrap = chars per line, max = line cap, refresh = seconds }.
-- Missing/empty file renders nothing, matching the legacy execi behavior.
function M.lines(opts)
  local wrap    = tonumber(opts and opts.wrap)    or 39
  local max_l   = tonumber(opts and opts.max)     or 90
  local refresh = tonumber(opts and opts.refresh) or 3

  local tick = math.floor(os.time() / refresh)
  if CACHE.tick == tick and CACHE.lines ~= nil then
    return CACHE.lines
  end

  local out = {}
  local content = read_file(NOTES_FILE)
  if content and content ~= "" then
    if not content:match("\n$") then content = content .. "\n" end
    for line in content:gmatch("([^\r\n]*)\r?\n") do
      fold_line(line, wrap, out, max_l)
      if #out >= max_l then break end
    end
  end

  CACHE.tick, CACHE.lines = tick, out
  return out
end

return M
