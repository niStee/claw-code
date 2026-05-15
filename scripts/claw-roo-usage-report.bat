@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-roo-usage-report.ps1" %*
exit /b %ERRORLEVEL%
