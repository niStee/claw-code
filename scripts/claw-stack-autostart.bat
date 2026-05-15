@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-stack-autostart.ps1" %*
exit /b %ERRORLEVEL%
