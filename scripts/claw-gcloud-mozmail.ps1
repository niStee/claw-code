#Requires -Version 5.1
<#
.SYNOPSIS
    Run gcloud with a repo-local mozmail Cloud SDK profile.
.DESCRIPTION
    Pins CLOUDSDK_CONFIG to E:\claw-code\profiles\gcloud-mozmail so Google Cloud
    config, credentials, logs, and ADC state do not mix with the user's global
    gcloud profile.
.EXAMPLE
    scripts\claw-gcloud-mozmail.ps1 config configurations list
.EXAMPLE
    scripts\claw-gcloud-mozmail.ps1 auth application-default login
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GcloudArgs
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ProfileRoot = Join-Path $RepoRoot "profiles\gcloud-mozmail"

New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null

$env:CLOUDSDK_CONFIG = $ProfileRoot

$gcloud = Get-Command gcloud -ErrorAction SilentlyContinue
if (-not $gcloud) {
    throw "gcloud was not found on PATH. Install Google Cloud CLI or open a shell where gcloud is available."
}

if (-not $GcloudArgs -or $GcloudArgs.Count -eq 0) {
    Write-Host "CLOUDSDK_CONFIG=$ProfileRoot"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  scripts\claw-gcloud-mozmail.ps1 init"
    Write-Host "  scripts\claw-gcloud-mozmail.ps1 auth application-default login"
    Write-Host "  scripts\claw-gcloud-mozmail.ps1 config set project PROJECT_ID"
    exit 0
}

& $gcloud.Source @GcloudArgs
exit $LASTEXITCODE
