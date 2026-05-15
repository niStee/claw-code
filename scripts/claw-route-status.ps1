#Requires -Version 5.1
<#
.SYNOPSIS
    Show the effective Claw LiteLLM lane routing without making model calls.
.DESCRIPTION
    Reads scripts/litellm_unified_config.yaml and prints each public Claw lane
    with its current primary deployment and fallback order. This is a static
    config inspection; the actually used model for a specific request is the
    first healthy deployment in that lane at request time.
.PARAMETER Config
    Path to the LiteLLM YAML config.
#>

param(
    [string]$Config = (Join-Path $PSScriptRoot "litellm_unified_config.yaml")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Config)) {
    Write-Error "Config not found: $Config"
    exit 1
}

function Read-YamlConfig {
    param([string]$Path)
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Error "python is required to parse YAML for this status script."
        exit 1
    }
    $json = & python -c @"
import json, yaml
with open(r'''$Path''', encoding='utf-8') as f:
    print(json.dumps(yaml.safe_load(f), ensure_ascii=False))
"@
    return $json | ConvertFrom-Json
}

function Get-ProviderLabel {
    param([object]$Params)
    $model = [string]$Params.model
    $apiBase = [string]$Params.api_base

    if ($model.StartsWith("vertex_ai/gemini-")) { return "Google Cloud / Vertex credits" }
    if ($model.StartsWith("vertex_ai/claude-")) { return "Google Cloud / Vertex Claude" }
    if ($apiBase -like "*generativelanguage.googleapis.com*") { return "AI Studio API key" }
    if ($apiBase -like "*VSCODE_LM_PROXY_BASE_URL*") { return "VS Code LM / Copilot" }
    if ($apiBase -like "*4000/openai/v1*") { return "VS Code LM / Copilot" }
    if ($apiBase -like "*CODEX_PROXY_BASE_URL*") { return "Codex proxy / ChatGPT subscription" }
    if ($apiBase -like "*8089/v1*") { return "Codex proxy / ChatGPT subscription" }
    if ($apiBase -like "*ANTIGRAVITY_BASE_URL*") { return "Antigravity direct-only" }
    if ($apiBase -like "*deepseek.com*") { return "DeepSeek paid overflow" }
    if ($apiBase -like "*4999/v1*") { return "Antigravity direct-only" }
    return "unknown"
}

function Get-CostLabel {
    param([string]$Provider)
    if ($Provider -like "*DeepSeek*") { return "paid overflow" }
    if ($Provider -like "*Vertex credits*") { return "finite credits" }
    if ($Provider -like "*AI Studio*") { return "subscription/quota" }
    if ($Provider -like "*Codex*" -or $Provider -like "*VS Code*") { return "subscription/quota" }
    if ($Provider -like "*Antigravity*") { return "risky direct-only" }
    return "quota/credit"
}

function Format-Deployment {
    param(
        [string]$Name,
        [object]$Model
    )
    if (-not $Model) {
        return "$Name => MISSING"
    }
    $params = $Model.litellm_params
    $provider = Get-ProviderLabel -Params $params
    $cost = Get-CostLabel -Provider $provider
    return "$Name => $($params.model) [$provider; $cost]"
}

$cfg = Read-YamlConfig -Path $Config
$models = @{}
foreach ($m in $cfg.model_list) {
    $models[$m.model_name] = $m
}

$fallbacks = @{}
foreach ($entry in $cfg.router_settings.fallbacks) {
    $prop = $entry.PSObject.Properties | Select-Object -First 1
    if ($prop) {
        $fallbacks[$prop.Name] = @($prop.Value)
    }
}

$lanes = @("claw-opus", "claw-sonnet", "claw-haiku", "claw-pro")

Write-Host "Claw unified routing lanes"
Write-Host "Config: $Config"
Write-Host ""
Write-Host "Note: 'active now' means the primary below until it errors/rate-limits; then LiteLLM tries fallbacks in order."
Write-Host "Actual Roo/Claw calls are traced by the route tap: use http://127.0.0.1:8099/v1 and run scripts\claw-route-last.ps1."
Write-Host ""

foreach ($lane in $lanes) {
    $display = $lane -replace '^claw-', ''
    Write-Host ("[{0}]" -f $display)
    Write-Host ("  primary  {0}" -f (Format-Deployment -Name $lane -Model $models[$lane]))

    $chain = @($fallbacks[$lane])
    if ($chain.Count -gt 0) {
        $i = 1
        foreach ($fallback in $chain) {
            Write-Host ("  fb{0,-6} {1}" -f $i, (Format-Deployment -Name $fallback -Model $models[$fallback]))
            $i++
        }
    } else {
        Write-Host "  fallbacks none"
    }
    Write-Host ""
}

Write-Host "Direct-only / provider-specific routes"
foreach ($direct in @(
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.3-codex",
    "gpt-5.2",
    "gpt-5-codex",
    "gpt-5-codex-mini",
    "aistudio-gemini-3.1-pro-preview",
    "aistudio-gemini-3-pro-preview",
    "aistudio-gemini-3-flash-preview",
    "aistudio-gemini-3.1-flash-lite",
    "aistudio-gemini-2.5-pro",
    "aistudio-gemini-2.5-flash",
    "aistudio-gemini-2.5-flash-lite",
    "vscode-auto",
    "vscode-gpt-5.2",
    "vscode-gpt-5.2-codex",
    "vscode-gpt-5.4-mini",
    "vscode-gpt-5-mini",
    "vscode-gpt-4.1",
    "vscode-gpt-4o",
    "vscode-gemini-3.1-pro-preview",
    "vscode-gemini-3-flash-preview",
    "vscode-gemini-2.5-pro",
    "vscode-gpt-4o-mini",
    "vscode-claude-haiku",
    "gemini-3.1-pro-preview",
    "gemini-3-flash-preview",
    "antigravity-opus",
    "deepseek-v4-pro",
    "deepseek-v4-flash"
)) {
    if ($models.ContainsKey($direct)) {
        Write-Host ("  {0}" -f (Format-Deployment -Name $direct -Model $models[$direct]))
    }
}
