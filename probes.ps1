# probes.ps1 -- gauge probes for a manifest-driven `probe:<name>` rule.
#
# Each probe returns @{ Color; Status; Pct }. Pct is OPTIONAL -- its presence is what makes
# the renderer draw a bar instead of a plain status line. Color is GREEN / AMBER / RED.
#
# ponytail: one switch, not one script per probe -- a new gauge is a new branch, not a new
# file. Split only if a probe grows past ~15 lines.

function Invoke-PanelProbe {
    param([string]$Name)

    switch ($Name) {

        'ram' {
            $os = Get-CimInstance Win32_OperatingSystem
            $usedPct = 100 - (100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)
            $color = if ($usedPct -gt 88) { 'RED' } elseif ($usedPct -gt 75) { 'AMBER' } else { 'GREEN' }
            @{ Color  = $color
               Status = ('{0:N2} GB free of {1:N1} GB' -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB))
               Pct    = $usedPct }
        }

        'disk' {
            $d = Get-PSDrive C
            $tot = $d.Free + $d.Used
            $freePct = 100 * $d.Free / $tot
            $color = if ($freePct -lt 8) { 'RED' } elseif ($freePct -lt 15) { 'AMBER' } else { 'GREEN' }
            @{ Color  = $color
               Status = ('{0:N0} GB free of {1:N0} GB' -f ($d.Free / 1GB), ($tot / 1GB))
               Pct    = (100 - $freePct) }
        }

        # Colour comes from COMMIT AGE, not dirty count: a handful of dirty files is normal
        # in most repos, so a count threshold would just scream every day.
        'git' {
            # Kit layout is flat -- probes.ps1 sits directly in the repo root it should
            # report on, unlike the workspace source where this file lives one level down
            # in brain-index\ and had to Split-Path -Parent to reach the repo root.
            $root = $PSScriptRoot
            $ts = (& git -C $root log -1 --format=%ct 2>$null)
            if (-not $ts) { return @{ Color = 'AMBER'; Status = 'no git history readable' } }
            $ageH = ((Get-Date) - [DateTimeOffset]::FromUnixTimeSeconds([long]$ts).LocalDateTime).TotalHours
            $dirty = @(& git -C $root status --porcelain 2>$null).Count
            $color = if ($ageH -gt 72) { 'RED' } elseif ($ageH -gt 24) { 'AMBER' } else { 'GREEN' }
            @{ Color = $color; Status = ('{0} dirty, last commit {1:N0}h ago' -f $dirty, $ageH) }
        }

        # 'mybuild' {
        #     # Template for a new probe: read a signal, pick a Color, return a one-line Status.
        #     # Wire it in by adding a branch here -- then reference it from your manifest as
        #     # `probe:mybuild`. No other file needs to change.
        # }

        default { @{ Color = 'AMBER'; Status = "unknown probe: $Name" } }
    }
}

# Self-check: every probe should return a usable colour. Run directly (not dot-sourced).
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    foreach ($p in 'ram', 'disk', 'git', 'nonesuch') {
        $r = Invoke-PanelProbe $p
        if ($r.Color -notin 'GREEN', 'AMBER', 'RED') { throw "probe '$p' returned bad colour: $($r.Color)" }
        '{0,-9} {1,-6} {2,5} {3}' -f $p, $r.Color, $(if ($null -ne $r.Pct) { '{0:N0}%' -f $r.Pct } else { '' }), $r.Status
    }
    'SELFCHECK OK'
}
