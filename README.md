# gtex62-clean-suite-e

Engine-driven conversion of gtex62-clean-suite. The first legacy suite ported to the
core-native model established by gtex62-osa.

Requires [gtex62-core](../gtex62-core) `>=1.0,<2.0`.

---

## Panel Map

### Chassis: Monitor (`clean-monitor`)

| Panel | Content |
|-------|---------|
| SYS   | CPU model, core load, RAM, GPU, top processes |
| NET   | Primary interface, WAN IP, throughput, VLAN gateway status |

### Chassis: Ambient (`clean-ambient`)

| Panel | Content |
|-------|---------|
| WXR   | Current conditions, 5-day forecast, METAR, TAF, SIGMET/AIRMET advisories |
| ORB   | Horizon arc — sun, moon, and visible planets by azimuth |
| TME   | Local clock, UTC, date, month calendar |

### Chassis: Media (`clean-media`)

| Panel | Content |
|-------|---------|
| MSC   | Now-playing arc, album art, title/album/artist |
| NOTES | Sticky notes from `~/Documents/conky-notes.txt` |
| LYRICS | Current track lyrics |

### Standalone: pfSense (`clean-pfsense`) — optional

VLAN traffic flow arcs for WAN / HOME / IOT / GUEST / INFRA interfaces.
Requires pfSense reachable via SSH. Data from the core `pfsense` provider.

For pfBlockerNG stats, Pi-hole status, AP client counts, and cumulative data
totals, use the `sitrep` core utility (not part of this suite).

---

## Quick Start

```bash
# First run — bootstrap runtime config
./scripts/bootstrap-runtime.sh

# Launch suite
./scripts/start-conky.sh
```

---

## Palette Selection

At launch, `start-conky.sh` prompts for a palette. Available palettes are
defined in `theme/clean-palettes.lua`. To launch with a specific palette
without the prompt:

```bash
GTEX62_PALETTE=dark ./scripts/start-conky.sh
```

---

## Customization

| File | Purpose |
|------|---------|
| `theme/clean-palettes.lua` | Color schemes |
| `theme/clean-theme.lua` | Fonts, stroke widths, frame effects |
| `theme/clean-layout.lua` | Chassis dimensions and monitor targeting |
| `theme/panels.lua` | Per-panel position, size, and sub-box geometry |

---

## What Changed from clean-suite

- Data collection delegated to gtex62-core providers (no local fetch scripts)
- 9 Conky processes consolidated into 3 chassis + 1 standalone
- `apwbe` widget retired — AP status now in core `sitrep` utility
- pfSense widget draws VLAN flow only; status/totals moved to `sitrep`
- Theme split into palette / theme / layout / panels files
- Palette switching at launch (was single fixed color scheme)
- AQI panel added (air domain, not in original suite)
- Astronomy uses core `astro` provider (altitude/azimuth) replacing PyEphem sky_update.py
- Monitor targeting via `xinerama_head` (no hardcoded pixel offsets)
