@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-gcloud-mozmail.ps1" %*
exit /b %ERRORLEVEL%
