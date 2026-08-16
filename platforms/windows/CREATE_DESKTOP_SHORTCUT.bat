@echo off
rem Put a branded "1132.WTF" shortcut on the desktop.
setlocal EnableExtensions
cd /d "%~dp0"

set "TARGET=%~dp01132.WTF.vbs"
set "ICON=%~dp0assets\1132.WTF.ico"
set "SHORTCUT=%USERPROFILE%\Desktop\1132.WTF.lnk"

if not exist "%TARGET%" (
  echo Cannot find 1132.WTF.vbs beside this script.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut($env:SHORTCUT); $s.TargetPath = $env:TARGET; $s.WorkingDirectory = Split-Path $env:TARGET; $s.Description = 'Zoom error 1132, fixed.'; if (Test-Path $env:ICON) { $s.IconLocation = $env:ICON }; $s.Save()"

if errorlevel 1 (
  echo Could not create the shortcut.
  pause
  exit /b 1
)

echo Shortcut created: %SHORTCUT%
pause
