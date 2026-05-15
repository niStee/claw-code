$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$geminiJs = Join-Path $repoRoot "tools\gemini-cli\package\bundle\gemini.js"
$bundledNode = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\node.exe"

if (-not (Test-Path -LiteralPath $geminiJs)) {
    throw "Gemini CLI package is missing at $geminiJs. Run the local bootstrap first."
}

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if ([string]::IsNullOrWhiteSpace($node)) {
    $node = $bundledNode
}

if (-not (Test-Path -LiteralPath $node)) {
    throw "Node.js was not found on PATH and Codex bundled node.exe was not found at $bundledNode."
}

& $node $geminiJs @args
exit $LASTEXITCODE
