# uninstall.ps1 — Remove a Claude Desktop instance created by setup.ps1
#
# Usage:
#   .\uninstall.ps1 -InstanceName "secondary"
#   .\uninstall.ps1 -InstanceName "secondary" -KeepUserData   # keep chat history etc.
#
# Removes:
#   - Desktop shortcut "Claude (<name>).lnk"
#   - Launcher script %USERPROFILE%\.claude-dual-launcher\launch-<name>.ps1
#   - user-data-dir %APPDATA%\Claude-<name>\  (asks first; pass -KeepUserData to skip)

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
        Remove-Item $userDataDir -Recurse -Force
        Write-OK "Removed"
    }
}

Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
