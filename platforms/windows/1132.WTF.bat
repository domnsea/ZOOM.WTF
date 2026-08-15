@echo off
rem =====================================================================
rem  1132.WTF for Windows - dispatcher
rem
rem  No arguments   : opens the app window
rem  /fix           : level 1, reset this PC's Zoom identity and relaunch
rem  /deep          : level 2, rotate a throwaway Windows user (needs admin)
rem  /browser [url] : level 3, join in a fresh private browser session
rem  /status        : print what this PC looks like right now
rem  /restore       : undo the most recent fix
rem  /autostart-on  : run level 1 at every logon
rem  /autostart-off : remove the logon task
rem  /logs          : open the log folder
rem  /visible       : run level 1 in a visible console, for troubleshooting
rem =====================================================================

setlocal EnableExtensions
cd /d "%~dp0"

set "APP_NAME=1132.WTF"
set "ENGINE=%~dp01132WTF_ENGINE.ps1"
set "GUI=%~dp01132WTF_APP.ps1"
set "LOG_DIR=%ProgramData%\1132.WTF\logs"
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

if /I "%~1"=="/fix"           goto :run_fix
if /I "%~1"=="/deep"          goto :run_deep
if /I "%~1"=="/browser"       goto :run_browser
if /I "%~1"=="/status"        goto :run_status
if /I "%~1"=="/restore"       goto :run_restore
if /I "%~1"=="/autostart-on"  goto :run_autostart_on
if /I "%~1"=="/autostart-off" goto :run_autostart_off
if /I "%~1"=="/logs"          goto :run_logs
if /I "%~1"=="/visible"       goto :run_visible
goto :run_gui

:check_engine
if exist "%ENGINE%" exit /b 0
call :show_error "1132WTF_ENGINE.ps1 is missing." "Keep every file in this folder together."
exit /b 1

:show_error
%PS% -Command "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('%~1' + [char]10 + [char]10 + '%~2','%APP_NAME%','OK','Error')" >nul 2>&1
exit /b 1

:run_gui
if not exist "%GUI%" (
  call :show_error "1132WTF_APP.ps1 is missing." "Keep every file in this folder together."
  exit /b 1
)
call :check_engine || exit /b 1
start "" %PS% -WindowStyle Hidden -File "%GUI%"
exit /b 0

:run_fix
call :check_engine || exit /b 1
%PS% -WindowStyle Hidden -File "%ENGINE%" -Action fix
exit /b %errorlevel%

:run_deep
call :check_engine || exit /b 1
%PS% -File "%ENGINE%" -Action deep-fix
exit /b %errorlevel%

:run_browser
call :check_engine || exit /b 1
if "%~2"=="" (
  %PS% -WindowStyle Hidden -File "%ENGINE%" -Action browser
) else (
  %PS% -WindowStyle Hidden -File "%ENGINE%" -Action browser -Url "%~2"
)
exit /b %errorlevel%

:run_status
call :check_engine || exit /b 1
%PS% -File "%ENGINE%" -Action status
echo.
pause
exit /b 0

:run_restore
call :check_engine || exit /b 1
%PS% -File "%ENGINE%" -Action restore
exit /b %errorlevel%

:run_autostart_on
call :check_engine || exit /b 1
%PS% -File "%ENGINE%" -Action autostart-on
exit /b %errorlevel%

:run_autostart_off
call :check_engine || exit /b 1
%PS% -File "%ENGINE%" -Action autostart-off
exit /b %errorlevel%

:run_logs
if exist "%LOG_DIR%" (start "" "%LOG_DIR%") else (echo No logs yet: %LOG_DIR% & pause)
exit /b 0

:run_visible
call :check_engine || exit /b 1
cls
echo ======================================================
echo  1132.WTF - visible run (level 1)
echo  Logs: %LOG_DIR%
echo ======================================================
echo.
%PS% -File "%ENGINE%" -Action fix
echo.
echo Exit code: %errorlevel%
echo.
pause
exit /b 0
