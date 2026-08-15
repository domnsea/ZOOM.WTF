@echo off
rem Level 3: open a fresh private browser session to join without the client.
setlocal EnableExtensions
cd /d "%~dp0"
set /p MEETING="Meeting link (press Enter for zoom.us/join): "
if "%MEETING%"=="" (
  call "%~dp01132.WTF.bat" /browser
) else (
  call "%~dp01132.WTF.bat" /browser "%MEETING%"
)
