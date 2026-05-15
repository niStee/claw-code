@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-route-last.ps1" %*
exit /b %ERRORLEVEL%
