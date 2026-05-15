@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-vscode-lm-localhost.ps1" %*
exit /b %ERRORLEVEL%
