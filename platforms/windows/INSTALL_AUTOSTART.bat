@echo off
rem Run a level 1 reset automatically at every logon.
cd /d "%~dp0"
call "%~dp01132.WTF.bat" /autostart-on
pause
