#Requires -Version 5.1
<#
.SYNOPSIS
    Show local Claw account/profile isolation status without printing secrets.
.DESCRIPTION
    Checks the local-only account boundaries used by the unified Claw routing
    setup: Gemini CLI profiles, gcloud/ADC state, DPAPI key files, LiteLLM
    fallback ordering, ignored local state, and local proxy ports.
#>

    [string]$ExpectedGeminiAccount = "work-account@example.com",
    [string]$PersonalAccount = "personal-account@example.com",
    [int]$CodexPort = 8089,
    [int]$VsCodeLmPort = 4000,
    [int]$AntigravityPort = 4999,
    [string]$StackTaskName = "ClawCodeLocalStack"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ExpectedIssues = [System.Collections.Generic.List[string]]::new()

$localEnvPath = Join-Path $PSScriptRoot ".env.ps1"
if (Test-Path $localEnvPath) {
    . $localEnvPath
}

Write-Host "Expected Gemini CLI Account: $ExpectedGeminiAccount" -ForegroundColor Cyan
Write-Host "Forbidden Personal Account:  $PersonalAccount" -ForegroundColor Cyan
Write-Host "--------------------------------"
$Warnings = New-Object System.Collections.Generic.List[string]

function Write-Section {
    param([string]$Name)
    Write-Host ""
    Write-Host $Name
    Write-Host ("-" * $Name.Length)
}

function Get-JsonOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        $Warnings.Add("Could not parse JSON: $Path")
        return $null
    }
}

function Get-GeminiActiveAccount {
    param([string]$Path)
    $json = Get-JsonOrNull -Path $Path
    if ($null -eq $json) {
        return $null
    }
    if ($json.PSObject.Properties.Name -contains "active") {
        return [string]$json.active
    }
    if ($json.PSObject.Properties.Name -contains "activeAccount") {
        return [string]$json.activeAccount
    }
    return $null
}

function Get-IniCore {
    param([string]$Path)
    $result = [ordered]@{ Account = $null; Project = $null }
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$result
    }
    $inCore = $false
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inCore = ($matches[1] -eq "core")
            continue
        }
        if (-not $inCore) {
            continue
        }
        if ($trimmed -match '^account\s*=\s*(.+)$') {
            $result.Account = $matches[1].Trim()
        }
        if ($trimmed -match '^project\s*=\s*(.+)$') {
            $result.Project = $matches[1].Trim()
        }
    }
    return [pscustomobject]$result
}

function Get-PortListeners {
    param([int]$Port)
    try {
        $rows = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
        foreach ($row in $rows) {
            $process = Get-Process -Id $row.OwningProcess -ErrorAction SilentlyContinue
            [pscustomobject]@{
                LocalAddress = [string]$row.LocalAddress
                Port = $Port
                Pid = $row.OwningProcess
                Process = if ($process) { $process.ProcessName } else { "unknown" }
            }
        }
    } catch {
        $rows = @(netstat -ano | Select-String -Pattern (":$Port\s+.*LISTENING"))
        foreach ($row in $rows) {
            $parts = ($row.Line -split "\s+") | Where-Object { $_ }
            $pidText = $parts[$parts.Count - 1]
            $address = ($parts[1] -replace (":" + [regex]::Escape([string]$Port) + "$"), "")
            [pscustomobject]@{ LocalAddress = $address; Port = $Port; Pid = $pidText; Process = "unknown" }
        }
    }
}

function Format-Exists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return "present"
    }
    return "missing"
}

function Test-GitIgnorePattern {
    param(
        [string[]]$Lines,
        [string]$Pattern
    )
    return ($Lines | Where-Object { $_.Trim() -eq $Pattern }).Count -gt 0
}

function Show-LiteLlmFallbackStatus {
    $configPath = Join-Path $ScriptDir "litellm_unified_config.yaml"
    Write-Host ("Config: {0}" -f $configPath)
    if (-not (Test-Path -LiteralPath $configPath)) {
        $Warnings.Add("Missing LiteLLM unified config.")
        return
    }

    $content = Get-Content -LiteralPath $configPath -Raw
    if ($content -match 'providerFallbacks\s*:\s*\r?\n\s*primary\s*:') {
        $Warnings.Add("providerFallbacks.primary is present; this setup should avoid it.")
    } else {
        Write-Host "providerFallbacks.primary: absent"
    }

    $fallbackLines = @($content -split "`r?`n" | Where-Object { $_ -match '^\s*-\s+"claw-[^"]+"\s*:' })
    if ($fallbackLines.Count -eq 0) {
        $Warnings.Add("No claw-* fallback lines were found.")
        return
    }

    foreach ($line in $fallbackLines) {
        $lane = if ($line -match '"(claw-[^"]+)"') { $matches[1] } else { "unknown" }
        $items = @()
        if ($line -match '\[(.*)\]') {
            $items = $matches[1].Split(",") | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }
        }
        $deepseekPositions = @()
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ($items[$i] -like "deepseek-*") {
                $deepseekPositions += $i
            }
        }
        if ($line -match 'antigravity') {
            $Warnings.Add("Antigravity appears in fallback lane $lane; it should remain direct-only.")
        }
        if ($deepseekPositions.Count -gt 0 -and $deepseekPositions[-1] -ne ($items.Count - 1)) {
            $Warnings.Add("DeepSeek is not last in fallback lane $lane.")
        }
        $suffix = if ($items.Count -gt 0) { $items -join " -> " } else { "no parsed fallbacks" }
        Write-Host ("{0}: {1}" -f $lane, $suffix)
    }
}

function Show-ProxyHardeningStatus {
    $codexBat = Join-Path $ScriptDir "claw-codex-proxy.bat"
    $codexRunner = Join-Path $ScriptDir "codex-proxy-runner.mjs"
    $codexDefault = Join-Path $ScriptDir "codex-proxy\config\default.yaml"
    $codexLocal = Join-Path $ScriptDir "codex-proxy\data\local.yaml"

    if (Test-Path -LiteralPath $codexBat) {
        $batText = Get-Content -LiteralPath $codexBat -Raw
        if ($batText -match 'codex-proxy-runner\.mjs') {
            Write-Host "Codex standalone starter: localhost runner"
        } else {
            $Warnings.Add("Codex standalone starter does not use codex-proxy-runner.mjs; verify it binds loopback only.")
        }
    }
    if (Test-Path -LiteralPath $codexRunner) {
        $runnerText = Get-Content -LiteralPath $codexRunner -Raw
        if ($runnerText -match 'host:\s*"127\.0\.0\.1"') {
            Write-Host "Codex runner bind: 127.0.0.1"
        } else {
            $Warnings.Add("Codex runner does not explicitly bind 127.0.0.1.")
        }
    }
    if (Test-Path -LiteralPath $codexDefault) {
        $defaultText = Get-Content -LiteralPath $codexDefault -Raw
        if ($defaultText -match 'server:\s*\r?\n(?:\s+.*\r?\n)*?\s+host:\s*"?([^"`r`n]+)"?') {
            Write-Host ("Codex upstream default host: {0} (ignored by wrapper)" -f $matches[1].Trim('"'))
        }
    }
    if (Test-Path -LiteralPath $codexLocal) {
        $localText = Get-Content -LiteralPath $codexLocal -Raw
        if ($localText -match 'proxy_api_key\s*:\s*(.+)') {
            $keyLabel = if ([string]::IsNullOrWhiteSpace($matches[1]) -or $matches[1].Trim() -eq "null") { "unset" } else { "set" }
            Write-Host ("Codex proxy_api_key: {0}" -f $keyLabel)
        } else {
            $Warnings.Add("Codex local.yaml does not set proxy_api_key.")
        }
    }

    $routeTap = Join-Path $ScriptDir "claw-route-tap.mjs"
    if (Test-Path -LiteralPath $routeTap) {
        $tapText = Get-Content -LiteralPath $routeTap -Raw
        if ($tapText -match 'server\.listen\(listenPort,\s*"127\.0\.0\.1"') {
            Write-Host "Route tap bind: 127.0.0.1"
        } else {
            $Warnings.Add("Route tap does not explicitly bind 127.0.0.1.")
        }
    }

    $vscodeExtensionRoot = Join-Path $env:USERPROFILE ".vscode\extensions"
    if (Test-Path -LiteralPath $vscodeExtensionRoot) {
        $lmProxy = Get-ChildItem -LiteralPath $vscodeExtensionRoot -Directory -Filter "ryonakae.vscode-lm-proxy-*" |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($lmProxy) {
            $manager = Join-Path $lmProxy.FullName "out\server\manager.js"
            if (Test-Path -LiteralPath $manager) {
                $managerText = Get-Content -LiteralPath $manager -Raw
                if ($managerText -match 'app\.listen\(port,\s*"127\.0\.0\.1"') {
                    Write-Host ("VS Code LM proxy patch: {0} binds 127.0.0.1" -f $lmProxy.Name)
                } elseif ($managerText -match 'app\.listen\(port,\s*\(\)') {
                    $Warnings.Add("VS Code LM Proxy extension $($lmProxy.Name) binds all interfaces. Run scripts\claw-vscode-lm-localhost.ps1.")
                } else {
                    $Warnings.Add("VS Code LM Proxy extension $($lmProxy.Name) has an unknown listen shape. Review $manager.")
                }
            }
        }
    }
}

function Show-AutostartStatus {
    param([string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    } catch {
        Write-Host ("{0}: not installed" -f $TaskName)
        return
    }

    Write-Host ("{0}: installed; state={1}" -f $TaskName, $task.State)
    foreach ($action in @($task.Actions)) {
        $execute = if ($action.Execute) { $action.Execute } else { "unknown" }
        $arguments = if ($action.Arguments) { $action.Arguments } else { "" }
        Write-Host ("action: {0} {1}" -f $execute, $arguments)

        if ($arguments -notmatch [regex]::Escape($RepoRoot)) {
            $Warnings.Add("Autostart task $TaskName does not appear to start this repo.")
        }
        if ($arguments -notmatch 'claw-stack\.ps1') {
            $Warnings.Add("Autostart task $TaskName does not appear to use scripts\claw-stack.ps1.")
        }
    }
}

Write-Host "Claw local security status"
Write-Host ("Repo: {0}" -f $RepoRoot)
Write-Host ("Expected Gemini account: {0}" -f $ExpectedGeminiAccount)

Write-Section "Gemini CLI Profiles"
$globalGeminiDir = Join-Path $env:USERPROFILE ".gemini"
$globalAccounts = Join-Path $globalGeminiDir "google_accounts.json"
$repoProfileRoot = Join-Path $RepoRoot "profiles\gemini-mozmail"
$repoGeminiDir = Join-Path $repoProfileRoot ".gemini"
$repoAccounts = Join-Path $repoGeminiDir "google_accounts.json"
$globalActive = Get-GeminiActiveAccount -Path $globalAccounts
$repoActive = Get-GeminiActiveAccount -Path $repoAccounts

Write-Host ("Global ~/.gemini: {0}" -f (Format-Exists $globalGeminiDir))
Write-Host ("Global active account: {0}" -f ($(if ($globalActive) { $globalActive } else { "none" })))
Write-Host ("Repo GEMINI_CLI_HOME: {0}" -f $repoProfileRoot)
Write-Host ("Repo active account: {0}" -f ($(if ($repoActive) { $repoActive } else { "none" })))
Write-Host ("Repo file credentials: oauth={0}, gemini-credentials={1}" -f (Format-Exists (Join-Path $repoGeminiDir "oauth_creds.json")), (Format-Exists (Join-Path $repoGeminiDir "gemini-credentials.json")))

if ($globalActive -and $globalActive -ne $ExpectedGeminiAccount) {
    $ExpectedIssues.Add("Global Gemini profile is $globalActive. Use scripts\gemini-cli-mozmail.ps1 for this repo so global state stays out of the route.")
}
if (-not $repoActive) {
    $ExpectedIssues.Add("Repo-local mozmail Gemini CLI profile is not logged in yet.")
} elseif ($repoActive -ne $ExpectedGeminiAccount) {
    $Warnings.Add("Repo-local Gemini profile is $repoActive, expected $ExpectedGeminiAccount.")
}

Write-Section "Google Cloud / ADC"
$cloudSdkConfig = if ([string]::IsNullOrWhiteSpace($env:CLOUDSDK_CONFIG)) { Join-Path $env:APPDATA "gcloud" } else { $env:CLOUDSDK_CONFIG }
$activeConfigName = if ([string]::IsNullOrWhiteSpace($env:CLOUDSDK_ACTIVE_CONFIG_NAME)) { "global active" } else { $env:CLOUDSDK_ACTIVE_CONFIG_NAME }
$adcPath = Join-Path $cloudSdkConfig "application_default_credentials.json"
Write-Host ("CLOUDSDK_CONFIG: {0}" -f $cloudSdkConfig)
Write-Host ("CLOUDSDK_ACTIVE_CONFIG_NAME: {0}" -f $activeConfigName)
Write-Host ("ADC file: {0}" -f (Format-Exists $adcPath))
Write-Host ("GOOGLE_APPLICATION_CREDENTIALS: {0}" -f ($(if ($env:GOOGLE_APPLICATION_CREDENTIALS) { "set" } else { "unset" })))
Write-Host ("GOOGLE_CLOUD_PROJECT: {0}" -f ($(if ($env:GOOGLE_CLOUD_PROJECT) { $env:GOOGLE_CLOUD_PROJECT } else { "unset" })))

$configDir = Join-Path $cloudSdkConfig "configurations"
if (Test-Path -LiteralPath $configDir) {
    Get-ChildItem -LiteralPath $configDir -Filter "config_*" | ForEach-Object {
        $core = Get-IniCore -Path $_.FullName
        Write-Host ("{0}: account={1}; project={2}" -f $_.Name, ($(if ($core.Account) { $core.Account } else { "unset" })), ($(if ($core.Project) { $core.Project } else { "unset" })))
        if ($core.Account -eq $PersonalAccount) {
            $ExpectedIssues.Add("gcloud config '$($_.Name)' uses $PersonalAccount. Do not rely on global gcloud/ADC for mozmail-only tests.")
        }
    }
} else {
    Write-Host "gcloud configurations: missing"
}

Write-Section "Stored Provider Secrets"
$keyDir = Join-Path $env:APPDATA "claw-code\keys"
foreach ($name in @("gemini.enc", "deepseek.enc", "vertex-project.enc")) {
    Write-Host ("{0}: {1}" -f $name, (Format-Exists (Join-Path $keyDir $name)))
}
Write-Host ("GEMINI_API_KEY env: {0}" -f ($(if ($env:GEMINI_API_KEY) { "set" } else { "unset" })))
Write-Host ("DEEPSEEK_API_KEY env: {0}" -f ($(if ($env:DEEPSEEK_API_KEY) { "set" } else { "unset" })))
Write-Host ("LITELLM_MASTER_KEY env: {0}" -f ($(if ($env:LITELLM_MASTER_KEY) { "set" } else { "unset" })))

Write-Section "LiteLLM Routing"
Show-LiteLlmFallbackStatus

Write-Section "Proxy Hardening"
Show-ProxyHardeningStatus

Write-Section "Stack Autostart"
Show-AutostartStatus -TaskName $StackTaskName

Write-Section "Local Proxy Ports"
foreach ($port in @($LiteLlmPort, $RouteTapPort, $CodexPort, $VsCodeLmPort, $AntigravityPort)) {
    $listeners = @(Get-PortListeners -Port $port | Sort-Object LocalAddress, Port, Pid, Process -Unique)
    if ($listeners.Count -eq 0) {
        Write-Host ("127.0.0.1:{0}: down" -f $port)
    } else {
        foreach ($listener in $listeners) {
            $address = if ($listener.LocalAddress) { $listener.LocalAddress } else { "unknown" }
            Write-Host ("{0}:{1}: listening pid={2} process={3}" -f $address, $port, $listener.Pid, $listener.Process)
            if ($address -notin @("127.0.0.1", "::1", "localhost")) {
                $Warnings.Add("Port $port is listening on $address, not loopback-only.")
            }
        }
    }
}

Write-Section "Ignore Guardrails"
$gitignorePath = Join-Path $RepoRoot ".gitignore"
$requiredIgnores = @("logs/", "downloads/", "tools/", "profiles/", ".gemini/", ".env", ".env.local", "scripts/*.env", "*.enc", ".claw/settings.local.json")
if (Test-Path -LiteralPath $gitignorePath) {
    $lines = Get-Content -LiteralPath $gitignorePath
    foreach ($pattern in $requiredIgnores) {
        $ok = Test-GitIgnorePattern -Lines $lines -Pattern $pattern
        Write-Host ("{0}: {1}" -f $pattern, ($(if ($ok) { "ignored" } else { "missing" })))
        if (-not $ok) {
            $Warnings.Add(".gitignore is missing $pattern")
        }
    }
} else {
    $Warnings.Add("Missing .gitignore.")
}

Write-Section "Summary"
if ($ExpectedIssues.Count -eq 0 -and $Warnings.Count -eq 0) {
    Write-Host "No isolation issues found."
} else {
    foreach ($issue in $ExpectedIssues) {
        Write-Host ("INFO: {0}" -f $issue)
    }
    foreach ($warning in $Warnings) {
        Write-Host ("WARN: {0}" -f $warning)
    }
}
