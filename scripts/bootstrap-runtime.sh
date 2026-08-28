#!/usr/bin/env bash
# scripts/bootstrap-runtime.sh
# Ensure the runtime root contains a clean-e.toml and required cache dirs.
# Delegates to the core bootstrap utility when available; otherwise creates
# the minimum structure locally so the suite can launch without the core.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RUNTIME_ROOT="${GTEX62_CONFIG_DIR:-${GTEX62_CONKY_CONFIG_DIR:-$HOME/.config/gtex62-core}}"
CACHE_ROOT="${GTEX62_CACHE_DIR:-${GTEX62_CONKY_CACHE_DIR:-$HOME/.cache/gtex62-core}}"
CORE_REPO="${GTEX62_CORE_DIR:-${GTEX62_CONKY_ENGINE_DIR:-$HOME/.config/conky/gtex62-core}}"
CORE_BOOTSTRAP="${GTEX62_CORE_BOOTSTRAP:-$CORE_REPO/bin/gtex62-core-bootstrap-runtime}"

export CONKY_SUITE_DIR="$SUITE_DIR"

# -- Run core bootstrap when available (normal call, not exec) ------------
if [[ -x "$CORE_BOOTSTRAP" ]]; then
  "$CORE_BOOTSTRAP" --suite-dir "$SUITE_DIR" "$@" || true
else
  echo "Core bootstrap not found at: $CORE_BOOTSTRAP"
fi

# -- Always ensure clean-e runtime dirs and toml exist --------------------
SUITES_CFG_DIR="$RUNTIME_ROOT/suites"
SUITE_TOML="$SUITES_CFG_DIR/clean-e.toml"

mkdir -p "$SUITES_CFG_DIR"
mkdir -p "$CACHE_ROOT/suites/clean-e/pf"
mkdir -p "$CACHE_ROOT/suites/clean-e/net"
mkdir -p "$CACHE_ROOT/suites/clean-e/msc"
mkdir -p "$CACHE_ROOT/runtime/pids"

if [[ ! -f "$SUITE_TOML" ]]; then
  cat > "$SUITE_TOML" <<TOML
suite_id = "clean-e"
name = "gtex62-clean-suite-e"
suite_repo = "${SUITE_DIR}"
suite_manifest = "${SUITE_DIR}/suite.toml"
enabled = true

[profiles]
pfsense = "main_router"
connectivity = "default"
weather = "home"
air = "home"
aviation = "home"
astro = "home"
network = "local"
TOML
  echo "Created: $SUITE_TOML"
else
  echo "Already exists: $SUITE_TOML"
fi

if [[ ! -f "$RUNTIME_ROOT/core.toml" ]]; then
  mkdir -p "$RUNTIME_ROOT"
  cat > "$RUNTIME_ROOT/core.toml" <<TOML
[paths]
cache_root = "${CACHE_ROOT}"
config_root = "${RUNTIME_ROOT}"
TOML
  echo "Created: $RUNTIME_ROOT/core.toml"
fi

echo "Bootstrap complete."
