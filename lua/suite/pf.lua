-- lua/suite/pf.lua
-- PF (pfSense) domain view model for gtex62-clean-suite-e.
-- Serves the standalone VLAN traffic-flow arc widget ONLY (conversion guide
-- §1.4 split): CPU/MEM/gateway/pfBlockerNG/Pi-hole/AP status belong to the
-- core sitrep utility and are deliberately not exposed here.
--
-- Data source: shared/pfsense/{profile}/ifaces.json — the core provider's
-- fast (~1s) interface byte-counter poller (fetch_pfsense_ifaces.sh), not
-- status.json, whose interfaces block only refreshes on the 60s cycle.
-- Rates arrive server-side (rate_ibytes_per_sec / rate_obytes_per_sec);
-- a null rate means cold start, counter wrap, or a degraded stub, and the
-- EMA simply does not step for that sample.
--
-- One jq call per second (tick-cached); EMA steps only when a VLAN's
-- fetched_at advances, and is applied to the scaled (0..1) value after the
-- response curve — smoothing raw bytes/sec and then compressing through a
-- nonlinear curve is a different curve than smoothing after it.

local M = {}

local HOME         = os.getenv("HOME") or ""
local SUITE_ID     = os.getenv("GTEX62_SUITE_ID") or "clean-e"
local CACHE_ROOT   = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")

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
          if section then out[section][key] = value
          else            out[key] = value
          end
        end
      end
    end
  end
  return out
end

local function json_query(path, filter)
  if not read_file(path) then return nil end
  local out = command_output(string.format("jq -r %q %q 2>/dev/null", filter, path))
  if not out or out == "null" or out == "" then return nil end
  return out
end

local IFACES_PATH

local function ifaces_json_path()
  if not IFACES_PATH then
    local cfg     = parse_simple_toml(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml")
    local profile = ((cfg.profiles or {}).pfsense) or "main_router"
    IFACES_PATH   = string.format("%s/shared/pfsense/%s/ifaces.json", CACHE_ROOT, profile)
  end
  return IFACES_PATH
end

local function clamp01(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 elseif v > 1 then return 1 else return v end
end

----------------------------------------------------------------
-- Nonlinear response curve (linear | sqrt | log), ported from the legacy
-- pf_widget.lua scale_pct() — pure function. Per-VLAN floor (Mbps) is
-- subtracted before normalizing by the per-direction link cap, then the
-- configured curve is applied. scale_cfg is panels.pfsense.scale.
----------------------------------------------------------------
local function scale_pct(mbps, link_mbps, scale_cfg, vlan)
  local link = tonumber(link_mbps or 1000) or 1000
  if link <= 0 then return 0 end

  scale_cfg = scale_cfg or {}
  local floors     = scale_cfg.floors_mbps or {}
  local floor_mbps = tonumber(floors[vlan or "WAN"] or 0) or 0
  local adj        = (tonumber(mbps) or 0) - floor_mbps
  if adj < 0 then adj = 0 end

  local norm = clamp01(adj / link)

  local mode = scale_cfg.mode or "linear"
  if mode == "linear" then
    return norm
  elseif mode == "sqrt" then
    local gamma = tonumber((scale_cfg.sqrt or {}).gamma) or 0.5
    if gamma <= 0 then gamma = 0.5 end
    return norm ^ gamma
  elseif mode == "log" then
    local log_cfg  = scale_cfg.log or {}
    local base     = tonumber(log_cfg.base) or 10.0
    local min_norm = tonumber(log_cfg.min_norm) or 0.001
    if base < 1.001 then base = 10.0 end
    local nn = norm
    if nn > 0 and nn < min_norm then nn = min_norm end
    local num = math.log(1 + (base - 1) * nn)
    local den = math.log(base)
    return clamp01((den ~= 0) and (num / den) or nn)
  end
  return norm
end

----------------------------------------------------------------
-- Tick-cached ifaces.json read
----------------------------------------------------------------
local CACHE = { tick = nil, order_sig = nil, filter = nil, fields = nil }

local function build_filter(order)
  local parts = {}
  for _, vlan in ipairs(order) do
    parts[#parts + 1] = string.format(
      ".interfaces.%s.rate_ibytes_per_sec, .interfaces.%s.rate_obytes_per_sec, .interfaces.%s.fetched_at",
      vlan, vlan, vlan)
  end
  return "[" .. table.concat(parts, ", ") .. "]"
    .. ' | map(if . == null then "null" else . end) | @tsv'
end

local function refresh(order)
  local tick = os.time()
  local sig  = table.concat(order, ",")
  if CACHE.tick == tick and CACHE.order_sig == sig then return end
  CACHE.tick = tick
  if CACHE.order_sig ~= sig then
    CACHE.filter    = build_filter(order)
    CACHE.order_sig = sig
  end

  local out = json_query(ifaces_json_path(), CACHE.filter)
  if not out then
    CACHE.fields = nil
    return
  end

  local fields = {}
  for field in (out .. "\t"):gmatch("([^\t]*)\t") do
    fields[#fields + 1] = field
  end
  CACHE.fields = fields
end

-- EMA state, keyed by VLAN. Steps only on a new fetched_at sample from
-- core — core's poll cadence is independent of conky's redraw cadence.
local ema_in, ema_out, ema_seen_at = {}, {}, {}

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Returns { [vlan] = { in_frac = 0..1, out_frac = 0..1 } } for every VLAN
-- in cfg.iface_order, EMA-smoothed and curve-scaled for direct use as arc
-- marker positions. cfg is panels.pfsense (iface_order, smoothing.alpha,
-- scale, link_mbps_in, link_mbps_out).
function M.flow_fractions(cfg)
  cfg = cfg or {}
  local order     = cfg.iface_order or { "WAN", "HOME", "IOT", "GUEST", "INFRA", "CAM" }
  local alpha     = clamp01(tonumber((cfg.smoothing or {}).alpha) or 0.35)
  local scale_cfg = cfg.scale or {}
  local link_in   = cfg.link_mbps_in or {}
  local link_out  = cfg.link_mbps_out or {}

  refresh(order)
  local fields = CACHE.fields

  local flow = {}
  for i, vlan in ipairs(order) do
    local base       = (i - 1) * 3
    local in_bps     = fields and tonumber(fields[base + 1])
    local out_bps    = fields and tonumber(fields[base + 2])
    local fetched_at = fields and tonumber(fields[base + 3])

    if ema_in[vlan] == nil then ema_in[vlan] = 0 end
    if ema_out[vlan] == nil then ema_out[vlan] = 0 end

    if fetched_at and fetched_at ~= ema_seen_at[vlan] then
      if in_bps then
        local pct = scale_pct(in_bps * 8 / 1e6, tonumber(link_in[vlan]) or 1000, scale_cfg, vlan)
        ema_in[vlan] = alpha * pct + (1 - alpha) * ema_in[vlan]
      end
      if out_bps then
        local pct = scale_pct(out_bps * 8 / 1e6, tonumber(link_out[vlan]) or 1000, scale_cfg, vlan)
        ema_out[vlan] = alpha * pct + (1 - alpha) * ema_out[vlan]
      end
      ema_seen_at[vlan] = fetched_at
    end

    flow[vlan] = { in_frac = ema_in[vlan], out_frac = ema_out[vlan] }
  end

  return flow
end

return M
