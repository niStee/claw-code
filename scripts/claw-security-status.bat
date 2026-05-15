@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-security-status.ps1" %*
exit /b %ERRORLEVEL%
