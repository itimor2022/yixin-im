@echo off
setlocal
cd /d "%~dp0"

if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\replace_icons.ps1" -Source "assets\logo.png"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\replace_icons.ps1" -Source "%~1"
)

if errorlevel 1 (
  echo.
  echo Icon replacement failed.
  pause
  exit /b 1
)

echo.
echo Icon replacement finished.
pause
