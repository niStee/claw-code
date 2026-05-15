#Requires -Version 3.0
<#
.SYNOPSIS
    Manage claw-code API keys encrypted via Windows DPAPI.
.DESCRIPTION
    Stores provider API keys in %APPDATA%\claw-code\keys\ as DPAPI-encrypted
    files. DPAPI ties encryption to the current Windows user account; keys
    cannot be decrypted by other users or on other machines.
.PARAMETER Action
    Set, Get, List, or Remove. Defaults to List.
.PARAMETER Provider
    Provider name (deepseek, gemini, anthropic, vertex-project, etc.)
.PARAMETER Key
    The API key to store with -Action Set. If omitted, the script prompts
    securely so the key is not written to shell history.
.EXAMPLE
    claw-cred.ps1 -Action Set -Provider deepseek
.EXAMPLE
    claw-cred.ps1 -Action Test
.EXAMPLE
    claw-cred.ps1 -Action Get -Provider deepseek
.EXAMPLE
    claw-cred.ps1 -Action List
.EXAMPLE
    claw-cred.ps1 -Action Remove -Provider deepseek
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Set","Get","List","Test","Remove")]
    [string]$Action = "List",

    [Parameter(Mandatory=$false)]
    [string]$Provider,

    [Parameter(Mandatory=$false)]
    [string]$Key
)

$ErrorActionPreference = "Stop"
$KeysDir = Join-Path $env:APPDATA "claw-code\keys"

function EnsureKeysDir {
    if (-not (Test-Path $KeysDir)) {
        New-Item -ItemType Directory -Path $KeysDir -Force | Out-Null
    }
}

function Store-Key {
    param([string]$Provider, [string]$ApiKey)
    if (-not $Provider) {
        Write-Error "Usage: claw-cred.ps1 -Action Set -Provider <name>"
        exit 1
    }
    EnsureKeysDir
    $path = Join-Path $KeysDir "$Provider.enc"
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $secure = Read-Host -Prompt "Enter secret for '$Provider'" -AsSecureString
    } else {
        Write-Warning "Passing -Key writes the secret into shell history. Prefer: claw-cred.ps1 -Action Set -Provider $Provider"
        $secure = ConvertTo-SecureString -String $ApiKey -AsPlainText -Force
    }
    $encrypted = ConvertFrom-SecureString -SecureString $secure
    # Write without trailing newline; trailing whitespace breaks ConvertTo-SecureString on read
    [System.IO.File]::WriteAllText($path, $encrypted, [System.Text.Encoding]::UTF8)
    Write-Host "Stored API key for '$Provider' (DPAPI-encrypted at $path)"
}

function Read-KeySecureString {
    param([string]$Provider)
    $path = Join-Path $KeysDir "$Provider.enc"
    if (-not (Test-Path $path)) {
        Write-Error "No API key found for '$Provider'. Use: claw-cred.ps1 -Action Set -Provider $Provider"
        exit 1
    }
    $encrypted = (Get-Content -Path $path -Raw -Encoding UTF8).Trim()
    ConvertTo-SecureString -String $encrypted
}

function Get-Key {
    param([string]$Provider)
    if (-not $Provider) {
        Write-Error "Usage: claw-cred.ps1 -Action Get -Provider <name>"
        exit 1
    }
    try {
        $secure = Read-KeySecureString -Provider $Provider
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            # Write plain key to stdout ONLY (no extra output)
            Write-Host $plain
        } finally {
            if ($ptr -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
            }
        }
    }
    catch {
        Write-Error "Failed to decrypt key for '$Provider': $_"
        exit 1
    }
}

function List-Keys {
    EnsureKeysDir
    Write-Host "Stored claw-code API keys (DPAPI-encrypted in $KeysDir):"
    $files = Get-ChildItem -Path $KeysDir -Filter "*.enc" -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  (none)"
    }
    else {
        foreach ($f in $files) {
            $provider = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $size = $f.Length
            Write-Host "  $provider  ($size bytes)"
        }
    }
}

function Test-OneKey {
    param([string]$Provider)
    try {
        $secure = Read-KeySecureString -Provider $Provider
        if ($secure.Length -le 0) {
            [pscustomobject]@{ Provider = $Provider; Status = "empty"; Detail = "decrypted but empty" }
        } else {
            [pscustomobject]@{ Provider = $Provider; Status = "ok"; Detail = "decryptable for current Windows user" }
        }
    } catch {
        [pscustomobject]@{ Provider = $Provider; Status = "failed"; Detail = $_.Exception.Message }
    }
}

function Test-Keys {
    param([string]$Provider)
    EnsureKeysDir
    $providers = @()
    if (-not [string]::IsNullOrWhiteSpace($Provider)) {
        $providers = @($Provider)
    } else {
        $providers = Get-ChildItem -Path $KeysDir -Filter "*.enc" -ErrorAction SilentlyContinue |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
    }
    if (-not $providers -or $providers.Count -eq 0) {
        Write-Host "No stored claw-code API keys found in $KeysDir"
        return
    }
    $results = foreach ($name in $providers) { Test-OneKey -Provider $name }
    $results | Format-Table -AutoSize
    if ($results.Status -contains "failed" -or $results.Status -contains "empty") {
        exit 2
    }
}

function Remove-Key {
    param([string]$Provider)
    if (-not $Provider) {
        Write-Error "Usage: claw-cred.ps1 -Action Remove -Provider <name>"
        exit 1
    }
    $path = Join-Path $KeysDir "$Provider.enc"
    if (Test-Path $path) {
        Remove-Item -Path $path -Force
        Write-Host "Removed API key for '$Provider'"
    }
    else {
        Write-Host "No stored key for '$Provider' (nothing to remove)"
    }
}

# Main dispatch
try {
    switch ($Action.ToLower()) {
        "set"    { Store-Key -Provider $Provider -ApiKey $Key }
        "get"    { Get-Key -Provider $Provider }
        "list"   { List-Keys }
        "test"   { Test-Keys -Provider $Provider }
        "remove" { Remove-Key -Provider $Provider }
        default  {
            Write-Host "claw-cred: Manage claw-code API keys (DPAPI-encrypted)"
            Write-Host ""
            Write-Host "  -Action Set    -Provider <name>                   Store a key with secure prompt"
            Write-Host "  -Action Get    -Provider <name>                   Retrieve a key"
            Write-Host "  -Action List                                     List stored providers"
            Write-Host "  -Action Test   [-Provider <name>]                 Check decryptability without printing keys"
            Write-Host "  -Action Remove -Provider <name>                   Delete a key"
            Write-Host ""
            Write-Host "  Keys stored in: $KeysDir"
        }
    }
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
