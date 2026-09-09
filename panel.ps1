# panel.ps1 -- manifest-driven terminal status board, printed on demand.
#
# ponytail: a terminal print, no window, no timer, no server, no HTML, no dependency.
# PANEL.template.md (or any -Manifest path) is the single source of truth for lanes;
# adding a lane = adding a row there, never editing this script. Gauges live in
# probes.ps1, one branch each.
[CmdletBinding()]
param(
    # Back-compat: the old "print, don't open a window" switch. Printing is now the only mode,
    # so this is a no-op kept so existing callers don't break.
    [switch]$Once,
    # Append each RED lane's manifest "say" keyword -- the thing to type to act on it.
    [switch]$Say,
    # Plain uncoloured single-column output, for piping/diffing.
    [switch]$Raw,
    # Isolate the hook sub-line classifier for verification (no manifest parsing, no render).
    [string]$TestLine,
    # Manifest table to read lanes from. Defaults to PANEL.template.md next to this script.
    # Left unset here (not defaulted via $PSScriptRoot in the param block) --
    # incident_windows_psscriptroot-empty-after-mandatory-param: $PSScriptRoot in a param
    # default can evaluate empty; assign the default in the body instead.
    [string]$Manifest
)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultManifest = Join-Path $here 'PANEL.template.md'
if (-not $Manifest) { $Manifest = $defaultManifest }
$panelPath = $Manifest
if (-not (Test-Path -LiteralPath $panelPath)) {
    Write-Error "Manifest not found: $panelPath"
    exit 1
}
# Change-tracking state is scoped per manifest -- otherwise running a second manifest
# (e.g. PANEL-school.md) would overwrite the live panel's panel-last.json and corrupt its
# next "changed since last look" markers. Default manifest keeps the original filename.
$manifestStem = [IO.Path]::GetFileNameWithoutExtension($panelPath)
$lastPath = if ((Resolve-Path -LiteralPath $panelPath).Path -eq (Resolve-Path -LiteralPath $defaultManifest -ErrorAction SilentlyContinue).Path) {
    Join-Path $here 'panel-last.json'
} else {
    Join-Path $here "panel-last-$manifestStem.json"
}
. (Join-Path $here 'probes.ps1')   # Invoke-PanelProbe, for the `probe:<name>` rule

function Strip-Backtick([string]$s) {
    $s = $s.Trim()
    if ($s.Length -ge 2 -and $s.StartsWith('`') -and $s.EndsWith('`')) { $s.Substring(1, $s.Length - 2) } else { $s }
}

# Parses the manifest's "## Lanes" table into one object per row. Splits on "|" that is NOT
# preceded by "\" so an escaped pipe inside a regex cell (e.g. `count:^\| G-\d+ \|...`)
# does not get mistaken for a cell delimiter.
function Get-Lanes {
    # -Encoding UTF8 is required: PS 5.1's default Get-Content encoding (no BOM present) reads
    # a UTF-8 file as the legacy codepage, mangling any non-ASCII pattern into mojibake that
    # silently never matches.
    $raw = Get-Content -LiteralPath $panelPath -Encoding UTF8
    $rows = @()
    $seenHeader = $false
    $seenSep = $false
    foreach ($line in $raw) {
        $t = $line.Trim()
        if (-not $t.StartsWith('|')) { continue }
        if (-not $seenHeader) { $seenHeader = $true; continue }
        if (-not $seenSep) {
            if (($t -replace '[|\s\-:]', '') -eq '') { $seenSep = $true; continue }
        }
        $cells = [regex]::Split($t, '(?<!\\)\|')
        if ($cells.Count -lt 2) { continue }
        $cells = $cells[1..($cells.Count - 2)] | ForEach-Object { $_.Trim() }
        if ($cells.Count -lt 6) { continue }
        $rows += [pscustomobject]@{
            Lane   = $cells[0]
            Group  = $cells[1]
            Source = Strip-Backtick $cells[2]
            Rule   = Strip-Backtick $cells[3]
            Say    = $cells[4]
            Open   = Strip-Backtick $cells[5]
        }
    }
    $rows
}

function Get-RuleKind([string]$rule) {
    $rule = $rule.Trim()
    if ($rule -eq 'hook')   { return @{ Kind = 'hook' } }
    if ($rule -eq 'exists') { return @{ Kind = 'exists' } }
    if ($rule -eq 'absent') { return @{ Kind = 'absent' } }
    if ($rule -match '^mtime>([\d.]+)d$') { return @{ Kind = 'mtime'; Days = [double]$matches[1] } }
    if ($rule -match '^probe:(.+)$') { return @{ Kind = 'probe'; Name = $matches[1].Trim() } }
    if ($rule -match '^count:(.*)$') {
        $rest = $matches[1]
        $min = $null; $max = $null; $pattern = $rest
        if ($rest -match '^(?<p>.*):(?<min>\d+):(?<max>\d+)$') {
            $pattern = $matches['p']; $min = [int]$matches['min']; $max = [int]$matches['max']
        } elseif ($rest -match '^(?<p>.*):(?<min>\d+)$') {
            $pattern = $matches['p']; $min = [int]$matches['min']
        }
        return @{ Kind = 'count'; Pattern = $pattern; Min = $min; Max = $max }
    }
    return @{ Kind = 'unknown'; Raw = $rule }
}

function Get-MtimeColor([string]$source, [double]$days) {
    $file = if ($source -match '[*?]') {
        Get-ChildItem -Path $source -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    } else {
        Get-Item -LiteralPath $source -ErrorAction SilentlyContinue
    }
    if (-not $file) { return @{ Color = 'RED'; Status = "missing: $source" } }
    $age = ((Get-Date) - $file.LastWriteTime).TotalDays
    $color = if ($age -gt $days) { 'RED' } elseif ($age -gt ($days / 2)) { 'AMBER' } else { 'GREEN' }
    @{ Color = $color; Status = ('{0:N1}d old ({1})' -f $age, $file.Name) }
}

function Get-CountColor([string]$source, [string]$pattern, $min, $max) {
    # Glob-mode: mirror Get-MtimeColor's newest-file resolution (line ~90) so a count: rule
    # over a glob counts matches in the single newest file, not every historical file it globs.
    $target = $source
    if ($source -match '[*?]') {
        $file = Get-ChildItem -Path $source -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $file) { return @{ Color = 'RED'; Status = "missing: $source" } }
        $target = $file.FullName
    } elseif (-not (Test-Path -LiteralPath $source)) {
        return @{ Color = 'RED'; Status = "missing: $source" }
    }
    $count = @(Select-String -LiteralPath $target -Pattern $pattern -ErrorAction SilentlyContinue).Count
    $color =
        if ($null -ne $max -and $count -gt $max) { 'RED' }
        elseif ($null -ne $min -and $count -lt $min) { 'RED' }
        elseif ($null -eq $max -and $count -gt 0) { 'AMBER' }
        else { 'GREEN' }
    # Read as an instrument, not a debug dump: "49 (max 40)" beats "count=49 (min=0 max=40)".
    $bound = if ($null -ne $max) { "max $max" } elseif ($null -ne $min) { "min $min" } else { $null }
    @{ Color = $color; Status = $(if ($bound) { "$count  ($bound)" } else { "$count" }) }
}

# The hook rule's classifier -- also exposed standalone via -TestLine for verification.
function Get-SublineColor([string]$line) {
    if ($line -match '^!!|STALE|WARNING|work-to-rule: on') { 'RED' }
    elseif ($line -match 'WARN') { 'AMBER' }
    else { 'GREEN' }
}

function Get-HookColor([string]$source) {
    if (-not (Test-Path -LiteralPath $source)) { return @{ Color = 'RED'; Status = "missing: $source" } }
    # Never pipe stdin -- the hook never reads it.
    $out = (& powershell -NoProfile -File $source 2>$null | Out-String).Trim()
    if (-not $out) { return @{ Color = 'GREEN'; Status = 'all clear' } }
    try {
        $ctx = ($out | ConvertFrom-Json).hookSpecificOutput.additionalContext
    } catch {
        return @{ Color = 'AMBER'; Status = 'unparseable hook output' }
    }
    if (-not $ctx) { return @{ Color = 'GREEN'; Status = 'all clear' } }
    $worst = 'GREEN'; $firstBad = $null
    foreach ($sub in ($ctx -split "`n")) {
        $c = Get-SublineColor $sub
        if ($c -eq 'RED') {
            $worst = 'RED'
            if (-not $firstBad -or (Get-SublineColor $firstBad) -ne 'RED') { $firstBad = $sub }
        } elseif ($c -eq 'AMBER' -and $worst -ne 'RED') {
            $worst = 'AMBER'
            if (-not $firstBad) { $firstBad = $sub }
        }
    }
    @{ Color = $worst; Status = $(if ($firstBad) { $firstBad.Trim() } else { 'all clear' }) }
}

function Evaluate-Lane($lane) {
    try {
        $r = Get-RuleKind $lane.Rule
        switch ($r.Kind) {
            'mtime'  { Get-MtimeColor $lane.Source $r.Days }
            'count'  { Get-CountColor $lane.Source $r.Pattern $r.Min $r.Max }
            'hook'   { Get-HookColor $lane.Source }
            'probe'  { Invoke-PanelProbe $r.Name }
            'exists' { if (Test-Path -LiteralPath $lane.Source) { @{ Color = 'GREEN'; Status = 'present' } } else { @{ Color = 'RED'; Status = 'missing' } } }
            'absent' { if (Test-Path -LiteralPath $lane.Source) { @{ Color = 'RED'; Status = 'present (should be absent)' } } else { @{ Color = 'GREEN'; Status = 'absent' } } }
            default  { @{ Color = 'AMBER'; Status = "unknown rule: $($lane.Rule)" } }
        }
    } catch {
        @{ Color = 'AMBER'; Status = "eval error: $($_.Exception.Message)" }
    }
}

function Get-AllStatuses {
    $lanes = Get-Lanes
    if (-not $lanes -or @($lanes).Count -eq 0) {
        Write-Error "Manifest has no parseable lane rows (missing '## Lanes' table?): $panelPath"
        exit 1
    }
    $last = $null
    if (Test-Path -LiteralPath $lastPath) {
        try { $last = Get-Content -LiteralPath $lastPath -Raw | ConvertFrom-Json } catch {}
    }
    $newMap = [ordered]@{}
    $results = foreach ($lane in $lanes) {
        $r = Evaluate-Lane $lane
        $prev = if ($last) { $last.($lane.Lane) } else { $null }
        # A gauge's status text drifts every single tick (GB free, commit age), so comparing it
        # would mark every gauge changed forever. For probes only the LIGHT changing is news.
        $isProbe = $lane.Rule -match '^probe:'
        $changed = if (-not $prev) { $true }
                   elseif ($isProbe) { $prev.Color -ne $r.Color }
                   else { ($prev.Color -ne $r.Color) -or ($prev.Status -ne $r.Status) }
        $newMap[$lane.Lane] = @{ Color = $r.Color; Status = $r.Status }
        [pscustomobject]@{ Lane = $lane.Lane; Group = $lane.Group; Color = $r.Color; Status = $r.Status
                           Pct = $r.Pct; Say = $lane.Say; Open = $lane.Open; Changed = $changed }
    }
    ($newMap | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $lastPath -Encoding UTF8
    $results
}

if ($PSBoundParameters.ContainsKey('TestLine')) {
    Get-SublineColor $TestLine
    exit 0
}

# ------------------------------------------------------------------ cockpit renderer
# Grouped by the manifest's `group` column -- already parsed by Get-Lanes, previously discarded.
# A lane whose probe returned a Pct draws a bar; every other lane prints its status inline.

$DOT   = [char]0x25CF   # lane light -- the CONSOLE COLOUR carries the meaning, not the shape
$TRI   = [char]0x25B2   # changed since last tick
$FULL  = [char]0x2588
$EMPTY = [char]0x2591
$RULE  = [char]0x2500

function Get-LaneColor($c) { switch ($c) { 'RED' { 'Red' } 'AMBER' { 'Yellow' } default { 'Green' } } }

function Format-Bar([double]$pct, [int]$width = 10) {
    $filled = [int][math]::Max(0, [math]::Min($width, [math]::Round($pct * $width / 100)))
    ($FULL.ToString() * $filled) + ($EMPTY.ToString() * ($width - $filled))
}

$results = @(Get-AllStatuses)

# Uncoloured single column, for piping and for diffing against a previous run.
if ($Raw) {
    foreach ($r in $results) { '{0} | {1} | {2}' -f $r.Lane, $r.Color, $r.Status }
    exit 0
}

$W = 22   # lane-name column (longest lane name in the reference manifest today is 20 chars)
# One row must stay one line -- a wrapped row destroys the at-a-glance read. Trim the status
# to whatever the console actually leaves after the fixed columns.
$termW = try { [math]::Max(60, [Console]::WindowWidth) } catch { 100 }
function Limit-Status([string]$s, [int]$used) {
    $room = $termW - $used - 2
    if ($room -lt 12 -or $s.Length -le $room) { return $s }
    $s.Substring(0, $room - 1) + [char]0x2026   # ellipsis
}

Write-Host ''
Write-Host '  HOUSEKEEPING PANEL' -ForegroundColor White -NoNewline
Write-Host ("   " + (Get-Date -Format 'ddd dd MMM HH:mm')) -ForegroundColor DarkGray

foreach ($group in ($results | ForEach-Object { $_.Group } | Select-Object -Unique)) {
    $head = '  ' + ($RULE.ToString() * 2) + ' ' + $group.ToUpper() + ' '
    Write-Host ''
    Write-Host ($head + ($RULE.ToString() * [math]::Max(4, 72 - $head.Length))) -ForegroundColor DarkGray

    foreach ($r in ($results | Where-Object { $_.Group -eq $group })) {
        $mark = if ($r.Changed) { $TRI } else { ' ' }
        Write-Host ('  ' + $mark + ' ') -ForegroundColor Cyan -NoNewline
        Write-Host $DOT -ForegroundColor (Get-LaneColor $r.Color) -NoNewline
        Write-Host (' ' + $r.Lane.PadRight($W)) -NoNewline

        $used = 6 + $W
        if ($null -ne $r.Pct) {
            Write-Host (Format-Bar $r.Pct) -ForegroundColor (Get-LaneColor $r.Color) -NoNewline
            Write-Host ('{0,5:N0}%  ' -f $r.Pct) -NoNewline
            $used += 17
        }
        Write-Host (Limit-Status $r.Status $used) -ForegroundColor DarkGray

        if ($Say -and $r.Color -eq 'RED' -and $r.Say) {
            Write-Host (' ' * ($W + 6)) -NoNewline
            Write-Host ('say: ' + $r.Say) -ForegroundColor DarkYellow
        }
    }
}

$red   = @($results | Where-Object { $_.Color -eq 'RED' }).Count
$amber = @($results | Where-Object { $_.Color -eq 'AMBER' }).Count
$green = @($results | Where-Object { $_.Color -eq 'GREEN' }).Count

Write-Host ''
Write-Host '  ' -NoNewline
Write-Host "$red RED" -ForegroundColor Red -NoNewline
Write-Host ' / ' -NoNewline
Write-Host "$amber AMBER" -ForegroundColor Yellow -NoNewline
Write-Host ' / ' -NoNewline
Write-Host "$green GREEN" -ForegroundColor Green -NoNewline
Write-Host ("      $TRI = changed since last look" + $(if (-not $Say) { '   ( -Say for fix keywords )' } else { '' })) -ForegroundColor DarkGray
Write-Host ''
