@echo off
REM Show effective unified Claw routing lanes without making model calls.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-route-status.ps1" %*
