@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gemini-cli-mozmail.ps1" %*
exit /b %ERRORLEVEL%
