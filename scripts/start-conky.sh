#!/usr/bin/env bash
# scripts/start-conky.sh
# Launch all gtex62-clean-suite-e Conky instances (chassis + standalones).
# Prefers the core launcher when available; falls back to direct conky invocations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RUNTIME_ROOT="${GTEX62_CONFIG_DIR:-${GTEX62_CONKY_CONFIG_DIR:-$HOME/.config/gtex62-core}}"
CACHE_ROOT="${GTEX62_CACHE_DIR:-${GTEX62_CONKY_CACHE_DIR:-$HOME/.cache/gtex62-core}}"
CORE_REPO="${GTEX62_CORE_DIR:-${GTEX62_CONKY_ENGINE_DIR:-$HOME/.config/conky/gtex62-core}}"
CORE_LAUNCHER="${GTEX62_CORE_LAUNCHER:-${GTEX62_CONKY_LAUNCHER:-$CORE_REPO/bin/gtex62-core-launch}}"

# Export vars that Conky conf preambles and Lua view models need
export CONKY_SUITE_DIR="$SUITE_DIR"
export GTEX62_SUITE_ID="clean-e"
export GTEX62_CONFIG_DIR="$RUNTIME_ROOT"
export GTEX62_CACHE_DIR="$CACHE_ROOT"
export GTEX62_CONKY_SUITE_ID="clean-e"
export GTEX62_CONKY_CONFIG_DIR="$RUNTIME_ROOT"
export GTEX62_CONKY_CACHE_DIR="$CACHE_ROOT"

# -- Bootstrap runtime if needed ------------------------------------------
if [[ ! -f "$RUNTIME_ROOT/suites/clean-e.toml" ]]; then
  "$SUITE_DIR/scripts/bootstrap-runtime.sh" >/dev/null
fi

# -- Stop any running instances -------------------------------------------
PIDS_DIR="$CACHE_ROOT/runtime/pids"
mkdir -p "$PIDS_DIR"

stop_pid_file() {
  local file="$1"
  local pid=""
  [[ -f "$file" ]] || return 0
  pid="$(cat "$file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
}

wait_pid_exit() {
  local file="$1"
  local pid=""
  [[ -f "$file" ]] || return 0
  pid="$(cat "$file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 0
  local _i
  for _i in {1..30}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
}

for chassis in monitor ambient media notes calendar pfsense; do
  stop_pid_file "$PIDS_DIR/clean-e-${chassis}.pid"
done
pkill -f "clean-(monitor|ambient|media|notes|calendar|pfsense).conky.conf" 2>/dev/null || true
for chassis in monitor ambient media notes calendar pfsense; do
  wait_pid_exit "$PIDS_DIR/clean-e-${chassis}.pid"
done

# -- Enforce suite exclusivity ---------------------------------------------
# Only one main suite may run at a time; SitRep is the sole exception (it's
# allowed to run alongside any main suite), so it's skipped here. Match on
# each other suite's widgets/ path — the same scoped convention this
# script and gtex62-osa already use for their own self-stop — rather than
# a blanket `pkill -x conky`, so SitRep is never touched. Killing a
# suite's conky window is enough to bring the whole suite down: a
# core-launcher-managed suite (osa) blocks on `wait "$CONKY_PID"` and
# exits once it's gone, and its refresh loops self-terminate on their next
# `kill -0 "$CONKY_PID"` check.
CONKY_ROOT="$(dirname "$SUITE_DIR")"
for other_dir in "$CONKY_ROOT"/*/; do
  other_dir="${other_dir%/}"
  [[ "$other_dir" == "$SUITE_DIR" ]] && continue
  [[ "$(basename "$other_dir")" == "gtex62-sitrep" ]] && continue
  [[ -d "$other_dir/widgets" ]] || continue
  pkill -f "$other_dir/widgets/" 2>/dev/null || true
done

# -- Prefer core launcher -------------------------------------------------
if [[ -x "$CORE_LAUNCHER" ]]; then
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$CORE_LAUNCHER" --suite clean-e >/dev/null 2>&1
  else
    nohup "$CORE_LAUNCHER" --suite clean-e >/dev/null 2>&1 &
    disown || true
  fi
  exit 0
fi

# -- Fallback: launch four Conky processes directly -----------------------
echo "Core launcher not found at: $CORE_LAUNCHER"
echo "Launching Conky chassis directly."

launch_chassis() {
  local id="$1"
  local conf="$2"
  local pid_file="$PIDS_DIR/clean-e-${id}.pid"

  nohup conky -c "$conf" >/dev/null 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" > "$pid_file"
  disown "$pid" || true
  echo "  [${id}] pid=${pid}"
}

launch_chassis "monitor"  "$SUITE_DIR/widgets/clean-monitor.conky.conf"
launch_chassis "ambient"  "$SUITE_DIR/widgets/clean-ambient.conky.conf"
launch_chassis "media"    "$SUITE_DIR/widgets/clean-media.conky.conf"
launch_chassis "notes"    "$SUITE_DIR/widgets/clean-notes.conky.conf"
launch_chassis "calendar" "$SUITE_DIR/widgets/clean-calendar.conky.conf"
launch_chassis "pfsense"  "$SUITE_DIR/widgets/clean-pfsense.conky.conf"

echo "All chassis launched."
