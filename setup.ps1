# setup.ps1 -- installs the `panel` command for the current user.
# SAFE + IDEMPOTENT: only creates what's missing, never deletes or overwrites a file it
# didn't create itself. Run it as many times as you like.
#
# Usage (from this kit's folder, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# Result:
#   %USERPROFILE%\bin\panel.cmd  -- cmd.exe / PowerShell shim, calls this kit's panel.ps1
#   %USERPROFILE%\bin\panel      -- Git-Bash-resolvable shim (no extension), same target
#   %USERPROFILE%\bin added to the user PATH, only if it wasn't already there
#
# ponytail: two tiny shim files + one PATH check -- no installer framework, no MSI, no
# per-machine (only per-user) PATH change.
#
# -DryRun: print what would happen, touch no real state (registry PATH included). Required
# for automated testing -- [Environment]::SetEnvironmentVariable(...,'User') writes to the
# REAL logged-in user's registry regardless of $env:USERPROFILE, so a test harness that
# overrides $env:USERPROFILE to a fake sandbox directory and then runs this script for real
# would still corrupt the real user's PATH with a bogus temp-folder entry. -DryRun is the
# only safe way to exercise this script's PATH logic outside of a real, intended install.
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'

$kitRoot = $PSScriptRoot
$panelPs1 = Join-Path $kitRoot 'panel.ps1'
if (-not (Test-Path -LiteralPath $panelPs1)) {
    Write-Error "panel.ps1 not found next to setup.ps1 ($panelPs1) -- run this script from inside the kit folder."
    exit 1
}

$binDir = Join-Path $env:USERPROFILE 'bin'
if (-not (Test-Path -LiteralPath $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Write-Host "  created  $binDir" -ForegroundColor Green
} else {
    Write-Host "  exists   $binDir" -ForegroundColor DarkGray
}

# Writes $content to $path UNLESS a different file is already there -- never clobbers a
# stranger's own script of the same name. A file we wrote ourselves (byte-identical content)
# is a silent no-op on re-run, which is what makes this idempotent.
function Install-Shim([string]$path, [string]$content) {
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path -Raw
        if ($existing -eq $content) {
            Write-Host "  exists   $path  (up to date)" -ForegroundColor DarkGray
            return
        }
        Write-Warning "  $path already exists and its content does not match this kit's shim -- NOT overwriting. Remove it manually first if you want setup.ps1 to manage it."
        return
    }
    Set-Content -LiteralPath $path -Value $content -NoNewline
    Write-Host "  placed   $path" -ForegroundColor Green
}

$cmdContent = "@echo off`r`nREM panel-kit shim -- calls panel.ps1 next to this kit's own setup.ps1.`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$panelPs1`" %*`r`n"
Install-Shim (Join-Path $binDir 'panel.cmd') $cmdContent

$bashPath = ($panelPs1 -replace '\\', '/') -replace '^([A-Za-z]):', '/$1'
$bashContent = "#!/bin/bash`n# panel-kit shim -- Git-Bash-resolvable sibling of panel.cmd (bash's exec search does not`n# fall back through PATHEXT the way cmd.exe does, so a bare panel.cmd is invisible to it).`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$panelPs1`" `"`$@`"`n"
Install-Shim (Join-Path $binDir 'panel') $bashContent

# --- PATH: add %USERPROFILE%\bin for this user only, only if it's not already there --------
# NOTE: this reads/writes the REAL logged-in user's registry PATH, not a path scoped to
# $env:USERPROFILE -- there is no per-USERPROFILE PATH in Windows. -DryRun skips the write.
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$already = @($userPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -eq $binDir.TrimEnd('\') })
if ($already.Count -gt 0) {
    Write-Host "  exists   $binDir already on user PATH" -ForegroundColor DarkGray
} elseif ($DryRun) {
    Write-Host "  [dry-run] would add $binDir to user PATH" -ForegroundColor Yellow
} else {
    $newPath = if ($userPath) { "$userPath;$binDir" } else { $binDir }
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Host "  added    $binDir to user PATH (open a new shell for it to take effect)" -ForegroundColor Green
}

# --- restore the example manifest's intended file ages ------------------------------------
# `git clone` sets every checked-out file's mtime to checkout time, which destroys the
# ordering the "recent log errors" glob-mode demo in PANEL.template.md depends on (it should
# read only example-logs\new.log, the newest file). Without this, a fresh clone can pick
# either file as "newest" and the demo silently shows the wrong lane color. Idempotent and
# skipped entirely if this isn't a copy of the kit with its example files (a user's own
# project won't have them, and that's fine -- nothing to restore).
$exLogs = Join-Path $kitRoot 'example-logs'
$oldLog = Join-Path $exLogs 'old.log'
$newLog = Join-Path $exLogs 'new.log'
if ((Test-Path -LiteralPath $oldLog) -and (Test-Path -LiteralPath $newLog)) {
    (Get-Item -LiteralPath $oldLog).LastWriteTime = (Get-Date).AddDays(-3)
    (Get-Item -LiteralPath $newLog).LastWriteTime = (Get-Date).AddHours(-1)
    Write-Host "  fixed    example-logs\ file ages (so the glob-mode demo lane reads correctly)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Done. Open a NEW PowerShell or Git Bash window, then run: panel -Raw" -ForegroundColor Cyan
Write-Host "(the current window's PATH is stale until you open a new one)" -ForegroundColor DarkGray
