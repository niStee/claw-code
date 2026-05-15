@echo off
REM ╔══════════════════════════════════════════════════════════════╗
REM ║  LiteLLM Vertex AI Claude Proxy Starter                     ║
REM ║                                                            ║
REM ║  Starts a LiteLLM proxy on localhost:8087 that translates   ║
REM ║  OpenAI-compatible /v1/chat/completions requests to Vertex  ║
REM ║  AI Anthropic Claude format.                                ║
REM ║                                                            ║
REM ║  Auth: Uses gcloud ADC (gcloud auth application-default     ║
REM ║        login). Token refresh handled automatically.         ║
REM ║                                                            ║
REM ║  Usage:                                                    ║
REM ║    claw-vertex-proxy.bat            Start on default port   ║
REM ║    claw-vertex-proxy.bat 9090       Start on port 9090      ║
REM ║    claw-vertex-proxy.bat stop        Stop running proxy      ║
REM ╚══════════════════════════════════════════════════════════════╝

setlocal enabledelayedexpansion

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8087"
if /I "%PORT%"=="stop" goto :stop

REM Resolve project ID: VERTEX_PROJECT_ID env > DPAPI storage.
REM Do not read global gcloud config here; Google Cloud state should be isolated
REM through scripts\claw-gcloud-mozmail.ps1 / profiles\gcloud-mozmail.
if defined VERTEX_PROJECT_ID (
    set "PROJECT_ID=%VERTEX_PROJECT_ID%"
) else (
    for /f "delims=" %%p in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider vertex-project 2^>nul ^|^| echo.') do set "PROJECT_ID=%%p"
)
if "%PROJECT_ID%"=="" (
    echo [ERROR] No GCP project ID found. Set VERTEX_PROJECT_ID or store it with claw-cred.ps1:
    echo         powershell -NoProfile -File "%~dp0claw-cred.ps1" -Action Set -Provider vertex-project -Key "PROJECT_ID"
    exit /b 1
)

if not defined CLOUDSDK_CONFIG set "CLOUDSDK_CONFIG=%~dp0..\profiles\gcloud-mozmail"

REM Location: VERTEX_LOCATION env or default global
if not defined VERTEX_LOCATION set "VERTEX_LOCATION=global"

REM Master key: LITELLM_MASTER_KEY env or generate a random one
if not defined LITELLM_MASTER_KEY set "LITELLM_MASTER_KEY=sk-litellm-vertex-proxy-key"

echo [litellm] Starting Vertex AI Claude proxy...
echo [litellm]   Project:  !PROJECT_ID!
echo [litellm]   Location: %VERTEX_LOCATION%
echo [litellm]   Port:     !PORT!
echo [litellm]   Models:   claude-sonnet-4, claude-opus-4
echo [litellm]   Auth:     Google ADC (gcloud auth application-default login)
echo [litellm]   gcloud:   %CLOUDSDK_CONFIG%
echo.

REM Export env vars for LiteLLM
set "VERTEXAI_PROJECT=!PROJECT_ID!"
set "VERTEXAI_LOCATION=%VERTEX_LOCATION%"

REM Start LiteLLM proxy (UTF-8 needed for banner on Windows)
set PYTHONIOENCODING=utf-8
litellm --config "%~dp0litellm_config.yaml" --port !PORT! --host 127.0.0.1 --detailed_debug

goto :end

:stop
echo [litellm] Stopping proxy...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8087.*LISTENING" 2^>nul') do (
    taskkill /PID %%a /F 2>nul
)
echo [litellm] Proxy stopped.
goto :end

:end
endlocal
