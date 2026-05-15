#Requires -Version 5.1
<#
.SYNOPSIS
    Summarize Roo Code traffic through the Claw route tap.
.DESCRIPTION
    Reads logs/claw-routes.ndjson and prints request counts, selected backends,
    failure bursts, and long idle gaps. This is a local log inspection only; it
    does not call LiteLLM or any model endpoint.
.PARAMETER LogPath
    Path to logs/claw-routes.ndjson.
.PARAMETER IdleGapSeconds
    Minimum gap between chat completion requests to report as idle time.
.PARAMETER Recent
    Number of recent chat completion requests to print.
#>

param(
    [string]$LogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "logs\claw-routes.ndjson"),
    [int]$IdleGapSeconds = 300,
    [int]$Recent = 12
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Host "No route log found: $LogPath"
    Write-Host "Use Roo Code through http://127.0.0.1:8099/v1 to capture selected backends."
    exit 0
}

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$dateStyles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
$rows = @()
foreach ($line in Get-Content -LiteralPath $LogPath) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    try {
        $row = $line | ConvertFrom-Json
    } catch {
        continue
    }

    if (-not $row.ts) {
        continue
    }

    $timestamp = [string]$row.ts
    $parsedTimestamp = [datetime]::Parse($timestamp, $culture, $dateStyles).ToUniversalTime()
    $row | Add-Member -NotePropertyName ts_dt -NotePropertyValue $parsedTimestamp -Force
    $rows += $row
}

if ($rows.Count -eq 0) {
    Write-Host "No parseable route rows found in $LogPath"
    exit 0
}

$rows = @($rows | Sort-Object ts_dt)
$chatRows = @($rows | Where-Object { $_.method -eq "POST" -and $_.path -eq "/v1/chat/completions" })
$modelListRows = @($rows | Where-Object { $_.method -eq "GET" -and $_.path -eq "/v1/models" })

function Get-SelectedName {
    param([object]$Row)
    if ($Row.response_model) { return [string]$Row.response_model }
    if ($Row.selected_model_id) { return [string]$Row.selected_model_id }
    if ($Row.model_group) { return [string]$Row.model_group }
    return "unknown"
}

function Get-ProviderName {
    param([object]$Row)
    if ($Row.provider) { return [string]$Row.provider }
    return "unknown"
}

$first = $rows[0].ts_dt
$last = $rows[-1].ts_dt

Write-Host "Roo / Claw Route Usage Report"
Write-Host ("Log:   {0}" -f $LogPath)
Write-Host ("Range: {0:u} -> {1:u}" -f $first, $last)
Write-Host ("Rows:  {0} total; {1} chat completions; {2} model-list calls" -f $rows.Count, $chatRows.Count, $modelListRows.Count)
Write-Host ""

if ($chatRows.Count -gt 0) {
    Write-Host "Status counts"
    $chatRows |
        Group-Object status |
        Sort-Object Count -Descending |
        ForEach-Object { Write-Host ("  {0,-5} {1}" -f $_.Name, $_.Count) }
    Write-Host ""

    Write-Host "Selected backends"
    $chatRows |
        Group-Object { "{0}|{1}|{2}" -f (Get-SelectedName $_), $_.status, (Get-ProviderName $_) } |
        Sort-Object Count -Descending |
        ForEach-Object {
            $parts = $_.Name -split "\|", 3
            Write-Host ("  {0,4}x  status={1,-4}  {2}  [{3}]" -f $_.Count, $parts[1], $parts[0], $parts[2])
        }
    Write-Host ""

    $costRows = @($chatRows | Where-Object {
        $_.response_cost -ne $null -and "$($_.response_cost)" -ne "" -and "$($_.response_cost)" -ne "0.0"
    })
    if ($costRows.Count -gt 0) {
        Write-Host "Reported LiteLLM cost"
        $totalCost = 0.0
        foreach ($row in $costRows) {
            $parsed = 0.0
            if ([double]::TryParse([string]$row.response_cost, [System.Globalization.NumberStyles]::Float, $culture, [ref]$parsed)) {
                $totalCost += $parsed
            }
        }
        Write-Host ("  total reported: {0}" -f $totalCost.ToString("0.########", $culture))
        $costRows |
            Group-Object { Get-ProviderName $_ } |
            Sort-Object Count -Descending |
            ForEach-Object {
                $providerCost = 0.0
                foreach ($row in $_.Group) {
                    $parsed = 0.0
                    if ([double]::TryParse([string]$row.response_cost, [System.Globalization.NumberStyles]::Float, $culture, [ref]$parsed)) {
                        $providerCost += $parsed
                    }
                }
                Write-Host ("  {0,-34} {1}" -f $_.Name, $providerCost.ToString("0.########", $culture))
            }
        Write-Host ""
    }

    Write-Host "Per-minute failure bursts"
    $failRows = @($chatRows | Where-Object { [int]$_.status -ge 400 })
    if ($failRows.Count -eq 0) {
        Write-Host "  none"
    } else {
        $failRows |
            Group-Object { $_.ts_dt.ToString("yyyy-MM-dd HH:mm'Z'") } |
            Sort-Object Name |
            ForEach-Object { Write-Host ("  {0}  failures={1}" -f $_.Name, $_.Count) }
    }
    Write-Host ""

    Write-Host "Provider failure counts"
    if ($failRows.Count -eq 0) {
        Write-Host "  none"
    } else {
        $failRows |
            Group-Object { "{0}|{1}" -f (Get-ProviderName $_), (Get-SelectedName $_) } |
            Sort-Object Count -Descending |
            ForEach-Object {
                $parts = $_.Name -split "\|", 2
                Write-Host ("  {0,4}x  {1}  via {2}" -f $_.Count, $parts[1], $parts[0])
            }
    }
    Write-Host ""

    Write-Host ("Idle gaps longer than {0}s between chat completions" -f $IdleGapSeconds)
    $previous = $null
    $gapCount = 0
    foreach ($row in $chatRows) {
        if ($previous -ne $null) {
            $gap = ($row.ts_dt - $previous.ts_dt).TotalSeconds
            if ($gap -ge $IdleGapSeconds) {
                $gapCount += 1
                Write-Host ("  {0:u} -> {1:u}  {2}s" -f $previous.ts_dt, $row.ts_dt, $gap.ToString("0.0", $culture))
            }
        }
        $previous = $row
    }
    if ($gapCount -eq 0) {
        Write-Host "  none"
    }
    Write-Host ""

    Write-Host ("Recent chat completions (last {0})" -f $Recent)
    $chatRows |
        Select-Object -Last $Recent |
        ForEach-Object {
            $deployment = if ($_.response_model -and $_.selected_model_id -and $_.response_model -ne $_.selected_model_id) { " deployment=$($_.selected_model_id)" } else { "" }
            Write-Host ("  {0:u}  {1}  {2} -> {3} [{4}]{5}" -f $_.ts_dt, $_.status, $_.requested_model, (Get-SelectedName $_), (Get-ProviderName $_), $deployment)
        }
} else {
    Write-Host "No chat completions found. Idle Roo Code does not appear to be calling models through this route tap."
}

if ($modelListRows.Count -gt 0) {
    Write-Host ""
    Write-Host "Model-list calls"
    $modelListRows |
        Select-Object -Last 10 |
        ForEach-Object { Write-Host ("  {0:u}  {1}" -f $_.ts_dt, $_.status) }
}

if ($chatRows.Count -gt 0) {
    $rateLimitRows = @($chatRows | Where-Object { [int]$_.status -eq 429 })
    if ($rateLimitRows.Count -gt 0) {
        Write-Host ""
        Write-Host "Hints"
        $rateLimitRows |
            Group-Object { Get-ProviderName $_ } |
            Sort-Object Count -Descending |
            ForEach-Object {
                if ($_.Count -ge 3) {
                    Write-Host ("  {0}: {1} rate-limit failures. Prefer switching provider buckets or using provider auto-routing before retrying." -f $_.Name, $_.Count)
                }
            }
    }
}
