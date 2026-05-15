@echo off
REM ============================================================
REM  SECURITY WARNING: Never use setx for API keys.
REM  Store keys via claw-cred.ps1 (DPAPI-encrypted files).
REM  API keys stored via setx are plaintext in the registry.
REM  Rotate keys periodically. Never commit keys to git.
REM
REM  API key portals:
REM    DeepSeek:  https://platform.deepseek.com/api_keys
REM    Gemini:    https://aistudio.google.com/app/apikey
REM    Copilot:   https://github.com/settings/copilot
REM    Vertex AI: https://console.cloud.google.com/vertex-ai
REM ============================================================
REM ============================================================
REM  Claw-Code Provider Switcher - May 2026 Model Names
REM  Sets OPENAI_API_KEY and OPENAI_BASE_URL per provider
REM  Usage: claw-provider.bat <provider>
REM    unified | deepseek | gemini | copilot | vertex | codex
REM
REM  API keys are retrieved from DPAPI-encrypted files stored
REM  via claw-cred.ps1. Use the secure prompt form:
REM    powershell -File claw-cred.ps1 -Action Set -Provider gemini
REM ============================================================

if "%1"=="" goto :usage
if /I "%1"=="help" goto :usage
if /I "%1"=="unified" goto :unified
if /I "%1"=="deepseek" goto :deepseek
if /I "%1"=="gemini" goto :gemini
if /I "%1"=="copilot" goto :copilot
if /I "%1"=="vertex" goto :vertex
if /I "%1"=="codex" goto :codex
if /I "%1"=="list" goto :list
goto :usage

REM [UNIFIED] Quota-first local LiteLLM proxy.
REM Proxy: Start with `claw-stack.bat start` before using this provider.
:unified
set "UNIFIED_PORT=%~2"
if "%UNIFIED_PORT%"=="" set "UNIFIED_PORT=8099"
echo [claw] Switching to unified quota-first Claw route
echo   NOTE: Requires unified proxy running on 127.0.0.1:%UNIFIED_PORT%
echo         Start proxy first: claw-stack.bat start
if not defined LITELLM_MASTER_KEY set LITELLM_MASTER_KEY=sk-claw-unified-proxy-key
set OPENAI_API_KEY=%LITELLM_MASTER_KEY%
set OPENAI_BASE_URL=http://127.0.0.1:%UNIFIED_PORT%/v1
set ANTHROPIC_BASE_URL=
set ANTHROPIC_AUTH_TOKEN=
echo   Base URL: http://127.0.0.1:%UNIFIED_PORT%/v1
if "%LITELLM_MASTER_KEY%"=="sk-claw-unified-proxy-key" (
    echo   Key:      sk-claw-unified-proxy-key
) else if "%LITELLM_MASTER_KEY%"=="sk-litellm-vertex-proxy-key" (
    echo   Key:      sk-litellm-vertex-proxy-key
) else (
    echo   Key:      set ^(hidden^)
)
echo   Aliases:
echo     opus, sonnet, haiku, fast, pro, think
echo   Policy:
echo     subscription/credit routes first, DeepSeek pay-as-you-go overflow last
if "%UNIFIED_PORT%"=="8099" (
    echo   Visibility:
    echo     route tap enabled; run scripts\claw-route-last.ps1 to see selected backend
) else (
    echo   Visibility:
    echo     supplied port used; 8098 is LiteLLM direct, 8099 is route tap
)
goto :end

REM [DEEPSEEK] Low risk - official API
REM Portal: https://platform.deepseek.com/api_keys
:deepseek
echo [claw] Switching to DeepSeek V4
REM Retrieve API key from DPAPI-encrypted storage
for /f "delims=" %%k in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider deepseek 2^>nul ^|^| echo.') do set "DEEPSEEK_API_KEY=%%k"
if "%DEEPSEEK_API_KEY%"=="" (
    echo   ERROR: No API key found for DeepSeek.
    echo   Run: powershell -NoProfile -File "%~dp0claw-cred.ps1" -Action Set -Provider deepseek
    goto :end
)
set OPENAI_API_KEY=%DEEPSEEK_API_KEY%
set OPENAI_BASE_URL=https://api.deepseek.com
echo   Models: deepseek-v4-pro (alias: pro, think)
echo          deepseek-v4-flash (alias: fast)
goto :end

REM [GEMINI] Low risk - official OpenAI-compatible endpoint
REM Portal: https://aistudio.google.com/app/apikey
:gemini
echo [claw] Switching to Google Gemini (AI Studio)
for /f "delims=" %%k in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider gemini 2^>nul ^|^| echo.') do set "GEMINI_API_KEY=%%k"
if "%GEMINI_API_KEY%"=="" (
    echo   ERROR: No API key found for Gemini.
    echo   Run: powershell -NoProfile -File "%~dp0claw-cred.ps1" -Action Set -Provider gemini
    goto :end
)
set OPENAI_API_KEY=%GEMINI_API_KEY%
set OPENAI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/
echo   Models: gemini-3-flash-preview (alias: gemini-flash, gemini^) -- FREE tier, works
echo          gemini-2.5-flash (alias: gemini-fast^) -- FREE tier, stable
echo          gemini-2.5-pro -- PAID tier, reasoning (needs billing)
echo          NOTE: gemini-pro alias -^> gemini-3-flash-preview ^(free tier^)
goto :end

REM [COPILOT] Higher risk - gray area ToS, light personal use only
REM Portal: https://github.com/settings/copilot
REM NOTE: Copilot uses a 127.0.0.1 proxy with dummy key; no credential storage needed
:copilot
echo [claw] Switching to GitHub Copilot (via vscode-lm-proxy)
set OPENAI_API_KEY=copilot
set OPENAI_BASE_URL=http://127.0.0.1:4000/openai/v1
echo   Working models (Copilot Education):
echo     gpt-4o (alias: copilot-gpt) -- confirmed
echo     claude-haiku-4.5 (alias: copilot-haiku, copilot-claude) -- confirmed
echo     gemini-2.5-pro (alias: copilot-gemini) -- BROKEN (400 Bad Request via proxy)
echo     gpt-4o-mini (alias: copilot-mini) -- confirmed
echo     gpt-5-mini -- confirmed
echo   Broken: gemini-2.5-pro (400), gpt-5.3-codex (empty), gemini-3.1-* (500)
goto :end

REM [VERTEX] Medium risk - uses LiteLLM translation proxy, supported API
REM Portal: https://console.cloud.google.com/vertex-ai
REM Proxy:  Start with `claw-vertex-proxy.bat` before using this provider
:vertex
echo [claw] Switching to Google Vertex AI (Gemini via LiteLLM proxy)
echo   NOTE: Requires GCP project + gcloud auth + running LiteLLM proxy
echo         Start proxy first: claw-vertex-proxy.bat
for /f "delims=" %%k in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claw-cred.ps1" -Action Get -Provider vertex-project 2^>nul ^|^| echo.') do set "VERTEX_PROJECT=%%k"
if "%VERTEX_PROJECT%"=="" (
    echo   ERROR: No GCP project ID found for Vertex AI.
    echo   Run: powershell -NoProfile -File "%~dp0claw-cred.ps1" -Action Set -Provider vertex-project
    goto :end
)
REM Set env vars for LiteLLM proxy (claw-vertex-proxy.bat reads these)
set VERTEX_PROJECT_ID=%VERTEX_PROJECT%
if not defined VERTEX_LOCATION set VERTEX_LOCATION=global
if not defined LITELLM_MASTER_KEY set LITELLM_MASTER_KEY=sk-litellm-vertex-proxy-key
REM Route through OpenAI-compat client to LiteLLM proxy
set OPENAI_BASE_URL=http://127.0.0.1:8087/v1
set OPENAI_API_KEY=%LITELLM_MASTER_KEY%
REM Clear Anthropic env vars (not used for this path)
set ANTHROPIC_BASE_URL=
set ANTHROPIC_AUTH_TOKEN=
echo   Project:  %VERTEX_PROJECT%
echo   Location: %VERTEX_LOCATION%
echo   Proxy:    http://127.0.0.1:8087 (LiteLLM)
echo   Models (use with --model openai/MODEL):
echo     gemini-3.1-pro-preview
echo     gemini-3-flash-preview
echo     gemini-2.5-flash
echo   NOTE: Vertex Claude partner models are not part of the normal quota-first setup.
echo   NOTE: Ensure proxy is running: claw-vertex-proxy.bat
goto :end

REM [CODEX] Low risk - ChatGPT subscription via codex-proxy (OAuth, no API key)
REM Portal: https://chat.openai.com/
REM Proxy:  Start with `claw-codex-proxy.bat` before using this provider
REM NOTE:   Uses browser OAuth; open http://127.0.0.1:8089 to log in with ChatGPT account
:codex
echo [claw] Switching to ChatGPT via codex-proxy (browser OAuth)
echo   NOTE: Requires codex-proxy running on 127.0.0.1:8089
echo         Start proxy first: claw-codex-proxy.bat
set OPENAI_API_KEY=pwd
set OPENAI_BASE_URL=http://127.0.0.1:8089/v1
echo   API Key: pwd ^(local codex-proxy key from data\local.yaml^)
echo   Base URL: http://127.0.0.1:8089/v1
echo   Models ^(use with --model openai/MODEL^):
echo     gpt-5.5 ^(alias: codex, gpt5^) - flagship, Plus+
echo     gpt-5.4 ^(alias: codex-pro^) - latest default
echo     gpt-5.4-mini ^(alias: codex-fast^) - lightweight
echo     gpt-5.3-codex ^(alias: gpt5-codex^) - coding-optimized
echo     claw-pro ^(alias: codex-think^) - unified high-capability lane
echo   NOTE: Ensure proxy is running: claw-codex-proxy.bat
echo   NOTE: First time? Open http://127.0.0.1:8089 in browser to log in
goto :end

:list
echo.
echo ============================================================
echo   Claw-Code Provider Matrix (May 2026)
echo ============================================================
echo.
echo   1. UNIFIED QUOTA-FIRST PROXY - RECOMMENDED DEFAULT
echo      Prereq: Start local proxy with claw-stack.bat
echo      Step 1: claw-stack.bat start
echo      Step 2: claw-provider.bat unified
echo      Run:  claw --model openai/claw-opus
echo      Note: Subscription/credit providers first, DeepSeek paid overflow last
echo.
echo   2. DEEPSEEK V4 - LOW RISK
echo      Env:  OPENAI_BASE_URL=https://api.deepseek.com
echo      Key:  OPENAI_API_KEY=^<retrieved from DPAPI storage^>
echo      Run:  claw --model openai/deepseek-v4-pro
echo      Note: Official API, pay-as-you-go overflow when quota routes fail
echo.
echo   3. GOOGLE GEMINI - LOW RISK
echo      Env:  OPENAI_BASE_URL=https://generativelanguage.../v1beta/openai/
echo      Key:  OPENAI_API_KEY=^<retrieved from DPAPI storage^>
echo      Run:  claw --model openai/gemini-3-flash-preview
echo      Note: Official OpenAI-compatible endpoint, use quota/credits before DeepSeek
echo.
echo   4. GITHUB COPILOT - HIGH RISK
echo      Prereq: VS Code extension 'ryonakae.vscode-lm-proxy' installed
echo      Env:  OPENAI_BASE_URL=http://127.0.0.1:4000/openai/v1
echo      Key:  OPENAI_API_KEY=copilot
echo      Run:  claw --model openai/gpt-4o
echo      Note: Gray area ToS, rate limit bans possible - tertiary only
echo.
echo   5. VERTEX AI GEMINI - MEDIUM RISK
echo      Prereq: GCP project + gcloud auth + LiteLLM proxy
echo      Step 1: claw-vertex-proxy.bat (start proxy in separate terminal)
echo      Step 2: claw-provider.bat vertex
echo      Run:  claw --model openai/gemini-3.1-pro-preview
echo      Note: Uses LiteLLM proxy with Google ADC; direct-only until billing/quota is settled
echo.
echo   6. CHATGPT via CODEX-PROXY - LOW RISK
echo      Prereq: ChatGPT account (free/plus) + codex-proxy running
echo      Step 1: claw-codex-proxy.bat (start proxy in separate terminal)
echo      Step 2: claw-provider.bat codex
echo      Run:  claw --model openai/gpt-5.5
echo      Note: Browser OAuth, no API key
echo.
echo   7. ANTHROPIC DIRECT (when API key available)
echo      Env:  ANTHROPIC_API_KEY=^<retrieved from DPAPI storage^>
echo      Run:  claw --model claude-sonnet-4-6
echo.
echo   Model aliases in .claw/settings.local.json:
echo     fast, pro, think, gemini-pro, gemini-flash, gemini
echo     vscode-gpt-4o, vscode-gpt-4o-mini, vertex-gemini-pro
echo     vertex-gemini-flash, opus, sonnet, haiku, claude
echo     codex, codex-fast, codex-think, gpt5, gpt5-codex
echo.
goto :end

:usage
echo.
echo ============================================================
echo   CLAW-PROVIDER - Recommended Failover Chain
echo ============================================================
echo   DEFAULT:
echo     unified  - quota-first local LiteLLM proxy
echo                subscription/credit routes before DeepSeek
echo.
echo   DIRECT PROVIDERS:
echo     gemini    - official OpenAI-compatible endpoint
echo     vertex    - supported API, needs translation proxy
echo.
echo   LOCAL/SUBSCRIPTION PROXIES:
echo     copilot   - VS Code LM proxy, light personal use only
echo     codex     - ChatGPT via codex-proxy, browser OAuth
echo.
echo   PAID OVERFLOW:
echo     deepseek  - official API, pay-as-you-go fallback
echo.
echo   EXPERIMENTAL DIRECT ONLY:
echo     antigravity-opus - never in default fallback chains
echo ============================================================
echo.
echo   Usage: claw-provider.bat ^<provider^>
echo          claw-provider.bat list
echo          claw-provider.bat help
echo          claw-provider.bat unified [port] ^| deepseek ^| gemini ^| copilot ^| vertex ^| codex
echo.
echo   API KEY SETUP ^(DPAPI-encrypted, per-user^)
echo   Store keys once with claw-cred.ps1:
echo.
echo     powershell -File scripts\claw-cred.ps1 -Action Set -Provider deepseek
echo.
echo     powershell -File scripts\claw-cred.ps1 -Action Set -Provider gemini
echo.
echo     powershell -File scripts\claw-cred.ps1 -Action Set -Provider vertex-project
echo.
echo   List stored keys:
echo     powershell -File scripts\claw-cred.ps1 -Action List
echo.
echo   Test decryptability:
echo     powershell -File scripts\claw-cred.ps1 -Action Test
echo.
echo   Keys stored in: %%APPDATA%%\claw-code\keys\
echo.
echo   WARNING: API keys are set via 'set' ^(session only, not persisted to registry^).
echo      Use claw-cred.ps1 for permanent DPAPI-encrypted storage.
echo   WARNING: NEVER commit keys to git. Encrypted .enc files are gitignored.
echo.

:end
