[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$OpenClawUri = 'http://127.0.0.1:18789/healthz',
    [string]$OllamaUri = 'http://127.0.0.1:11434/api/tags',
    [string[]]$RequiredContainers = @('openclaw-ollama', 'openclaw-gateway', 'openclaw-ollama-loopback')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = $env:OPENCLAW_PORTABLE_PROJECT_ROOT
}

if (-not $ProjectRoot) {
    throw 'Project root was not supplied and OPENCLAW_PORTABLE_PROJECT_ROOT is not set.'
}

$validationScript = Join-Path $ProjectRoot 'scripts\Invoke-OpenClawDeploymentValidation.ps1'
if (-not (Test-Path -LiteralPath $validationScript)) {
    throw "Validation script not found: $validationScript"
}

& $validationScript -OpenClawUri $OpenClawUri -OllamaUri $OllamaUri -RequiredContainers $RequiredContainers
