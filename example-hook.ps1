# example-hook.ps1 -- demo script for the `hook` rule kind in PANEL.template.md.
#
# A `hook` lane runs its `source` as a child PowerShell script and parses one JSON line of
# the shape below. `hookSpecificOutput.additionalContext` holds one status line per lane
# sub-row (split on newline); each sub-line is coloured by keyword: `!!`/STALE/WARNING -> red,
# WARN -> amber, else green. Replace this with a script that checks something real.
@{
    hookSpecificOutput = @{
        additionalContext = "WARN: this is a placeholder finding -- replace example-hook.ps1 with a real check"
    }
} | ConvertTo-Json -Depth 3 -Compress
