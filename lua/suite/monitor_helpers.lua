---@diagnostic disable: undefined-global
-- lua/suite/monitor_helpers.lua
-- View model for the clean-monitor chassis (SYS + NET). Consumed by
-- lua/ui/frame.lua draw_monitor via lua/widgets/clean_monitor.lua.
--
-- SYS half: reads the core system provider caches —
--   shared/system/[profile]/current.json     identity + live CPU/RAM/GPU telemetry
--   shared/system/[profile]/processes.json   top-N by CPU and by resident memory
--   shared/system/[profile]/storage.json     filesystem rows (/ROOT, /WD, ...)
-- No Conky built-ins, no direct nvidia-smi/df/proc probing — core owns the data.
--
-- NET half: reads the core network/net caches —
--   shared/network/[profile]/current.json interface, WAN/LAN IPs, DNS, VLANs
--   shared/net/[profile]/state.vars       ping probes (1.1.1.1 / 8.8.8.8) — net's
--     own independent ping (CF_1111_MS / GOOGLE_8888_MS), not connectivity's;
--     matches gtex62-osa's pattern. See docs/net-provider.md: net is the
--     "display-ready projection layer," refreshed at 1s: connectivity's own
--     ping output has no consumer anywhere in the codebase (confirmed).
-- Fast lane (guide §4.2 — live telemetry read directly at draw time):
--   LAN link state from /sys/class/net/<iface>/operstate
--   throughput rates + graph history from /sys/class/net/<iface>/statistics
--
-- Each cache file is parsed once per second via a single jq call (tick cache),
-- not one jq per field per draw.
--
-- Profile resolution: same as every other view model in this suite (orb.lua,
-- wxr.lua, pf.lua, msc.lua, tme.lua) — read [profiles] out of the suite's
-- runtime TOML, not env vars. system/network/net profiles used to be a
-- hardcoded-copy-that-happens-to-match-config (system/connectivity via env
-- vars nothing exported, network path hardcoded outright); see the recovery
-- runbook's F2 note for the full history, including why the net profile's
-- own env-var override (added when the ping reader moved to
-- shared/net/<profile>/state.vars) is folded in here too rather than kept as
-- an exception — docs/net-provider.md's own Suite Consumption section says
-- net's profile is resolved "from their suite TOML [profiles] net key",
-- same as every other domain.

local HOME         = os.getenv("HOME") or ""
local SUITE_ID     = os.getenv("GTEX62_SUITE_ID") or "clean-e"
local CACHE_ROOT   = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR")
  or (HOME .. "/.cache/gtex62-core")
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR")
  or (HOME .. "/.config/gtex62-core")

local M = {}

----------------------------------------------------------------
-- Utils
----------------------------------------------------------------

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

-- Same minimal parser every other suite view model carries locally
-- (pf.lua, wxr.lua, msc.lua, tme.lua) — not shared, per this codebase's
-- standing convention of one small copy per module rather than a shared
-- require target.
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

local SUITE_PROFILES = parse_simple_toml(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml").profiles or {}

local SYS_PROFILE     = SUITE_PROFILES.system or "local"
local NETWORK_PROFILE = SUITE_PROFILES.network or "local"
local NET_PROFILE     = SUITE_PROFILES.net or "local"

local SYS_DIR         = CACHE_ROOT .. "/shared/system/" .. SYS_PROFILE .. "/"
local NET_JSON        = CACHE_ROOT .. "/shared/network/" .. NETWORK_PROFILE .. "/current.json"
local NET_STATE_VARS  = CACHE_ROOT .. "/shared/net/" .. NET_PROFILE .. "/state.vars"

local function read_first_line(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  return s
end

local function cut_with_ellipsis(s, maxch)
  local m = tonumber(maxch) or 26
  s = tostring(s or "")
  if #s > m and m >= 1 then return s:sub(1, m - 1) .. "…" end
  return s
end

-- Conky-style IEC size: "468GiB", "93.9GiB", "3.64TiB"
local function human_size(bytes)
  local v = tonumber(bytes)
  if not v or v < 0 then return "-" end
  local units = { { "TiB", 1024 ^ 4 }, { "GiB", 1024 ^ 3 }, { "MiB", 1024 ^ 2 }, { "KiB", 1024 } }
  for _, u in ipairs(units) do
    if v >= u[2] then
      local n = v / u[2]
      if n >= 100 then return string.format("%.0f%s", n, u[1]) end
      if n >= 10 then return string.format("%.1f%s", n, u[1]) end
      return string.format("%.2f%s", n, u[1])
    end
  end
  return string.format("%.0fB", v)
end

-- Conky ${top_mem mem_res} style: MiB below 1 GiB, else GiB
local function human_mem_res(bytes)
  local v = tonumber(bytes)
  if not v or v < 0 then return "-" end
  if v >= 1024 ^ 3 then return string.format("%.2fGiB", v / 1024 ^ 3) end
  return string.format("%.0fMiB", v / 1024 ^ 2)
end

----------------------------------------------------------------
-- SYS cache readers (core system domain)
----------------------------------------------------------------

local SYS = { tick = nil, kv = {}, top_cpu = {}, top_mem = {}, fs = {}, available = false }

local SYS_CUR_JQ = [[
  "OS_NAME=\(.os.name // "-")",
  "HOSTNAME=\(.hostname // "-")",
  "USER=\(.user // "-")",
  "KERNEL=\(.kernel.release_full // .kernel.release // "-")",
  "CPU_PCT=\(.cpu.usage_percent // 0)",
  "MEM_PCT=\(.memory.usage_percent // 0)",
  "CPU_MODEL=\(.cpu.model // "-")",
  "GPU_MODEL=\(.gpu.model // "")",
  "GPU_DRIVER=\(.gpu.driver_version // "-")",
  "GPU_PCT=\(.gpu.usage_percent // 0)",
  "GPU_TEMP=\(.gpu.temperature_c // 0)",
  "GPU_POWER=\(.gpu.power_w // 0)",
  "VRAM_USED=\(.gpu.memory.used_mb // 0)",
  "VRAM_TOTAL=\(.gpu.memory.total_mb // 0)",
  "MBD=\(.motherboard.name // "-")",
  "BIOS=\(.bios.version // "-")"
]]

local SYS_PROC_JQ = [[
  (.top_cpu[]? | "TOPCPU=\(.name)|\(.cpu_percent)"),
  (.top_mem[]? | "TOPMEM=\(.name)|\(.rss_bytes)")
]]

local SYS_STOR_JQ = [[
  .filesystems[]? | "FS=\(.label)|\(.size_bytes)|\(.used_bytes)|\(.avail_bytes)|\(.use_percent)"
]]

local function refresh_sys()
  local tick = os.time()
  if SYS.tick == tick then return end
  SYS.tick    = tick
  SYS.kv      = {}
  SYS.top_cpu = {}
  SYS.top_mem = {}
  SYS.fs      = {}

  local out = command_output(string.format("jq -r %q %q 2>/dev/null", SYS_CUR_JQ, SYS_DIR .. "current.json"))
  SYS.available = out ~= nil
  if out then
    for line in out:gmatch("[^\r\n]+") do
      local key, value = line:match("^([A-Z_]+)=(.*)$")
      if key then SYS.kv[key] = value end
    end
  end

  local pout = command_output(string.format("jq -r %q %q 2>/dev/null", SYS_PROC_JQ, SYS_DIR .. "processes.json"))
  if pout then
    for line in pout:gmatch("[^\r\n]+") do
      local key, value = line:match("^([A-Z]+)=(.*)$")
      local name, num = (value or ""):match("^(.*)|([^|]*)$")
      if key == "TOPCPU" and name then
        SYS.top_cpu[#SYS.top_cpu + 1] = { name = name, num = tonumber(num) or 0 }
      elseif key == "TOPMEM" and name then
        SYS.top_mem[#SYS.top_mem + 1] = { name = name, num = tonumber(num) or 0 }
      end
    end
  end

  local sout = command_output(string.format("jq -r %q %q 2>/dev/null", SYS_STOR_JQ, SYS_DIR .. "storage.json"))
  if sout then
    for line in sout:gmatch("[^\r\n]+") do
      local label, size, used, avail, pct =
        line:match("^FS=([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
      if label then
        SYS.fs[label] = {
          size = tonumber(size), used = tonumber(used),
          avail = tonumber(avail), pct = tonumber(pct),
        }
      end
    end
  end
end

local function sys_value(key, fallback)
  refresh_sys()
  local v = SYS.kv[key]
  if v == nil or v == "" or v == "null" then return fallback end
  return v
end

local function sys_number(key)
  return tonumber(sys_value(key, nil)) or 0
end

----------------------------------------------------------------
-- SYS public API
----------------------------------------------------------------

function M.sys_available()
  refresh_sys()
  return SYS.available
end

function M.os_name()  return sys_value("OS_NAME", "-") end
function M.hostname() return sys_value("HOSTNAME", "-") end
function M.user()     return sys_value("USER", "-") end
function M.kernel()   return sys_value("KERNEL", "-") end

function M.cpu_percent() return sys_number("CPU_PCT") end
function M.ram_percent() return sys_number("MEM_PCT") end

function M.gpu_present()
  return sys_value("GPU_MODEL", "") ~= ""
end

function M.gpu_percent() return sys_number("GPU_PCT") end
function M.gpu_driver()  return sys_value("GPU_DRIVER", "-") end
function M.gpu_temp()    return sys_number("GPU_TEMP") end
function M.gpu_power()   return sys_number("GPU_POWER") end

function M.vram_percent()
  local used, total = sys_number("VRAM_USED"), sys_number("VRAM_TOTAL")
  if total <= 0 then return 0 end
  return (used * 100) / total
end

function M.cpu_model() return sys_value("CPU_MODEL", "-") end
function M.gpu_model() return sys_value("GPU_MODEL", "-") end
function M.mbd()       return sys_value("MBD", "-") end
function M.bios()      return sys_value("BIOS", "-") end

-- Legacy disk table rows: display label + preformatted value columns.
-- Legacy widget showed / as "/root" and /mnt/WD_Black as "/WD_Black";
-- the provider labels those rows /ROOT and /WD (see docs/system-schema.md).
local DISK_ROWS = {
  { cache_label = "/ROOT", display = "/root" },
  { cache_label = "/WD",   display = "/WD_Black" },
}

function M.disk_rows(rows)
  refresh_sys()
  local out = {}
  for _, spec in ipairs(rows or DISK_ROWS) do
    local fs = SYS.fs[spec.cache_label]
    out[#out + 1] = {
      label  = spec.display,
      values = fs and string.format("%7s | %7s | %7s | %d%%",
        human_size(fs.size), human_size(fs.used), human_size(fs.avail), fs.pct or 0)
        or "      - |       - |       - | -",
    }
  end
  return out
end

function M.top_cpu_rows(n, maxch)
  refresh_sys()
  local out = {}
  for i = 1, math.min(tonumber(n) or 5, #SYS.top_cpu) do
    local row = SYS.top_cpu[i]
    out[#out + 1] = {
      name  = cut_with_ellipsis(row.name, maxch),
      value = string.format("%.2f%%", row.num),
    }
  end
  return out
end

function M.top_mem_rows(n, maxch)
  refresh_sys()
  local out = {}
  for i = 1, math.min(tonumber(n) or 5, #SYS.top_mem) do
    local row = SYS.top_mem[i]
    out[#out + 1] = {
      name  = cut_with_ellipsis(row.name, maxch),
      value = human_mem_res(row.num),
    }
  end
  return out
end

----------------------------------------------------------------
-- NET cache readers (core network + connectivity domains)
----------------------------------------------------------------

local NET = { tick = nil, kv = {}, vlans = {}, pings = {} }

local NET_JQ = [[
  "IFACE=\(.interface.name // "eno1")",
  "TITLE=\(.interface.title // .interface.name // "NIC UNKNOWN")",
  "IS_ONLINE=\(if .interface.is_online then 1 else 0 end)",
  "LAN_IP=\(.interface.lan_ip // "-")",
  "DNS=\(.interface.dns // "-")",
  "SUBNET=\(.interface.subnet // "-")",
  "GATEWAY=\(.interface.gateway // "-")",
  "WAN_IP=\(.interface.wan_ip // "-")",
  (.vlan_hosts[]? | "VLAN=\(.label)|\(.host)|\(.ms // "")|\(if .reachable then 1 else 0 end)")
]]

-- net's own independent ping (state.vars key=value, no jq needed) — not
-- connectivity's .ping{} object, which has no consumer anywhere in the suite.
local NET_PING_HOST_KEY = {
  ["1.1.1.1"] = "CF_1111_MS",
  ["8.8.8.8"] = "GOOGLE_8888_MS",
}

local function refresh_net()
  local tick = os.time()
  if NET.tick == tick then return end
  NET.tick  = tick
  NET.kv    = {}
  NET.vlans = {}
  NET.pings = {}

  local out = command_output(string.format("jq -r %q %q 2>/dev/null", NET_JQ, NET_JSON))
  if out then
    for line in out:gmatch("[^\r\n]+") do
      local key, value = line:match("^([A-Z_]+)=(.*)$")
      if key == "VLAN" then
        local label, host, ms, reach = value:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
        if label then
          NET.vlans[#NET.vlans + 1] = {
            label = label, host = host,
            ms = tonumber(ms), reachable = (reach == "1"),
          }
        end
      elseif key then
        NET.kv[key] = value
      end
    end
  end

  local state_kv = {}
  local sf = io.open(NET_STATE_VARS, "r")
  if sf then
    local contents = sf:read("*a") or ""
    sf:close()
    for line in contents:gmatch("[^\r\n]+") do
      local key, value = line:match("^([A-Za-z0-9_]+)=(.*)$")
      if key then state_kv[key] = value end
    end
  end
  for host, state_key in pairs(NET_PING_HOST_KEY) do
    local ms = tonumber(state_kv[state_key])
    NET.pings[host] = { ms = ms, reachable = ms ~= nil }
  end
end

local function net_value(key, fallback)
  refresh_net()
  local v = NET.kv[key]
  if v == nil or v == "" or v == "null" then return fallback end
  return v
end

----------------------------------------------------------------
-- NET public API
----------------------------------------------------------------

function M.net_iface_title()
  return net_value("TITLE", "NIC UNKNOWN")
end

-- Internet reachability from the network provider (legacy wan_status).
function M.net_wan_status()
  return net_value("IS_ONLINE", "0") == "1" and "Online" or "Offline"
end

function M.net_wan_ip()
  return net_value("WAN_IP", "—")
end

-- Fast lane: physical link state of the primary interface (legacy lan_status).
function M.net_lan_status()
  local iface = net_value("IFACE", "eno1")
  local state = read_first_line("/sys/class/net/" .. iface .. "/operstate")
  return (state == "up") and "Online" or "Offline"
end

function M.net_lan_ip()  return net_value("LAN_IP", "—") end
function M.net_dns()     return net_value("DNS", "—") end
function M.net_subnet()  return net_value("SUBNET", "—") end

function M.net_ping(host)
  refresh_net()
  local p = NET.pings[host]
  if not p or not p.reachable or not p.ms then return "down" end
  return string.format("%g ms", p.ms)
end

-- VLAN gateway rows (legacy vlan_lines):
--   name "VLAN10(Home)", gateway IP, rtt "(0.234 ms)" or "(down)".
-- is_home marks the gateway of the primary interface (legacy VLAN10
-- highlight — rendered in the accent color by frame.lua).
function M.net_vlan_rows()
  refresh_net()
  local home_gw = NET.kv["GATEWAY"]
  local rows = {}
  for _, v in ipairs(NET.vlans) do
    local octet = (v.host or ""):match("^%d+%.%d+%.(%d+)%.%d+$")
    local pretty = v.label == "IOT" and "IoT"
      or (v.label and (v.label:sub(1, 1):upper() .. v.label:sub(2):lower()))
      or "?"
    local name = octet and string.format("VLAN%s(%s)", octet, pretty) or pretty
    local rtt = (v.reachable and v.ms) and string.format("%g ms", v.ms) or "down"
    rows[#rows + 1] = {
      name    = name,
      gateway = v.host or "—",
      rtt     = "(" .. rtt .. ")",
      is_home = (v.host == home_gw),
    }
  end
  return rows
end

function M.net_updated()
  return tostring(os.date("%H:%M:%S"))
end

----------------------------------------------------------------
-- Throughput (fast lane): /sys byte-counter deltas + graph history
----------------------------------------------------------------

local TP = {
  tick = nil, last_t = nil, last_rx = nil, last_tx = nil,
  up = 0, down = 0, up_hist = {}, down_hist = {}, maxlen = 531,
}

local function push_hist(t, v)
  t[#t + 1] = v
  if #t > TP.maxlen then table.remove(t, 1) end
end

local function refresh_throughput()
  local now = os.time()
  if TP.tick == now then return end
  TP.tick = now

  local iface = net_value("IFACE", "eno1")
  local rx = tonumber(read_first_line("/sys/class/net/" .. iface .. "/statistics/rx_bytes"))
  local tx = tonumber(read_first_line("/sys/class/net/" .. iface .. "/statistics/tx_bytes"))

  if rx and tx and TP.last_t and now > TP.last_t and TP.last_rx then
    local dt = now - TP.last_t
    TP.down = math.max(0, (rx - TP.last_rx) / dt / 1024)
    TP.up   = math.max(0, (tx - TP.last_tx) / dt / 1024)
    push_hist(TP.down_hist, TP.down)
    push_hist(TP.up_hist,   TP.up)
  end
  if rx and tx then
    TP.last_t, TP.last_rx, TP.last_tx = now, rx, tx
  end
end

-- { up = KiB/s, down = KiB/s, up_hist = {...}, down_hist = {...} }
-- History is newest-last, one sample per second, capped at graph width.
function M.throughput()
  refresh_throughput()
  return { up = TP.up, down = TP.down, up_hist = TP.up_hist, down_hist = TP.down_hist }
end

return M
