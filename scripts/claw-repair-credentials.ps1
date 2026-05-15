#Requires -Version 5.1
<#
.SYNOPSIS
    Re-store broken local Claw provider credentials with secure prompts.
.DESCRIPTION
    DPAPI-encrypted credentials are bound to the current Windows user context.
    This helper checks the common provider secrets and prompts only for values
    that are missing or cannot decrypt. It never prints secret values.
.EXAMPLE
    scripts\claw-repair-credentials.ps1
.EXAMPLE
    scripts\claw-repair-credentials.ps1 -Providers gemini,deepseek
#>

param(
    [string[]]$Providers = @("gemini", "deepseek", "vertex-project")
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CredScript = Join-Path $ScriptDir "claw-cred.ps1"

if (-not (Test-Path $CredScript)) {
    throw "Missing credential helper: $CredScript"
}

function Test-ClawCredential {
    param([string]$Provider)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $CredScript -Action Test -Provider $Provider | Out-String
    return $LASTEXITCODE -eq 0
}

foreach ($provider in $Providers) {
    Write-Host ""
    Write-Host "[claw-cred] Checking $provider"
    $ok = Test-ClawCredential -Provider $provider
    if ($ok) {
        Write-Host "[claw-cred] $provider is decryptable"
        continue
    }

    $answer = Read-Host "Re-store '$provider' now? [Y/n]"
    if ($answer -match '^(n|no)$') {
        Write-Host "[claw-cred] Skipped $provider"
        continue
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $CredScript -Action Set -Provider $provider
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to store $provider"
        exit $LASTEXITCODE
    }

    if (Test-ClawCredential -Provider $provider) {
        Write-Host "[claw-cred] $provider repaired"
    } else {
        Write-Error "$provider is still not decryptable after storing"
        exit 2
    }
}

Write-Host ""
Write-Host "[claw-cred] Credential repair complete"
