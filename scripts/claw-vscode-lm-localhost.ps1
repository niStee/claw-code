#Requires -Version 5.1
<#
.SYNOPSIS
    Patch the installed VS Code LM Proxy extension to bind localhost only.
.DESCRIPTION
    The ryonakae.vscode-lm-proxy extension version tested here starts Express
    with app.listen(port), which binds all interfaces on Windows. This script
    patches the installed extension output to app.listen(port, "127.0.0.1"),
    keeps a backup, and can stop existing port listeners so VS Code restarts it
    with the safer bind.
#>

param(
    [switch]$NoStop,
    [int]$Port = 4000
)

$ErrorActionPreference = "Stop"
$extensionRoot = Join-Path $env:USERPROFILE ".vscode\extensions"

function Get-LmProxyExtension {
    if (-not (Test-Path -LiteralPath $extensionRoot)) {
        return $null
    }
    Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter "ryonakae.vscode-lm-proxy-*" |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

$extension = Get-LmProxyExtension
if (-not $extension) {
    throw "VS Code LM Proxy extension was not found under $extensionRoot."
}

$manager = Join-Path $extension.FullName "out\server\manager.js"
if (-not (Test-Path -LiteralPath $manager)) {
    throw "VS Code LM Proxy manager file was not found: $manager"
}

$backup = "$manager.bak-claw-localhost"
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $manager -Destination $backup -Force
    Write-Host "Backup: $backup"
}

$text = Get-Content -LiteralPath $manager -Raw
$unsafe = 'this.server = app.listen(port, () => {'
$safe = 'this.server = app.listen(port, "127.0.0.1", () => {'

if ($text.Contains($unsafe)) {
    $text = $text.Replace($unsafe, $safe)
    [System.IO.File]::WriteAllText($manager, $text, [System.Text.Encoding]::UTF8)
    Write-Host "Patched: $manager"
} elseif ($text.Contains($safe)) {
    Write-Host "Already patched: $manager"
} else {
    throw "Did not find the expected app.listen call in $manager. The extension may have changed."
}

if (-not $NoStop) {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($processId in $listeners) {
        Write-Host "Stopping current port $Port listener PID $processId"
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "VS Code LM Proxy localhost patch complete. Restart VS Code or start the extension again."
