# panel-kit

A tiny, dependency-free terminal status board for **Windows + PowerShell**. You describe
what to check in a plain markdown table (a "manifest") — a file's age, a regex count, a
live gauge like free RAM — and `panel.ps1` prints a coloured cockpit view on demand. No
window, no server, no timer, no background process: it runs when you run it and prints
once.

```
  HOUSEKEEPING PANEL   Tue 08 Sep 16:58

  ── APP ─────────────────────────────────────────────────────
   ● probes.ps1 freshness      0.0d old (probes.ps1)
   ● recent log errors         1  (max 5)
   ● example hook               WARN: this is a placeholder finding
  ── SYSTEM ──────────────────────────────────────────────────
   ● hosts file                present
   ● stop flag                 absent
  ── MACHINE ─────────────────────────────────────────────────
   ● ram                ████████░░  82%  2.8 GB free of 15.4 GB

  0 RED / 1 AMBER / 5 GREEN      ▲ = changed since last look
```

## Install

Requires **Windows + PowerShell** (ships with Windows 10/11 — PowerShell 5.1 or newer, no
install needed). Git Bash / WSL work too once installed, via the extensionless shim below.

1. Clone or download this folder anywhere.
2. From inside it, run:
   ```
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```
   (`-ExecutionPolicy Bypass` only affects this one command — it tells PowerShell to run
   this specific script even if your system normally blocks unsigned `.ps1` files. It
   doesn't change any setting permanently.) This places a `panel` command in
   `%USERPROFILE%\bin\` and adds that folder to your user PATH (only if it isn't already
   there — safe to re-run, never overwrites a file it didn't create).
3. Open a **new** PowerShell, Command Prompt (`cmd.exe`), or Git Bash window (PATH changes
   don't apply to windows already open), then run:
   ```
   panel -Raw
   ```
   All three shells work — `setup.ps1` installs a `.cmd` shim for PowerShell/Command
   Prompt and a separate extensionless shim for Git Bash. You should see the 6 example
   lanes from `PANEL.template.md` (shown above).

If you'd rather not touch your PATH, run it directly instead: `powershell -File
panel.ps1 -Raw` from inside the kit folder, any time.

## Write your own manifest

Copy `PANEL.template.md` to `PANEL.md` (or any name) and edit the `## Lanes` table. One
row = one lane:

```
| lane | group | source | rule | say | open |
|---|---|---|---|---|---|
| my log's errors | app | `.\logs\*.log` | `count:ERROR:0:5` | "check the newest log" | `.\logs\` |
```

Then run it: `panel -Manifest .\my-manifest.md -Raw` (or without `-Raw` for the coloured
view). `panel.ps1`'s default manifest (no `-Manifest` flag) is `PANEL.template.md` next to
it — most people just edit that file in place instead.

### The six rule kinds

| Rule | Fires GREEN when... | Example |
|---|---|---|
| `mtime>Nd` | the newest file matching `source` is younger than N days (AMBER past N/2) | `mtime>7d` |
| `count:<regex>[:min[:max]]` | the regex's match count in `source` is within `[min,max]` | `count:ERROR:0:5` |
| `hook` | `source` (a PowerShell script) prints no `additionalContext`, or only clean lines | — |
| `exists` | `source` exists on disk | — |
| `absent` | `source` does **not** exist (for a "stop" flag file) | — |
| `probe:<name>` | the named branch in `probes.ps1` returns GREEN | `probe:ram` |

If `source` in a `count:` rule contains a wildcard (`*` or `?`), only the single **newest**
matching file is scanned — not every file the glob touches. Same behavior for `mtime>Nd`.

### Adding a probe

A `probe:<name>` rule is a **gauge** — it can return a percentage (drawn as a bar) as well
as a colour and status line, for a live measurement like RAM or disk that isn't really
"about a file." Open `probes.ps1`, add a new `case` in the `switch` block (there's a
commented example already), then reference it from your manifest as `probe:yourname`. No
other file needs to change.

## Files in this kit

| File | What it is |
|---|---|
| `panel.ps1` | the engine — parses a manifest, evaluates each lane, prints the board |
| `probes.ps1` | the `ram` / `disk` / `git` gauges, plus a stub showing how to add your own |
| `PANEL.template.md` | a working example manifest exercising all six rule kinds |
| `setup.ps1` | idempotent installer — places the `panel` command on your PATH |
| `skills/panel/SKILL.md` | a Claude Code skill that scouts a topic and drafts a manifest for you (optional — only relevant if you use Claude Code) |

## FAQ / troubleshooting

**`panel` isn't found after running setup.ps1.** Open a genuinely new terminal window —
PATH changes only apply to windows opened after the change.

**I use Git Bash, not PowerShell.** `setup.ps1` places both `panel.cmd` (for `cmd.exe` /
PowerShell) and an extensionless `panel` (for Bash) into `%USERPROFILE%\bin\` — Bash's
command search doesn't fall back through `PATHEXT` the way `cmd.exe` does, so a bare
`panel.cmd` alone would be invisible to it. Both point at the same `panel.ps1`.

**A lane is stuck on "eval error: ...".** Your manifest row's `rule` cell doesn't match
one of the six shapes above exactly — check for a typo (e.g. `mtime>7 d` with a stray
space, or a missing colon in `count:`).

**setup.ps1 warns instead of installing.** You already have a `panel.cmd` or `panel` in
`%USERPROFILE%\bin\` that isn't this kit's — it refuses to overwrite a file it didn't
create. Remove or rename the existing file first if you want this kit to manage it.

## License

CC0 — see `LICENSE`. Do whatever you want with it.
