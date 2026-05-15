@echo off
REM ============================================================================
REM  Claw unified LiteLLM proxy starter
REM
REM  Starts a local OpenAI-compatible LiteLLM proxy for quota-first Claw aliases.
REM  DeepSeek is configured only as pay-as-you-go overflow.
REM
REM  Usage:
REM    claw-stack.bat                      Start helper proxies + LiteLLM
REM    claw-unified-proxy.bat              Start LiteLLM only on default port 8098
REM    claw-unified-proxy.bat 9090         Start on custom port
REM    claw-unified-proxy.bat status       Show default port status
REM    claw-unified-proxy.bat status 9090  Show custom port status
REM    claw-unified-proxy.bat stop         Stop default port
REM    claw-unified-proxy.bat stop 9090    Stop custom port
REM ============================================================================

setlocal enabledelayedexpansion

set "COMMAND=start"
set "PORT=8098"

if /I "%~1"=="stop" (
    set "COMMAND=stop"
    if not "%~2"=="" set "PORT=%~2"
) else if /I "%~1"=="status" (
    set "COMMAND=status"
    if not "%~2"=="" set "PORT=%~2"
) else if not "%~1"=="" (
    set "PORT=%~1"
)

if "%COMMAND%"=="stop" goto :stop
if "%COMMAND%"=="status" goto :status

set "LITELLM_CMD=litellm"
where litellm >nul 2>nul
if errorlevel 1 (
    set "LITELLM_CMD="
    if exist "%LOCALAPPDATA%\Programs\Python\Python312\Scripts\litellm.exe" (
        set "LITELLM_CMD=%LOCALAPPDATA%\Programs\Python\Python312\Scripts\litellm.exe"
    ) else (
        for /f "delims=" %%l in ('powershell -NoProfile -Command "(Get-Command litellm -ErrorAction SilentlyContinue).Source" 2^>nul') do set "LITELLM_CMD=%%l"
    )
)
if not defined LITELLM_CMD (
    echo [ERROR] litellm.exe was not found.
    echo         Install or activate LiteLLM, or set PATH so cmd.exe can find it.
    exit /b 1
)

for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT%.*LISTENING" 2^>nul') do (
    echo [ERROR] Port %PORT% is already listening ^(PID %%a^).
    echo         Use scripts\claw-unified-proxy.bat status %PORT% or choose another port.
    exit /b 1
)

if not defined VERTEX_LOCATION set "VERTEX_LOCATION=global"
if not defined LITELLM_MASTER_KEY set "LITELLM_MASTER_KEY=sk-claw-unified-proxy-key"

if "%LITELLM_MASTER_KEY%"=="sk-claw-unified-proxy-key" (
    echo [WARN] Using default local LiteLLM master key.
    echo        This is acceptable on 127.0.0.1, but set LITELLM_MASTER_KEY for shared machines.
)

REM DPAPI-backed keys. Missing optional providers get dummy values so LiteLLM can start;
REM actual calls will fail and fall through to the next configured fallback.
if not defined DEEPSEEK_API_KEY (
    for /f "delims=" %%k in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider deepseek 2^>nul ^|^| echo.') do set "DEEPSEEK_API_KEY=%%k"
)
if not defined DEEPSEEK_API_KEY if exist "%APPDATA%\claw-code\keys\deepseek.enc" (
    echo [WARN] Stored DeepSeek key exists but could not be loaded by claw-cred.ps1.
)
if not defined GEMINI_API_KEY (
    for /f "delims=" %%k in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider gemini 2^>nul ^|^| echo.') do set "GEMINI_API_KEY=%%k"
)
if not defined GEMINI_API_KEY if exist "%APPDATA%\claw-code\keys\gemini.enc" (
    echo [WARN] Stored Gemini key exists but could not be loaded by claw-cred.ps1.
    echo        Set GEMINI_API_KEY in this terminal before starting the proxy, or re-store the key.
)
if not defined VERTEX_PROJECT_ID (
    for /f "delims=" %%k in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider vertex-project 2^>nul ^|^| echo.') do set "VERTEX_PROJECT_ID=%%k"
)
if not defined VERTEX_PROJECT_ID if exist "%APPDATA%\claw-code\keys\vertex-project.enc" (
    echo [WARN] Stored Vertex project exists but could not be loaded by claw-cred.ps1.
)
if not defined DEEPSEEK_API_KEY set "DEEPSEEK_API_KEY=sk-missing-deepseek-key"
if not defined GEMINI_API_KEY set "GEMINI_API_KEY=AIza-missing-gemini-key"
if not defined VERTEX_PROJECT_ID set "VERTEX_PROJECT_ID=missing-vertex-project"
if not defined CLOUDSDK_CONFIG set "CLOUDSDK_CONFIG=%~dp0..\profiles\gcloud-mozmail"
if not defined GOOGLE_CLOUD_PROJECT set "GOOGLE_CLOUD_PROJECT=%VERTEX_PROJECT_ID%"
if not defined GOOGLE_CLOUD_LOCATION set "GOOGLE_CLOUD_LOCATION=%VERTEX_LOCATION%"
set "GOOGLE_GENAI_USE_VERTEXAI=True"

if not defined CODEX_PROXY_BASE_URL set "CODEX_PROXY_BASE_URL=http://127.0.0.1:8089/v1"
if not defined CODEX_PROXY_API_KEY set "CODEX_PROXY_API_KEY=pwd"

if not defined VSCODE_LM_PROXY_BASE_URL set "VSCODE_LM_PROXY_BASE_URL=http://127.0.0.1:4000/openai/v1"
if not defined VSCODE_LM_PROXY_API_KEY set "VSCODE_LM_PROXY_API_KEY=copilot"

if not defined ANTIGRAVITY_BASE_URL set "ANTIGRAVITY_BASE_URL=http://127.0.0.1:4999/v1"
if not defined ANTIGRAVITY_API_KEY set "ANTIGRAVITY_API_KEY=antigravity-local"

set "VERTEXAI_PROJECT=%VERTEX_PROJECT_ID%"
set "VERTEXAI_LOCATION=%VERTEX_LOCATION%"
set "PYTHONIOENCODING=utf-8"

echo [claw-unified] Starting LiteLLM proxy...
echo [claw-unified]   Port:     %PORT%
echo [claw-unified]   Config:   %~dp0litellm_unified_config.yaml
echo [claw-unified]   LiteLLM:  %LITELLM_CMD%
if "%LITELLM_MASTER_KEY%"=="sk-claw-unified-proxy-key" (
    echo [claw-unified]   Key:      sk-claw-unified-proxy-key
) else if "%LITELLM_MASTER_KEY%"=="sk-litellm-vertex-proxy-key" (
    echo [claw-unified]   Key:      sk-litellm-vertex-proxy-key
) else (
    echo [claw-unified]   Key:      set ^(hidden^)
)
echo [claw-unified]   Vertex:   %VERTEX_PROJECT_ID% / %VERTEX_LOCATION%
echo [claw-unified]   Gemini:   Google Cloud ADC %GOOGLE_CLOUD_PROJECT% / %GOOGLE_CLOUD_LOCATION%
echo [claw-unified]   gcloud:   %CLOUDSDK_CONFIG%
if "%GEMINI_API_KEY%"=="AIza-missing-gemini-key" (
    echo [claw-unified]   AI Studio: no Gemini API key found; direct aistudio-* calls will fail
) else (
    echo [claw-unified]   AI Studio: Gemini API key route enabled
)
echo [claw-unified]   Codex:    %CODEX_PROXY_BASE_URL%
echo [claw-unified]   VS Code:  %VSCODE_LM_PROXY_BASE_URL%
echo [claw-unified]   DeepSeek: overflow only
echo.
echo [claw-unified] In another shell run:
echo   Recommended full stack:
echo     "%~dp0claw-stack.bat" start
echo.
echo   PowerShell:
echo     scripts\claw-provider.ps1 unified %PORT%
echo     REM or set the environment manually:
echo     $env:OPENAI_BASE_URL = "http://127.0.0.1:%PORT%/v1"
echo     $env:OPENAI_API_KEY = "%LITELLM_MASTER_KEY%"
echo.
echo   cmd.exe:
echo     call "%~dp0claw-provider.bat" unified %PORT%
echo.
echo   claw --model openai/claw-opus "hello"
echo   REM In this repo, alias 'opus' also resolves to openai/claw-opus.
echo   "%~dp0claw-route-status.bat"
echo   "%~dp0claw-route-probe.bat" opus %PORT%
echo.

"%LITELLM_CMD%" --config "%~dp0litellm_unified_config.yaml" --port %PORT% --host 127.0.0.1
goto :end

:status
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT%.*LISTENING" 2^>nul') do (
    echo [claw-unified] Proxy is listening on port %PORT% ^(PID %%a^).
    goto :end
)
echo [claw-unified] No proxy is listening on port %PORT%.
goto :end

:stop
set "FOUND=0"
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%PORT%.*LISTENING" 2^>nul') do (
    set "FOUND=1"
    echo [claw-unified] Stopping PID %%a on port %PORT%...
    taskkill /PID %%a /F 2>nul
)
if "%FOUND%"=="0" echo [claw-unified] No proxy was listening on port %PORT%.
goto :end

:end
endlocal
