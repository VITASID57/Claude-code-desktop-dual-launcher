# setup.ps1 - Create a new Claude Desktop instance with its own user-data-dir
#
# Usage:
#   .\setup.ps1                              # creates instance "secondary"
#   .\setup.ps1 -InstanceName "work"         # custom name
#   .\setup.ps1 -InstanceName "work" -SkipLaunch
#
# What it does:
#   1. Locates Claude.exe in C:\Program Files\WindowsApps\Claude_*\
#   2. Creates a separate user-data-dir under %APPDATA%\Claude-<name>
#   3. Deploys a self-healing launcher script to %USERPROFILE%\.claude-dual-launcher\
#   4. Creates a desktop shortcut "Claude (<name>).lnk"
#   5. Launches the new instance (skip with -SkipLaunch)

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$InstanceName = "secondary",

    [string]$InstallDir = (Join-Path $env:USERPROFILE ".claude-dual-launcher"),

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

$shortcutName = "Claude ($InstanceName).lnk"
$shortcutPath = Join-Path $DesktopDir $shortcutName
$userDataDir  = Join-Path $UserDataRoot "Claude-$InstanceName"
$launcherPath = Join-Path $InstallDir "launch-$InstanceName.ps1"

Write-Host ""
Write-Host "Claude Desktop dual-launcher - setup" -ForegroundColor White
Write-Host "Instance name : $InstanceName"
Write-Host "User-data-dir : $userDataDir"
Write-Host "Launcher path : $launcherPath"
Write-Host "Shortcut path : $shortcutPath"
Write-Host ""

# --- Locate Claude.exe --------------------------------------------------------
Write-Step "Locating Claude.exe under C:\Program Files\WindowsApps\Claude_*\app\"
$claudeExe = Get-ChildItem 'C:\Program Files\WindowsApps\' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'app\Claude.exe' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $claudeExe) {
    Write-Err "Claude.exe not found under C:\Program Files\WindowsApps\Claude_*\."
    Write-Err "Install Claude Desktop from the Microsoft Store first, then re-run."
    exit 1
}
Write-OK "Found: $claudeExe"

# --- Check for existing instance ----------------------------------------------
if ((Test-Path $userDataDir) -and -not $Force) {
    Write-Warn "user-data-dir already exists: $userDataDir"
    Write-Warn "An instance named '$InstanceName' may already be set up."
    Write-Warn "Pass -Force to overwrite the shortcut + launcher anyway (existing data is preserved)."
    $answer = Read-Host "Continue? (y/N)"
    if ($answer -ne 'y' -and $answer -ne 'Y') {
        Write-Host "Aborted."
        exit 0
    }
}

# --- Create install dir + deploy launcher ------------------------------------
Write-Step "Preparing install directory: $InstallDir"
if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }

$launcherTemplatePath = Join-Path $PSScriptRoot 'launch.ps1'
if (-not (Test-Path $launcherTemplatePath)) {
    Write-Err "Launcher template not found next to setup.ps1: $launcherTemplatePath"
    exit 1
}

Write-Step "Deploying launcher: $launcherPath"
$launcherContent = Get-Content $launcherTemplatePath -Raw
$launcherContent = $launcherContent -replace '__USER_DATA_DIR__', [Regex]::Escape($userDataDir).Replace('\\', '\')
$launcherContent = $launcherContent -replace '__INSTANCE_NAME__', $InstanceName
Set-Content -Path $launcherPath -Value $launcherContent -Encoding UTF8
Write-OK "Launcher written"

# --- Create desktop shortcut --------------------------------------------------
Write-Step "Creating desktop shortcut: $shortcutName"
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $claudeExe
$shortcut.Arguments        = "--user-data-dir=`"$userDataDir`""
$shortcut.WorkingDirectory = Split-Path $claudeExe -Parent
$shortcut.IconLocation     = "$claudeExe,0"
$shortcut.Description      = "Launch Claude Desktop with a separate user-data-dir ($InstanceName)"
$shortcut.Save()
Write-OK "Shortcut created"

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "==== Done ====" -ForegroundColor Green
Write-Host "Double-click the desktop shortcut to launch the '$InstanceName' instance."
Write-Host "If Claude updates and the shortcut breaks, run the self-healing launcher:"
Write-Host "  $launcherPath" -ForegroundColor Yellow
Write-Host ""

# --- Optionally launch --------------------------------------------------------
if (-not $SkipLaunch) {
    Write-Step "Launching new instance..."
    Start-Process -FilePath $claudeExe -ArgumentList "--user-data-dir=`"$userDataDir`""
    Write-OK "Launched. A blank Claude window should appear - log in with the second account."
}
