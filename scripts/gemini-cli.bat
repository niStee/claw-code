@echo off
setlocal

set "REPO_ROOT=%~dp0.."
set "GEMINI_JS=%REPO_ROOT%\tools\gemini-cli\package\bundle\gemini.js"
set "BUNDLED_NODE=%LOCALAPPDATA%\OpenAI\Codex\bin\node.exe"

where node >nul 2>nul
if %ERRORLEVEL%==0 (
    set "NODE_CMD=node"
) else (
    set "NODE_CMD=%BUNDLED_NODE%"
)

if not exist "%GEMINI_JS%" (
    echo [gemini-cli] Missing Gemini CLI package at "%GEMINI_JS%".
    echo [gemini-cli] Run the local bootstrap first.
    exit /b 1
)

if not exist "%NODE_CMD%" if not "%NODE_CMD%"=="node" (
    echo [gemini-cli] Node.js was not found on PATH or at "%BUNDLED_NODE%".
    exit /b 1
)

"%NODE_CMD%" "%GEMINI_JS%" %*
exit /b %ERRORLEVEL%
