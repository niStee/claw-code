@echo off
REM Probe the unified proxy and show the backend selected right now.
REM Usage: claw-route-probe.bat [opus|sonnet|haiku|pro|MODEL] [port]
if "%~2"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-route-probe.ps1" -Model "%~1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-route-probe.ps1" -Model "%~1" -Port %~2
)
