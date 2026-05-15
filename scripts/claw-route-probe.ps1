#Requires -Version 5.1
<#
.SYNOPSIS
    Probe a unified Claw/LiteLLM lane and print the backend used right now.
.DESCRIPTION
    Sends a tiny chat completion request through the unified proxy. Unlike
    claw-route-status.ps1, this does make a model call, so it can reveal the
    model actually selected after current rate limits, cooldowns, and fallbacks.
.PARAMETER Model
    Lane or model to probe. Accepts opus, sonnet, haiku, pro, or a raw LiteLLM
    model name such as claw-opus or gemini-3.1-pro-preview.
.PARAMETER Port
    Unified proxy port. Defaults to 8098.
.PARAMETER ApiKey
    LiteLLM master key. Defaults to LITELLM_MASTER_KEY or local launcher default.
#>

param(
    [string]$Model = "opus",
    [int]$Port = 8098,
    [string]$ApiKey = $env:LITELLM_MASTER_KEY
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = "sk-claw-unified-proxy-key"
}

$aliases = @{
    "opus" = "claw-opus"
    "sonnet" = "claw-sonnet"
    "haiku" = "claw-haiku"
    "pro" = "claw-pro"
}

$requested = $Model
if ($aliases.ContainsKey($Model)) {
    $requested = $aliases[$Model]
}
if ($requested.StartsWith("openai/")) {
    $requested = $requested.Substring("openai/".Length)
}

function Label-ApiBase {
    param([string]$ApiBase)
    if ($ApiBase -like "*generativelanguage.googleapis.com*") { return "AI Studio API key" }
    if ($ApiBase -like "*aiplatform.googleapis.com*publishers/google/models/gemini-*") { return "Google Cloud / Vertex credits" }
    if ($ApiBase -like "*aiplatform.googleapis.com*publishers/anthropic/models/claude-*") { return "Google Cloud / Vertex Claude" }
    if ($ApiBase -like "*4000/openai/v1*") { return "VS Code LM / Copilot" }
    if ($ApiBase -like "*8089/v1*") { return "Codex proxy / ChatGPT subscription" }
    if ($ApiBase -like "*deepseek.com*") { return "DeepSeek paid overflow" }
    if ($ApiBase -like "*4999/v1*") { return "Antigravity direct-only" }
    if ([string]::IsNullOrWhiteSpace($ApiBase)) { return "unknown" }
    return "custom/unknown"
}

$uri = "http://127.0.0.1:$Port/v1/chat/completions"
$body = @{
    model = $requested
    max_tokens = 8
    temperature = 0
    messages = @(
        @{ role = "user"; content = "Reply exactly: OK" }
    )
} | ConvertTo-Json -Depth 8

try {
    $response = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri $uri `
        -Method Post `
        -Headers @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" } `
        -Body $body `
        -TimeoutSec 120

    $json = $response.Content | ConvertFrom-Json
    $apiBase = [string]$response.Headers["x-litellm-model-api-base"]
    $provider = Label-ApiBase -ApiBase $apiBase
    $modelGroup = [string]$response.Headers["x-litellm-model-group"]
    $modelId = [string]$response.Headers["x-litellm-model-id"]
    $fallbacks = [string]$response.Headers["x-litellm-attempted-fallbacks"]
    $retries = [string]$response.Headers["x-litellm-attempted-retries"]
    $cost = [string]$response.Headers["x-litellm-response-cost"]
    $duration = [string]$response.Headers["x-litellm-response-duration-ms"]
    $content = ""
    if ($json.choices -and $json.choices.Count -gt 0) {
        $content = [string]$json.choices[0].message.content
    }

    Write-Host "Route probe"
    Write-Host "  requested:          $Model -> $requested"
    Write-Host "  selected group:     $modelGroup"
    Write-Host "  selected id:        $modelId"
    Write-Host "  response model:     $($json.model)"
    Write-Host "  provider:           $provider"
    Write-Host "  fallbacks attempted:$fallbacks"
    Write-Host "  retries attempted:  $retries"
    if (-not [string]::IsNullOrWhiteSpace($cost)) {
        Write-Host "  litellm cost:       $cost"
    }
    if (-not [string]::IsNullOrWhiteSpace($duration)) {
        Write-Host "  duration ms:        $duration"
    }
    if (-not [string]::IsNullOrWhiteSpace($content)) {
        Write-Host "  response:           $content"
    }
    Write-Host "  api base:           $apiBase"
}
catch {
    Write-Host "Route probe failed"
    Write-Host "  requested: $Model -> $requested"
    Write-Host "  error:     $($_.Exception.Message)"
    exit 1
}
