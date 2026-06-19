@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM refresh-junction.bat
REM Re-points %USERPROFILE%\.claude-dual-launcher\current at the latest
REM installed Claude_<version>\app under WindowsApps.
REM
REM Pure cmd / mklink - no PowerShell, no VBS, no WScript - so heuristic
REM antivirus tools (Defender, huorong, 360, etc.) don't flag it as a
REM PowerShell-living-off-the-land vector. Verified against 火绒 2026-06-19.

set "BASE=C:\Program Files\WindowsApps"
set "JCT=%USERPROFILE%\.claude-dual-launcher\current"

set "LATEST="
for /f "delims=" %%D in ('dir /b /ad /o-n "%BASE%\Claude_*" 2^>nul') do (
    if exist "%BASE%\%%D\app\Claude.exe" (
        set "LATEST=%BASE%\%%D\app"
        goto :found
    )
)

echo [X] No Claude installation found under %BASE%\Claude_*
exit /b 1

:found
if exist "%JCT%" rmdir "%JCT%" 2>nul

mklink /J "%JCT%" "!LATEST!" >nul
if errorlevel 1 (
    echo [X] mklink failed
    exit /b 1
)

echo [OK] %JCT% -^> !LATEST!
exit /b 0
