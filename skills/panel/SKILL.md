---
name: panel
disable-model-invocation: true
description: Author a new topic-scoped status-board manifest and run it through panel.ps1's `-Manifest` flag. Trigger on "/panel", "make me a panel for X", "build a status board for X", "panel for [topic]", or "I want a cockpit view of X".
---

# /panel — author a topic-scoped status board

## What this is for

`panel.ps1` (this kit's engine) reads a manifest table on demand and prints a cockpit
board. `PANEL.template.md` is one example manifest; a real project usually wants its own
narrower one instead of growing a single giant table. This skill authors a new manifest:
scout the topic's real files on disk, draft lane rows using the six rule kinds, write the
manifest, then actually run it and show the result.

```
powershell -NoProfile -File panel.ps1 -Manifest PANEL-<name>.md -Raw
```

## Step 1 — scout the topic

Find the topic's REAL files or signals before drafting anything — never invent a lane
pointing at something that doesn't exist yet. A lane whose `source` is missing on disk
lights RED by construction, which is correct for "this should exist and doesn't," but
wrong (a fabricated lane) for a guessed filename.

## Step 2 — draft lanes using the six rule kinds

Read `PANEL.template.md`'s "Rule grammar" section for the authoritative definitions
before drafting:

- `mtime>Nd` — a file that should be refreshed periodically.
- `count:<regex>[:min[:max]]` — count matches in a file; glob-mode (`source` containing
  `*`/`?`) scans only the newest matching file.
- `hook` — only if a real PowerShell script already exists emitting the hook's JSON shape.
- `exists` — something that must be produced (a deliverable, a generated file).
- `absent` — a flag whose presence is bad.
- `probe:<name>` — only `ram`, `disk`, `git`, or a probe you've added a branch for in
  `probes.ps1` — don't invent a probe name without writing its branch.

Don't force all six kinds into a topic that doesn't have six real signals — a handful of
real lanes beats a padded set.

## Step 3 — the private-data refusal (hard rule, not a suggestion)

**Never write a row whose `source` or `open` column points at private/sensitive data** (a
credentials file, personal records, anything outside what the project is meant to expose).
If the topic's real signal lives there, tell the user this lane can't be added and stop —
don't substitute a nearby non-sensitive file as a workaround.

## Step 4 — write the manifest

Write `PANEL-<name>.md` next to `panel.ps1`, matching `PANEL.template.md`'s exact table
shape: a `## Lanes` heading, then `| lane | group | source | rule | say | open |`, a
separator row, then one row per lane. Wrap `source`, `rule`, and `open` cells in
backticks (the parser strips them). Include a short header blurb.

## Step 5 — run it and show the result

```
powershell -NoProfile -File panel.ps1 -Manifest PANEL-<name>.md
```
Confirm it exits 0 and every lane renders with a real status, not an "eval error" or
"unknown rule" line — fix any drafting mistakes before calling it done.

## Anti-patterns

- Writing a lane before confirming its `source` exists on disk.
- A row pointing at private/sensitive data (refuse instead, see Step 3).
- Inventing a new `probe:<name>` without writing its branch in `probes.ps1`.
- Padding to hit a specific lane count instead of using the topic's real signals.
