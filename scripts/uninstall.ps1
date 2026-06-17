# uninstall.ps1 - Remove a Claude Desktop instance created by setup.ps1
#
# Usage:
#   .\uninstall.ps1 -InstanceName "secondary"
#   .\uninstall.ps1 -InstanceName "secondary" -KeepUserData   # keep chat history etc.
#   .\uninstall.ps1 -InstanceName "secondary" -Force          # no prompts, kill processes if needed
#
# Removes:
#   - Desktop shortcut "Claude (<name>).lnk"
#   - Launcher script %USERPROFILE%\.claude-dual-launcher\launch-<name>.ps1
#   - user-data-dir %APPDATA%\Claude-<name>\  (asks first; pass -KeepUserData to skip)
#
# If the instance is still running, deleting user-data-dir will fail because
# Electron child processes hold file locks (Cache/, IndexedDB/, etc.). When
# this happens, this script identifies the locking processes by matching
# their command line against the user-data-dir, prompts to force-close them,
# and retries the delete.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InstanceName,

    [string]$InstallDir = (Join-Path $env:USERPROFILE ".claude-dual-launcher"),

    [string]$UserDataRoot = $env:APPDATA,

    [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),

    [switch]$KeepUserData,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step([string]$msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Skip([string]$msg) { Write-Host "[--] $msg" -ForegroundColor DarkGray }
function Write-Warn([string]$msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "[X] $msg" -ForegroundColor Red }

# Find Claude.exe processes whose command-line includes the given user-data-dir
# path (i.e. processes belonging to this specific instance).
function Get-InstanceProcesses {
    param([string]$UserDataDir)
    Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$UserDataDir*" }
}

# Stop all processes belonging to this instance. Returns count actually stopped.
function Stop-InstanceProcesses {
    param([array]$Procs)
    $stopped = 0
    foreach ($p in $Procs) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            $stopped++
        } catch {
            # Already gone (parent kill cascaded) — fine
        }
    }
    return $stopped
}

if ($InstanceName -notmatch '^[A-Za-z0-9_\-]+$') {
    Write-Host "[X] InstanceName must contain only letters, digits, underscore or hyphen." -ForegroundColor Red
    exit 1
}

$shortcutPath = Join-Path $DesktopDir "Claude ($InstanceName).lnk"
$launcherPath = Join-Path $InstallDir "launch-$InstanceName.ps1"
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

# --- Launcher ----------------------------------------------------------------
Write-Step "Removing launcher script: $launcherPath"
if (Test-Path $launcherPath) {
    Remove-Item $launcherPath -Force
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
    if (-not $Force) {
        Write-Host "    Deleting this removes the instance's chat history, OAuth login, and all local state." -ForegroundColor Yellow
        $answer = Read-Host "    Delete user-data-dir? (y/N)"
        if ($answer -ne 'y' -and $answer -ne 'Y') {
            Write-Skip "Kept by user choice"
            $skipDelete = $true
        }
    }
    if (-not $skipDelete) {
        # First attempt — clean delete (works if no Claude process is bound to this dir)
        $removed = $false
        try {
            Remove-Item $userDataDir -Recurse -Force -ErrorAction Stop
            $removed = $true
        } catch {
            # Likely a file lock from a running Electron child process
            Write-Warn "First delete attempt failed (file probably locked by a running process)."
        }

        # If still present, look for instance processes and offer to stop them
        if (-not $removed) {
            $procs = @(Get-InstanceProcesses -UserDataDir $userDataDir)
            if ($procs.Count -eq 0) {
                Write-Err "Could not delete and no Claude process appears bound to this dir."
                Write-Err "Manual cleanup: close all Claude windows, then re-run uninstall."
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
                        Write-Err "Still failed after stopping processes: $($_.Exception.Message)"
                        Write-Err "You may need to log out / reboot to release the lock."
                    }
                } else {
                    Write-Skip "Kept user-data-dir; processes left running."
                }
            }
        }

        if ($removed) { Write-OK "Removed" }
    }
}

Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
