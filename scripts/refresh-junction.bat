@echo off
setlocal enabledelayedexpansion

REM refresh-junction.bat
REM Re-points the junction at the latest installed Claude under WindowsApps.
REM
REM IMPORTANT 1: do NOT add chcp 65001. UTF-8 code page breaks cmd delayed
REM expansion; the !LATEST! token stops expanding, mklink silently creates
REM a junction to the literal string "!LATEST!", every shortcut dies.
REM Found the hard way 2026-06-20.
REM
REM IMPORTANT 2: this file MUST be saved as ASCII or UTF-8 without BOM.
REM UTF-16 or UTF-8-with-BOM breaks cmd parsing (each line gets mangled,
REM REM lines are executed as commands, etc).

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

echo [OK] %JCT% pointed at !LATEST!
exit /b 0
