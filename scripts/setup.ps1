# setup.ps1 - Create a new Claude Desktop instance with its own user-data-dir
#
# v1.2 architecture (NTFS junction + scheduled task):
#   - All instances share a single NTFS junction at:
#       %USERPROFILE%\.claude-dual-launcher\current  ->  <latest>\Claude_*\app
#   - The desktop shortcut for each instance targets:
#       %USERPROFILE%\.claude-dual-launcher\current\Claude.exe
#     This path is invariant across Claude updates because the junction
#     absorbs the version change.
#   - A user-level Windows Task Scheduler task runs refresh-junction.bat on
#     every user logon, so the junction always points at the freshly-installed
#     Claude.exe even after Claude auto-updates.
#   - No PowerShell or VBS appears in the shortcut, the .bat, or the task
#     command line, so heuristic antivirus (Defender, 火绒, 360, etc.) does
#     not flag any part of this chain.
#
# Usage:
#   .\setup.ps1                              # creates instance "secondary"
#   .\setup.ps1 -InstanceName "work"
#   .\setup.ps1 -InstanceName "work" -SkipLaunch
#   .\setup.ps1 -InstanceName "work" -Force

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InstanceName = "secondary",

    [string]$UserDataRoot = $env:APPDATA,

    [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),

    [switch]$SkipLaunch,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step([string]$msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "[X] $msg" -ForegroundColor Red }

# --- Validate instance name ---------------------------------------------------
if ($InstanceName -notmatch '^[A-Za-z0-9_\-]+$') {
    Write-Err "InstanceName must contain only letters, digits, underscore or hyphen."
    Write-Err "Got: '$InstanceName'"
    exit 1
}

# --- Fixed paths --------------------------------------------------------------
$installDir   = Join-Path $env:USERPROFILE '.claude-dual-launcher'
$junctionPath = Join-Path $installDir 'current'
$refreshBat   = Join-Path $installDir 'refresh-junction.bat'
$junctionExe  = Join-Path $junctionPath 'Claude.exe'
$taskName     = 'ClaudeDualLauncher-JunctionRefresh'

$shortcutName = "Claude ($InstanceName).lnk"
$shortcutPath = Join-Path $DesktopDir $shortcutName
$userDataDir  = Join-Path $UserDataRoot "Claude-$InstanceName"

Write-Host ""
Write-Host "Claude Desktop dual-launcher - setup" -ForegroundColor White
Write-Host "Instance name : $InstanceName"
Write-Host "User-data-dir : $userDataDir"
Write-Host "Shortcut path : $shortcutPath"
Write-Host ""

# --- Locate Claude.exe (initial install check + for icon path) ---------------
Write-Step "Locating Claude.exe under C:\Program Files\WindowsApps\Claude_*\app\"
$claudeAppDir = Get-ChildItem 'C:\Program Files\WindowsApps\' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'app' } |
    Where-Object { Test-Path (Join-Path $_ 'Claude.exe') } |
    Select-Object -First 1

if (-not $claudeAppDir) {
    Write-Err "Claude.exe not found under C:\Program Files\WindowsApps\Claude_*\."
    Write-Err "Install Claude Desktop from the Microsoft Store first, then re-run."
    exit 1
}
$claudeExe = Join-Path $claudeAppDir 'Claude.exe'
Write-OK "Found: $claudeExe"

# --- Check for existing instance ---------------------------------------------
if ((Test-Path $userDataDir) -and -not $Force) {
    Write-Warn "user-data-dir already exists: $userDataDir"
    Write-Warn "Instance '$InstanceName' may already be set up."
    Write-Warn "Pass -Force to refresh the shortcut + global infrastructure anyway (existing data preserved)."
    $answer = Read-Host "Continue? (y/N)"
    if ($answer -ne 'y' -and $answer -ne 'Y') { Write-Host "Aborted."; exit 0 }
}

# --- Ensure install dir + deploy refresh-junction.bat ------------------------
Write-Step "Preparing install directory: $installDir"
if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }

$bundledBat = Join-Path $PSScriptRoot 'refresh-junction.bat'
if (-not (Test-Path $bundledBat)) {
    Write-Err "Bundled refresh-junction.bat not found at: $bundledBat"
    exit 1
}
Copy-Item -Path $bundledBat -Destination $refreshBat -Force
Write-OK "Deployed: $refreshBat"

# --- Create / refresh the NTFS junction --------------------------------------
Write-Step "Creating NTFS junction: $junctionPath -> $claudeAppDir"
if (Test-Path $junctionPath) {
    # rmdir on a junction unlinks it, does NOT recurse into target
    (Get-Item $junctionPath).Delete()
}
New-Item -ItemType Junction -Path $junctionPath -Target $claudeAppDir -ErrorAction Stop | Out-Null
Write-OK "Junction ready"

# --- Register the user-level scheduled task ----------------------------------
# Two triggers so the junction stays fresh in all real-world cases:
#   1. AtLogOn  - catches the common case (Claude updates between sessions)
#   2. Daily 9am - catches mid-session updates (Claude updated while user was
#                  already logged in; would otherwise wait for next reboot)
# Register-ScheduledTask is used instead of schtasks.exe because schtasks
# can only register one trigger per /Create call.
Write-Step "Registering scheduled task: $taskName (logon + daily 9am)"
$savedEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-Null
$ErrorActionPreference = $savedEAP

try {
    $taskAction   = New-ScheduledTaskAction -Execute $refreshBat
    $trigLogon    = New-ScheduledTaskTrigger -AtLogOn
    $trigDaily    = New-ScheduledTaskTrigger -Daily -At '9am'
    $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $taskAction `
        -Trigger @($trigLogon, $trigDaily) `
        -Settings $taskSettings `
        -Description "Re-points the Claude dual-launcher junction at the latest installed Claude. Runs at every logon and once a day at 9 AM." `
        -Force | Out-Null
    Write-OK "Task registered (logon + daily 9am triggers)"
} catch {
    Write-Err "Register-ScheduledTask failed: $($_.Exception.Message)"
    exit 1
}

# Sanity-check: drive the .bat once so the junction is verified before the
# .lnk is created. Catches things like a broken .bat (we hit a chcp-65001
# delayed-expansion bug here on 2026-06-20) or wrong-encoding .bat files
# before the user ever double-clicks anything.
Write-Step "Sanity check: running refresh-junction.bat once"
& cmd.exe /c $refreshBat | Out-Null
$junctionTarget = (Get-Item $junctionPath -ErrorAction SilentlyContinue).Target
if (-not $junctionTarget -or -not (Test-Path $junctionTarget)) {
    Write-Err "Junction did not resolve to a real path after running .bat:"
    Write-Err "  target = $junctionTarget"
    Write-Err "Check $refreshBat for encoding (must be ASCII or UTF-8 no BOM) and"
    Write-Err "that it doesn't have ``chcp 65001`` (breaks cmd delayed expansion)."
    exit 1
}
Write-OK "Junction resolves: $junctionTarget"

# --- Create desktop shortcut --------------------------------------------------
# Shortcut targets Claude.exe through the junction. Because the junction is
# refreshed on every logon, the .lnk Target stays valid across Claude updates.
# Icon is loaded through the same junction path, so the desktop icon also
# survives updates (no white "missing icon" glyph).
Write-Step "Creating desktop shortcut: $shortcutName"
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $junctionExe
$shortcut.Arguments        = "--user-data-dir=`"$userDataDir`""
$shortcut.WorkingDirectory = $junctionPath
$shortcut.IconLocation     = "$junctionExe,0"
$shortcut.Description      = "Launch Claude Desktop (instance: $InstanceName) - junction-based, survives Claude updates"
$shortcut.Save()
Write-OK "Shortcut created"

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
Write-Host "Double-click '$shortcutName' on the desktop to launch the '$InstanceName' instance."
Write-Host "Each Claude update is absorbed by the junction + logon task - you don't"
Write-Host "have to do anything when Claude auto-updates."
Write-Host ""

# --- Optionally launch --------------------------------------------------------
if (-not $SkipLaunch) {
    Write-Step "Launching new instance..."
    Start-Process -FilePath $junctionExe -ArgumentList "--user-data-dir=`"$userDataDir`""
    Write-OK "Launched. A blank Claude window should appear - log in with the second account."
}
