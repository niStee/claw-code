#Requires -Version 5.1
<#
.SYNOPSIS
    Switch the current PowerShell session to a Claw provider route.
.DESCRIPTION
    Sets OPENAI_BASE_URL and OPENAI_API_KEY for the current PowerShell process.
    Keys are read from DPAPI storage through scripts/claw-cred.ps1 where needed.
.EXAMPLE
    scripts\claw-provider.ps1 unified
.EXAMPLE
    scripts\claw-provider.ps1 unified 8098
.EXAMPLE
    scripts\claw-provider.ps1 list
#>

param(
    [string]$Provider = "help",
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-StoredClawSecret {
    param([string]$Name)
    $credScript = Join-Path $ScriptDir "claw-cred.ps1"
    if (-not (Test-Path $credScript)) {
        return $null
    }
    try {
        $value = & powershell -NoProfile -ExecutionPolicy Bypass -File $credScript -Action Get -Provider $Name 2>$null
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }
        return [string]$value
    } catch {
        return $null
    }
}

function Clear-AnthropicRoute {
    Remove-Item Env:\ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
}

function Set-OpenAICompatRoute {
    param(
        [string]$BaseUrl,
        [string]$ApiKey
    )
    $env:OPENAI_BASE_URL = $BaseUrl
    $env:OPENAI_API_KEY = $ApiKey
    Clear-AnthropicRoute
}

function Format-KeyLabel {
    param([string]$ApiKey)
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        return "missing"
    }
    if ($ApiKey -in @("sk-claw-unified-proxy-key", "sk-litellm-vertex-proxy-key", "sk-codex-proxy", "copilot")) {
        return $ApiKey
    }
    return "set (hidden)"
}

function Show-Route {
    param(
        [string]$Name,
        [string]$BaseUrl,
        [string]$ApiKeyLabel,
        [string[]]$Models,
        [string]$Note
    )
    Write-Host "[claw] Switched to $Name"
    Write-Host "  OPENAI_BASE_URL: $BaseUrl"
    Write-Host "  OPENAI_API_KEY:  $ApiKeyLabel"
    if ($Models.Count -gt 0) {
        Write-Host "  Models:"
        foreach ($model in $Models) {
            Write-Host "    $model"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Note)) {
        Write-Host "  Note: $Note"
    }
}

function Show-Usage {
    Write-Host "Usage: scripts\claw-provider.ps1 <provider> [port]"
    Write-Host ""
    Write-Host "Providers:"
    Write-Host "  unified [port]  Recommended quota-first route tap + LiteLLM proxy"
    Write-Host "  codex           ChatGPT subscription via local codex-proxy"
    Write-Host "  gemini          AI Studio OpenAI-compatible API"
    Write-Host "  vertex          Vertex/Gemini via local LiteLLM proxy"
    Write-Host "  copilot         VS Code LM proxy"
    Write-Host "  deepseek        Official paid overflow API"
    Write-Host "  list            Show provider summary"
}

function Show-List {
    Write-Host "Claw provider routes"
    Write-Host "  unified   -> http://127.0.0.1:<port>/v1, models claw-opus/sonnet/haiku/pro"
    Write-Host "               default port is 8099 route tap; use 8098 for LiteLLM direct"
    Write-Host "  codex     -> http://127.0.0.1:8089/v1, ChatGPT subscription proxy"
    Write-Host "  gemini    -> https://generativelanguage.googleapis.com/v1beta/openai/, AI Studio key"
    Write-Host "  vertex    -> http://127.0.0.1:8087/v1, Vertex LiteLLM proxy"
    Write-Host "  copilot   -> http://127.0.0.1:4000/openai/v1, VS Code LM proxy"
    Write-Host "  deepseek  -> https://api.deepseek.com, paid overflow"
    Write-Host ""
    Write-Host "Recommended default:"
    Write-Host "  scripts\claw-stack.ps1 start"
    Write-Host "  scripts\claw-provider.ps1 unified"
    Write-Host "  or: scripts\claw-stack.ps1 start"
}

switch ($Provider.ToLowerInvariant()) {
    "unified" {
        if ($Port -le 0) { $Port = 8099 }
        if ([string]::IsNullOrWhiteSpace($env:LITELLM_MASTER_KEY)) {
            $env:LITELLM_MASTER_KEY = "sk-claw-unified-proxy-key"
        }
        $base = "http://127.0.0.1:$Port/v1"
        Set-OpenAICompatRoute -BaseUrl $base -ApiKey $env:LITELLM_MASTER_KEY
        $note = if ($Port -eq 8099) {
            "Route tap enabled; use scripts\claw-route-last.ps1 to see the selected backend. DeepSeek remains paid overflow behind the configured lanes."
        } else {
            "Using the supplied port. Port 8098 is LiteLLM direct; port 8099 is the route tap with selected-backend logging."
        }
        Show-Route `
            -Name "unified quota-first Claw route" `
            -BaseUrl $base `
            -ApiKeyLabel (Format-KeyLabel $env:LITELLM_MASTER_KEY) `
            -Models @("opus -> openai/claw-opus", "sonnet -> openai/claw-sonnet", "haiku -> openai/claw-haiku", "pro/think -> openai/claw-pro") `
            -Note $note
    }
    "codex" {
        $key = if ([string]::IsNullOrWhiteSpace($env:CODEX_PROXY_API_KEY)) { "pwd" } else { $env:CODEX_PROXY_API_KEY }
        $base = if ([string]::IsNullOrWhiteSpace($env:CODEX_PROXY_BASE_URL)) { "http://127.0.0.1:8089/v1" } else { $env:CODEX_PROXY_BASE_URL }
        Set-OpenAICompatRoute -BaseUrl $base -ApiKey $key
        Show-Route -Name "ChatGPT via codex-proxy" -BaseUrl $base -ApiKeyLabel (Format-KeyLabel $key) -Models @("openai/gpt-5.5", "openai/gpt-5.4", "openai/gpt-5.4-mini", "openai/gpt-5.3-codex", "openai/o3") -Note "Start scripts\claw-codex-proxy.bat first."
    }
    "gemini" {
        $key = Get-StoredClawSecret "gemini"
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "No Gemini key found. Store it with: powershell -NoProfile -File scripts\claw-cred.ps1 -Action Set -Provider gemini"
        }
        $base = "https://generativelanguage.googleapis.com/v1beta/openai/"
        Set-OpenAICompatRoute -BaseUrl $base -ApiKey $key
        Show-Route -Name "AI Studio Gemini" -BaseUrl $base -ApiKeyLabel "DPAPI gemini key" -Models @("openai/gemini-3-flash-preview", "openai/gemini-3.1-pro-preview", "openai/gemini-2.5-pro", "openai/gemini-2.5-flash") -Note "AI Studio API calls use an API key, not Gemini CLI OAuth."
    }
    "vertex" {
        if ($Port -le 0) { $Port = 8087 }
        $project = Get-StoredClawSecret "vertex-project"
        if ([string]::IsNullOrWhiteSpace($project)) {
            $project = $env:VERTEX_PROJECT_ID
        }
        if ([string]::IsNullOrWhiteSpace($project)) {
            throw "No Vertex project found. Store it with: powershell -NoProfile -File scripts\claw-cred.ps1 -Action Set -Provider vertex-project"
        }
        if ([string]::IsNullOrWhiteSpace($env:LITELLM_MASTER_KEY)) {
            $env:LITELLM_MASTER_KEY = "sk-litellm-vertex-proxy-key"
        }
        if ([string]::IsNullOrWhiteSpace($env:VERTEX_LOCATION)) {
            $env:VERTEX_LOCATION = "global"
        }
        $env:VERTEX_PROJECT_ID = $project
        $base = "http://127.0.0.1:$Port/v1"
        Set-OpenAICompatRoute -BaseUrl $base -ApiKey $env:LITELLM_MASTER_KEY
        Show-Route -Name "Vertex/Gemini via LiteLLM proxy" -BaseUrl $base -ApiKeyLabel (Format-KeyLabel $env:LITELLM_MASTER_KEY) -Models @("openai/gemini-3.1-pro-preview", "openai/gemini-3-flash-preview", "openai/gemini-2.5-flash") -Note "Start scripts\claw-vertex-proxy.bat first. Vertex Claude partner models are not part of the normal quota-first setup."
    }
    "copilot" {
        $base = if ([string]::IsNullOrWhiteSpace($env:VSCODE_LM_PROXY_BASE_URL)) { "http://127.0.0.1:4000/openai/v1" } else { $env:VSCODE_LM_PROXY_BASE_URL }
        $key = if ([string]::IsNullOrWhiteSpace($env:VSCODE_LM_PROXY_API_KEY)) { "copilot" } else { $env:VSCODE_LM_PROXY_API_KEY }
        Set-OpenAICompatRoute -BaseUrl $base -ApiKey $key
        Show-Route -Name "VS Code LM proxy" -BaseUrl $base -ApiKeyLabel (Format-KeyLabel $key) -Models @("openai/vscode-auto", "openai/vscode-gpt-5-mini", "openai/vscode-gpt-4.1", "openai/vscode-gpt-4o", "openai/vscode-gpt-4o-mini", "openai/vscode-claude-haiku") -Note "Requires the VS Code LM proxy to be running. Prefer vscode-auto when avoiding model-specific Copilot limits."
    }
    "deepseek" {
        $key = Get-StoredClawSecret "deepseek"
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "No DeepSeek key found. Store it with: powershell -NoProfile -File scripts\claw-cred.ps1 -Action Set -Provider deepseek"
        }
        $base = "https://api.deepseek.com"
        Set-OpenAICompatRoute -BaseUrl $base -ApiKey $key
        Show-Route -Name "DeepSeek paid overflow" -BaseUrl $base -ApiKeyLabel "DPAPI deepseek key" -Models @("openai/deepseek-v4-pro", "openai/deepseek-v4-flash") -Note "Use as overflow, not as the default primary lane."
    }
    "list" { Show-List }
    "help" { Show-Usage }
    default {
        Show-Usage
        throw "Unknown provider '$Provider'."
    }
}
