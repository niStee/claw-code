#Requires -Version 5.1
<#
.SYNOPSIS
    Start, stop, or inspect the local Claw proxy stack.
.DESCRIPTION
    Starts the helper proxies that LiteLLM depends on, then starts the unified
    LiteLLM proxy. This is the recommended entrypoint for Roo Code and Claw.

    The Codex proxy can be launched automatically because it is a local process.
    The VS Code LM proxy is owned by VS Code, so this script checks whether it is
    listening and reports status, but does not launch VS Code for you.
#>

param(
    [ValidateSet("start", "stop", "status")]
    [string]$Action = "start",
    [int]$Port = 8098,
    [int]$TapPort = 8099,
    [int]$CodexPort = 8089,
    [int]$VsCodeLmPort = 4000,
    [switch]$NoCodex,
    [switch]$NoTap
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$LogDir = Join-Path $RepoRoot "logs\claw-stack"

function Ensure-LogDir {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
}

function Test-LocalPort {
    param([int]$TargetPort)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect("127.0.0.1", $TargetPort, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(350)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-PortPids {
    param([int]$TargetPort)
    $rows = netstat -ano | Select-String -Pattern (":$TargetPort\s+.*LISTENING")
    foreach ($row in $rows) {
        $parts = ($row.Line -split "\s+") | Where-Object { $_ }
        if ($parts.Count -gt 0) {
            $pidText = $parts[$parts.Count - 1]
            $processId = 0
            if ([int]::TryParse($pidText, [ref]$processId)) {
                $processId
            }
        }
    }
}

function Get-PortListeners {
    param([int]$TargetPort)
    try {
        Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction Stop |
            Sort-Object LocalAddress, LocalPort, OwningProcess -Unique |
            ForEach-Object {
                $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    LocalAddress = [string]$_.LocalAddress
                    Pid = $_.OwningProcess
                    Process = if ($process) { $process.ProcessName } else { "unknown" }
                }
            }
    } catch {
        $rows = netstat -ano | Select-String -Pattern (":$TargetPort\s+.*LISTENING")
        foreach ($row in $rows) {
            $parts = ($row.Line -split "\s+") | Where-Object { $_ }
            $pidText = $parts[$parts.Count - 1]
            $address = ($parts[1] -replace (":" + [regex]::Escape([string]$TargetPort) + "$"), "")
            [pscustomobject]@{ LocalAddress = $address; Pid = $pidText; Process = "unknown" }
        }
    }
}

function Test-LoopbackAddress {
    param([string]$Address)
    return $Address -in @("127.0.0.1", "::1", "localhost")
}

function Format-KeyLabel {
    param([string]$ApiKey)
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        return "missing"
    }
    if ($ApiKey -in @("sk-claw-unified-proxy-key", "sk-litellm-vertex-proxy-key", "copilot", "pwd")) {
        return $ApiKey
    }
    return "set (hidden)"
}

function Wait-LocalPort {
    param(
        [int]$TargetPort,
        [string]$Name,
        [int]$TimeoutSeconds = 25
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-LocalPort $TargetPort) {
            Write-Host "[claw-stack] $Name is listening on 127.0.0.1:$TargetPort"
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "[claw-stack] WARN: $Name did not become ready on 127.0.0.1:$TargetPort within ${TimeoutSeconds}s"
    return $false
}

function Start-HiddenCommand {
    param(
        [string]$Name,
        [string]$CommandLine,
        [string]$WorkingDirectory = $ScriptDir
    )
    Ensure-LogDir
    $stdout = Join-Path $LogDir "$Name.out.log"
    $stderr = Join-Path $LogDir "$Name.err.log"
    $process = Start-Process `
        -FilePath $env:ComSpec `
        -ArgumentList @("/c", $CommandLine) `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    Write-Host "[claw-stack] Started $Name as PID $($process.Id)"
    Write-Host "[claw-stack]   logs: $stdout"
    Write-Host "[claw-stack]         $stderr"
}

function Start-HiddenProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory = $ScriptDir
    )
    Ensure-LogDir
    $stdout = Join-Path $LogDir "$Name.out.log"
    $stderr = Join-Path $LogDir "$Name.err.log"
    $process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    Write-Host "[claw-stack] Started $Name as PID $($process.Id)"
    Write-Host "[claw-stack]   logs: $stdout"
    Write-Host "[claw-stack]         $stderr"
}

function Resolve-Node {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        return $node.Source
    }
    $codexNode = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\node.exe"
    if (Test-Path $codexNode) {
        return $codexNode
    }
    return $null
}

function Stop-Port {
    param(
        [int]$TargetPort,
        [string]$Name
    )
    $pids = @(Get-PortPids $TargetPort | Sort-Object -Unique)
    if ($pids.Count -eq 0) {
        Write-Host "[claw-stack] $Name is not listening on 127.0.0.1:$TargetPort"
        return
    }
    foreach ($processId in $pids) {
        Write-Host "[claw-stack] Stopping $Name PID $processId on port $TargetPort"
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
}

function Show-Port {
    param(
        [string]$Name,
        [int]$TargetPort,
        [string]$Note
    )
    if (Test-LocalPort $TargetPort) {
        $listeners = @(Get-PortListeners $TargetPort)
        if ($listeners.Count -eq 0) {
            $pids = @(Get-PortPids $TargetPort | Sort-Object -Unique)
            $pidLabel = if ($pids.Count -gt 0) { $pids -join ", " } else { "unknown" }
            Write-Host ("  {0,-14} up    127.0.0.1:{1}  PID {2}" -f $Name, $TargetPort, $pidLabel)
            return
        }
        foreach ($listener in $listeners) {
            $exposure = if (Test-LoopbackAddress $listener.LocalAddress) { "loopback" } else { "EXPOSED" }
            Write-Host ("  {0,-14} up    {1}:{2}  PID {3}  {4}" -f $Name, $listener.LocalAddress, $TargetPort, $listener.Pid, $exposure)
        }
    } else {
        Write-Host ("  {0,-14} down  127.0.0.1:{1}  {2}" -f $Name, $TargetPort, $Note)
    }
}

function Start-CodexProxy {
    if ($NoCodex) {
        Write-Host "[claw-stack] Skipping Codex proxy because -NoCodex was supplied."
        return
    }
    if (Test-LocalPort $CodexPort) {
        Write-Host "[claw-stack] Codex proxy already listening on 127.0.0.1:$CodexPort"
        return
    }
    $codexScript = Join-Path $ScriptDir "claw-codex-proxy.bat"
    $codexDir = Join-Path $ScriptDir "codex-proxy"
    $codexPackage = Join-Path $ScriptDir "codex-proxy\package.json"
    $tsxCli = Join-Path $ScriptDir "codex-proxy\node_modules\tsx\dist\cli.mjs"
    $runner = Join-Path $ScriptDir "codex-proxy-runner.mjs"
    if (-not (Test-Path $codexScript) -or -not (Test-Path $codexPackage)) {
        Write-Host "[claw-stack] WARN: codex-proxy is not installed under scripts\codex-proxy; Codex routes will fall back."
        return
    }
    $node = Resolve-Node
    if ($node -and (Test-Path $tsxCli)) {
        $previousPort = $env:PORT
        $env:PORT = [string]$CodexPort
        try {
            Start-HiddenProcess `
                -Name "codex-proxy" `
                -FilePath $node `
                -ArgumentList @($tsxCli, $runner) `
                -WorkingDirectory $codexDir
        } finally {
            if ($null -eq $previousPort) {
                Remove-Item Env:\PORT -ErrorAction SilentlyContinue
            } else {
                $env:PORT = $previousPort
            }
        }
    } else {
        Start-HiddenCommand -Name "codex-proxy" -CommandLine "`"$codexScript`" $CodexPort"
    }
    Wait-LocalPort -TargetPort $CodexPort -Name "Codex proxy" -TimeoutSeconds 35 | Out-Null
}

function Start-UnifiedProxy {
    if (Test-LocalPort $Port) {
        Write-Host "[claw-stack] Unified LiteLLM already listening on 127.0.0.1:$Port"
        return
    }
    $unifiedScript = Join-Path $ScriptDir "claw-unified-proxy.bat"
    Start-HiddenCommand -Name "litellm-unified" -CommandLine "`"$unifiedScript`" $Port"
    Wait-LocalPort -TargetPort $Port -Name "Unified LiteLLM" -TimeoutSeconds 35 | Out-Null
}

function Start-RouteTap {
    if ($NoTap) {
        Write-Host "[claw-stack] Skipping route tap because -NoTap was supplied."
        return
    }
    if (Test-LocalPort $TapPort) {
        Write-Host "[claw-stack] Route tap already listening on 127.0.0.1:$TapPort"
        return
    }
    $tapScript = Join-Path $ScriptDir "claw-route-tap.mjs"
    if (-not (Test-Path $tapScript)) {
        Write-Host "[claw-stack] WARN: route tap script not found at $tapScript"
        return
    }
    $node = Resolve-Node
    if (-not $node) {
        Write-Host "[claw-stack] WARN: node.exe was not found; route trace tap will not start."
        return
    }
    Start-HiddenProcess `
        -Name "route-tap" `
        -FilePath $node `
        -ArgumentList @($tapScript, [string]$TapPort, "http://127.0.0.1:$Port") `
        -WorkingDirectory $ScriptDir
    Wait-LocalPort -TargetPort $TapPort -Name "Route tap" -TimeoutSeconds 15 | Out-Null
}

function Set-CurrentShellRoute {
    if ([string]::IsNullOrWhiteSpace($env:LITELLM_MASTER_KEY)) {
        $env:LITELLM_MASTER_KEY = "sk-claw-unified-proxy-key"
    }
    $routePort = if ($NoTap) { $Port } else { $TapPort }
    $env:OPENAI_BASE_URL = "http://127.0.0.1:$routePort/v1"
    $env:OPENAI_API_KEY = $env:LITELLM_MASTER_KEY
}

function Show-Status {
    Write-Host "Claw stack status"
    Show-Port -Name "LiteLLM" -TargetPort $Port -Note "run scripts\claw-stack.ps1 start"
    Show-Port -Name "Route Tap" -TargetPort $TapPort -Note "optional trace proxy"
    Show-Port -Name "Codex" -TargetPort $CodexPort -Note "auto-started by stack when installed"
    Show-Port -Name "VS Code LM" -TargetPort $VsCodeLmPort -Note "managed by VS Code extension"
    Write-Host ""
    Write-Host "Roo Code models: claw-sonnet, claw-opus, claw-haiku, claw-pro"
    Write-Host "Roo Code base:   http://127.0.0.1:$TapPort/v1  (route trace)"
    Write-Host "LiteLLM direct:  http://127.0.0.1:$Port/v1"
    Write-Host "Last routes:     scripts\claw-route-last.ps1"
    Show-CredentialHealth
}

function Show-CredentialHealth {
    $credScript = Join-Path $ScriptDir "claw-cred.ps1"
    if (-not (Test-Path $credScript)) {
        return
    }

    Write-Host ""
    Write-Host "Credential health"
    Write-Host "  Codex:   browser/OAuth state via codex-proxy"
    Write-Host "  Copilot: VS Code LM session"

    foreach ($provider in @("gemini", "deepseek", "vertex-project")) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $credScript -Action Test -Provider $provider *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("  {0,-14} ok" -f $provider)
        } else {
            Write-Host ("  {0,-14} needs repair: scripts\claw-repair-credentials.ps1 -Providers {0}" -f $provider)
        }
    }
}

function Start-Stack {
    Write-Host "[claw-stack] Starting local Claw stack..."
    Set-CurrentShellRoute
    Start-CodexProxy
    if (-not (Test-LocalPort $VsCodeLmPort)) {
        Write-Host "[claw-stack] WARN: VS Code LM proxy is not listening on 127.0.0.1:$VsCodeLmPort."
        Write-Host "[claw-stack]       Start VS Code with its LM proxy extension if you want Copilot fallbacks."
    } else {
        $exposed = @(Get-PortListeners $VsCodeLmPort | Where-Object { -not (Test-LoopbackAddress $_.LocalAddress) })
        if ($exposed.Count -gt 0) {
            Write-Host "[claw-stack] WARN: VS Code LM proxy is listening beyond loopback."
            Write-Host "[claw-stack]       Run scripts\claw-vscode-lm-localhost.ps1 and restart VS Code."
        }
    }
    Start-UnifiedProxy
    Start-RouteTap
    Write-Host ""
    Write-Host "[claw-stack] Current shell route:"
    Write-Host "  OPENAI_BASE_URL=$env:OPENAI_BASE_URL"
    Write-Host "  OPENAI_API_KEY=$(Format-KeyLabel $env:OPENAI_API_KEY)"
    Write-Host ""
    Show-Status
}

function Stop-Stack {
    if (-not $NoTap) {
        Stop-Port -TargetPort $TapPort -Name "Route tap"
    }
    Stop-Port -TargetPort $Port -Name "Unified LiteLLM"
    if (-not $NoCodex) {
        Stop-Port -TargetPort $CodexPort -Name "Codex proxy"
    }
}

switch ($Action) {
    "start" { Start-Stack }
    "stop" { Stop-Stack }
    "status" { Show-Status }
}
