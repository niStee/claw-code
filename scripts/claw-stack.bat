@echo off
REM Start, stop, or inspect the local Claw proxy stack.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-stack.ps1" %*
