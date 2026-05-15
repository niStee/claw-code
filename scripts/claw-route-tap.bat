@echo off
setlocal
set "PORT=%~1"
if "%PORT%"=="" set "PORT=8099"
set "TARGET=%~2"
if "%TARGET%"=="" set "TARGET=http://127.0.0.1:8098"
node "%~dp0claw-route-tap.mjs" "%PORT%" "%TARGET%"
exit /b %ERRORLEVEL%
