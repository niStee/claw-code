$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$profileRoot = Join-Path $repoRoot "profiles\gemini-mozmail"
$profileGemini = Join-Path $profileRoot ".gemini"
$settingsPath = Join-Path $profileGemini "settings.json"

New-Item -ItemType Directory -Force -Path $profileGemini | Out-Null

if (-not (Test-Path -LiteralPath $settingsPath)) {
    @'
{
  "security": {
    "auth": {
      "selectedType": "oauth-personal"
    }
  }
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding utf8
}

$env:GEMINI_CLI_HOME = $profileRoot
$env:GEMINI_FORCE_FILE_STORAGE = "true"
$env:GOOGLE_GENAI_USE_GCA = "true"

& (Join-Path $PSScriptRoot "gemini-cli.ps1") @args
exit $LASTEXITCODE
