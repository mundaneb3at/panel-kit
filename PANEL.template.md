# PANEL.template.md — starter manifest for panel-kit

Copy this to `PANEL.md` (or point `panel.ps1 -Manifest <path>` at it) and edit
the rows below. `panel.ps1` reads the `## Lanes` table on demand and prints a
cockpit board — lanes grouped by `group`, each with a light (green / amber / red) and a
one-line status. **Adding a lane = adding a row.** A row whose `source` is missing on disk
lights RED by construction.

Every row below is runnable as-is against a fresh clone of this kit (`.\setup.ps1` first) —
it's the working reference for all six rule kinds, not just documentation.

## Rule grammar (the panel evaluates these; keep them this simple)
- `mtime>Nd` — RED when the newest file matching `source` is older than N days (AMBER at N/2).
- `count:<regex>[:min[:max]]` — count regex matches in `source`; RED when count>max or <min; AMBER when count>0 and no max. If `source` contains a wildcard (`*`/`?`), only the single **newest** matching file is scanned — not every file the glob touches.
- `hook` — run `source` as a child PowerShell script, parse its JSON `hookSpecificOutput.additionalContext`, one sub-row per line (`!!`/STALE/WARNING → red, WARN → amber, else green).
- `exists` — GREEN when `source` exists, RED when it does not (use for "a thing that must be produced").
- `absent` — GREEN when `source` does NOT exist (use for flags whose presence is bad).
- `probe:<name>` — a **gauge**: run the named branch in `probes.ps1`, which returns its own colour, status, and an optional percentage. A probe that returns a percentage draws a bar. This kit ships three probes: `ram`, `disk`, `git` (see `probes.ps1` for how to add your own). `source` is unused by a probe rule — point it at the producer for the record.

## Lanes
| lane | group | source | rule | say | open |
|---|---|---|---|---|---|
| probes.ps1 freshness | docs | `.\probes.ps1` | `mtime>90d` | "review probes.ps1 for drift" | `.\probes.ps1` |
| recent log errors | app | `.\example-logs\*.log` | `count:ERROR:0:5` | "open the newest log and check the error" | `.\example-logs\` |
| example hook | app | `.\example-hook.ps1` | `hook` | "replace example-hook.ps1 with a real check" | `.\example-hook.ps1` |
| hosts file | system | `C:\Windows\System32\drivers\etc\hosts` | `exists` | n/a — ships on every Windows install | `C:\Windows\System32\drivers\etc\hosts` |
| stop flag | app | `.\STOP.flag` | `absent` | "delete STOP.flag to resume" | `.` |
| ram | machine | `.\probes.ps1` | `probe:ram` | "free some RAM" | `.\probes.ps1` |

<!-- "recent log errors" is the glob-mode count demo: example-logs\old.log carries 10 ERROR
     lines (would be RED under a scan-every-file reading), example-logs\new.log carries 1
     ERROR line and is the newer file. Because count: over a glob scans only the newest
     match, this lane counts 1 and lights GREEN -- that's the behavior being demonstrated. -->
