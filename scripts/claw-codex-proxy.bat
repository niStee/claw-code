@echo off
REM ============================================================
REM  Codex Proxy Starter - ChatGPT subscription via codex-proxy
REM
REM  Starts the codex-proxy server on localhost:8089 that
REM  translates OpenAI-compatible /v1/chat/completions requests
REM  to Codex Desktop API using a ChatGPT OAuth session.
REM
REM  Usage:
REM    claw-codex-proxy.bat             Start on port 8089
REM    claw-codex-proxy.bat 9090        Start on port 9090
REM    claw-codex-proxy.bat status      Show default port status
REM    claw-codex-proxy.bat status 9090 Show custom port status
REM    claw-codex-proxy.bat stop        Stop default port
REM    claw-codex-proxy.bat stop 9090   Stop custom port
REM ============================================================

setlocal enabledelayedexpansion

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8089"
if /I "%PORT%"=="stop" (
    set "PORT=%~2"
    if "!PORT!"=="" set "PORT=8089"
    goto :stop
)
if /I "%PORT%"=="status" (
    set "PORT=%~2"
    if "!PORT!"=="" set "PORT=8089"
    goto :status
)

REM Resolve codex-proxy directory (always next to this script)
set "CODEX_PROXY_DIR=%~dp0codex-proxy"

set "NODE_CMD=node"
where node >nul 2>nul
if errorlevel 1 (
    if exist "%LOCALAPPDATA%\OpenAI\Codex\bin\node.exe" (
        set "NODE_CMD=%LOCALAPPDATA%\OpenAI\Codex\bin\node.exe"
    ) else (
        echo [ERROR] node.exe was not found.
        echo   Install Node.js or ensure Codex bundled node.exe is available.
        exit /b 1
    )
)

set "NPM_CMD=npm"
where npm >nul 2>nul
if errorlevel 1 set "NPM_CMD="

set "TSX_CLI=%CODEX_PROXY_DIR%\node_modules\tsx\dist\cli.mjs"
set "RUNNER=%~dp0codex-proxy-runner.mjs"

if not exist "%CODEX_PROXY_DIR%\package.json" (
    echo [ERROR] codex-proxy not found at %CODEX_PROXY_DIR%
    echo   Clone it: git clone https://github.com/icebear0828/codex-proxy.git
    exit /b 1
)

REM Check node_modules exist
if not exist "%CODEX_PROXY_DIR%\node_modules" (
    if not defined NPM_CMD (
        echo [ERROR] node_modules is missing and npm was not found.
        echo   Install Node.js/npm or run npm install inside %CODEX_PROXY_DIR% once.
        exit /b 1
    )
    echo [codex-proxy] Installing dependencies...
    cd /d "%CODEX_PROXY_DIR%"
    call "%NPM_CMD%" install
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] npm install failed
        exit /b 1
    )
)

echo [codex-proxy] Starting Codex Proxy...
echo [codex-proxy]   Port:     !PORT!
echo [codex-proxy]   Host:     127.0.0.1 ^(forced by claw wrapper^)
echo [codex-proxy]   Auth:     Browser OAuth (open http://127.0.0.1:!PORT! to login)
echo [codex-proxy]   API Key:  pwd ^(default, or check http://127.0.0.1:!PORT! dashboard^)
echo [codex-proxy]   Models:   gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-5.3-codex
echo [codex-proxy]   Env:      OPENAI_BASE_URL=http://127.0.0.1:!PORT!/v1
echo [codex-proxy]             OPENAI_API_KEY=pwd ^(or dashboard key^)
echo.

REM Set PORT env var for codex-proxy to override config/default.yaml.
REM Use the local runner so the upstream default host "::" cannot expose the
REM proxy outside localhost when this standalone script is used.
set "PORT=!PORT!"

cd /d "%CODEX_PROXY_DIR%"
"%NODE_CMD%" "%TSX_CLI%" "%RUNNER%"

goto :end

:status
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT%.*LISTENING" 2^>nul') do (
    echo [codex-proxy] Proxy is listening on port %PORT% ^(PID %%a^).
    goto :end
)
echo [codex-proxy] No proxy is listening on port %PORT%.
goto :end

:stop
echo [codex-proxy] Stopping proxy...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT%.*LISTENING" 2^>nul') do (
    taskkill /PID %%a /F 2>nul
)
echo [codex-proxy] Proxy stopped.
goto :end

:end
endlocal
