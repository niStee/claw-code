#Requires -Version 5.1
<#
.SYNOPSIS
    Show recent actual backend routes captured by claw-route-tap.mjs.
.DESCRIPTION
    Reads logs/claw-routes.ndjson. These entries are created from LiteLLM
    response headers, so this does not make extra model calls or burn tokens.
#>

param(
    [int]$Count = 10,
    [switch]$All,
    [switch]$Raw
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$LogPath = Join-Path $RepoRoot "logs\claw-routes.ndjson"

if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Host "No route trace log yet: $LogPath"
    Write-Host "Use Roo Code with base URL http://127.0.0.1:8099/v1, or start scripts\claw-stack.ps1 start."
    exit 0
}

$tailCount = [Math]::Max($Count * 10, 50)
$lines = @(Get-Content -LiteralPath $LogPath -Tail $tailCount)
if ($Raw) {
    $lines | Select-Object -Last $Count
    exit 0
}

$rows = foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }
    try {
        $line | ConvertFrom-Json
    } catch {
        Write-Host $line
        continue
    }
}

if (-not $All) {
    $rows = @($rows | Where-Object { $_.path -eq "/v1/chat/completions" })
}

$rows = @($rows | Select-Object -Last $Count)
if ($rows.Count -eq 0) {
    Write-Host "No recent chat completion routes found."
    Write-Host "Use -All to include metadata calls such as /v1/models."
    exit 0
}

foreach ($row in $rows) {
    $requestLabel = if ($row.requested_model) { $row.requested_model } else { $row.path }

    $selected = if ($row.response_model) { $row.response_model } elseif ($row.selected_model_id) { $row.selected_model_id } elseif ($row.model_group) { $row.model_group } else { "unknown" }
    $fallbacks = if ($row.fallbacks_attempted -ne $null -and "$($row.fallbacks_attempted)" -ne "") { $row.fallbacks_attempted } else { "?" }
    $duration = if ($row.response_duration_ms) { $row.response_duration_ms } else { $row.proxy_duration_ms }

    Write-Host ("{0}  {1}  {2} -> {3}" -f $row.ts, $row.status, $requestLabel, $selected)
    Write-Host ("  provider: {0}; fallbacks: {1}; duration_ms: {2}" -f $row.provider, $fallbacks, $duration)
    if ($row.response_model -and $row.selected_model_id -and $row.response_model -ne $row.selected_model_id) {
        Write-Host ("  deployment: {0}" -f $row.selected_model_id)
    }
    if ($row.call_id) {
        Write-Host ("  call_id:  {0}" -f $row.call_id)
    }
}
