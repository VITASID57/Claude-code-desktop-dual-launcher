# uninstall.ps1 - Remove a Claude Desktop instance created by setup.ps1 (v1.2)
#
# Per-instance removal:
#   - Desktop shortcut "Claude (<name>).lnk"
#   - user-data-dir %APPDATA%\Claude-<name>\  (asks first; -KeepUserData to skip)
#
# If the user-data-dir is locked by running Electron processes, this script
# identifies them by command-line and offers to stop them, then retries.
#
# Optional global teardown:
#   - Pass -RemoveGlobal to also remove the shared infrastructure (NTFS
#     junction, refresh-junction.bat, scheduled task). Only do this when
#     you're sure no other instances are configured.
#
# Usage:
#   .\uninstall.ps1 -InstanceName "secondary"
#   .\uninstall.ps1 -InstanceName "secondary" -KeepUserData
#   .\uninstall.ps1 -InstanceName "secondary" -Force
#   .\uninstall.ps1 -InstanceName "secondary" -Force -RemoveGlobal

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InstanceName,

    [string]$UserDataRoot = $env:APPDATA,

    [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),

    [switch]$KeepUserData,

    [switch]$RemoveGlobal,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step([string]$msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Skip([string]$msg) { Write-Host "[--] $msg" -ForegroundColor DarkGray }
function Write-Warn([string]$msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "[X] $msg" -ForegroundColor Red }

function Get-InstanceProcesses {
    param([string]$UserDataDir)
    Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$UserDataDir*" }
}

function Stop-InstanceProcesses {
    param([array]$Procs)
    $stopped = 0
    foreach ($p in $Procs) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $stopped++ } catch {}
    }
    return $stopped
}

if ($InstanceName -notmatch '^[A-Za-z0-9_\-]+$') {
    Write-Err "InstanceName must contain only letters, digits, underscore or hyphen."
    exit 1
}

# --- Fixed paths --------------------------------------------------------------
$installDir   = Join-Path $env:USERPROFILE '.claude-dual-launcher'
$junctionPath = Join-Path $installDir 'current'
$refreshBat   = Join-Path $installDir 'refresh-junction.bat'
$taskName     = 'ClaudeDualLauncher-JunctionRefresh'

$shortcutPath = Join-Path $DesktopDir "Claude ($InstanceName).lnk"
$userDataDir  = Join-Path $UserDataRoot "Claude-$InstanceName"

Write-Host ""
Write-Host "Uninstalling Claude Desktop instance: $InstanceName" -ForegroundColor White
Write-Host ""

# --- Shortcut ----------------------------------------------------------------
Write-Step "Removing desktop shortcut: $shortcutPath"
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-OK "Removed"
} else {
    Write-Skip "Not present"
}

# --- User data ----------------------------------------------------------------
Write-Step "user-data-dir: $userDataDir"
if (-not (Test-Path $userDataDir)) {
    Write-Skip "Not present"
} elseif ($KeepUserData) {
    Write-Skip "Kept (-KeepUserData passed)"
} else {
    $skipDelete = $false
    if (-not $Force) {
        Write-Host "    Deleting removes the instance's chat history, OAuth login, and all local state." -ForegroundColor Yellow
        $answer = Read-Host "    Delete user-data-dir? (y/N)"
        if ($answer -ne 'y' -and $answer -ne 'Y') {
            Write-Skip "Kept by user choice"
            $skipDelete = $true
        }
    }
    if (-not $skipDelete) {
        $removed = $false
        try {
            Remove-Item $userDataDir -Recurse -Force -ErrorAction Stop
            $removed = $true
        } catch {
            Write-Warn "First delete attempt failed (file probably locked by a running process)."
        }
        if (-not $removed) {
            $procs = @(Get-InstanceProcesses -UserDataDir $userDataDir)
            if ($procs.Count -eq 0) {
                Write-Err "Could not delete and no Claude process appears bound to this dir."
            } else {
                Write-Warn "Instance '$InstanceName' still has $($procs.Count) Claude process(es) running."
                $proceed = $Force
                if (-not $Force) {
                    $a = Read-Host "    Force-close them and finish uninstall? (y/N)"
                    $proceed = ($a -eq 'y' -or $a -eq 'Y')
                }
                if ($proceed) {
                    $stopped = Stop-InstanceProcesses -Procs $procs
                    Write-OK "Stopped $stopped process(es). Retrying delete..."
                    Start-Sleep -Seconds 2
                    try {
                        Remove-Item $userDataDir -Recurse -Force -ErrorAction Stop
                        $removed = $true
                    } catch {
                        Write-Err "Still failed: $($_.Exception.Message)"
                    }
                } else {
                    Write-Skip "Kept user-data-dir; processes left running."
                }
            }
        }
        if ($removed) { Write-OK "Removed" }
    }
}

# --- Global teardown (only if -RemoveGlobal) ---------------------------------
if ($RemoveGlobal) {
    Write-Host ""
    Write-Host "Tearing down shared infrastructure (-RemoveGlobal passed)" -ForegroundColor Yellow

    Write-Step "Unregistering scheduled task: $taskName"
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-Null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $savedEAP
    if ($rc -eq 0) { Write-OK "Task removed" } else { Write-Skip "Task not present" }

    Write-Step "Removing junction: $junctionPath"
    if (Test-Path $junctionPath) {
        try { (Get-Item $junctionPath).Delete(); Write-OK "Removed" }
        catch { Write-Err $_.Exception.Message }
    } else {
        Write-Skip "Not present"
    }

    Write-Step "Removing helper: $refreshBat"
    if (Test-Path $refreshBat) {
        Remove-Item $refreshBat -Force; Write-OK "Removed"
    } else {
        Write-Skip "Not present"
    }

    # Remove install dir if it's empty
    if ((Test-Path $installDir) -and -not (Get-ChildItem $installDir -Force)) {
        Remove-Item $installDir -Force
        Write-OK "Removed empty install dir: $installDir"
    }
} else {
    Write-Host ""
    Write-Host "Shared infrastructure (junction + task + .bat) left in place." -ForegroundColor DarkGray
    Write-Host "Pass -RemoveGlobal on the LAST instance's uninstall if you want a clean wipe." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
