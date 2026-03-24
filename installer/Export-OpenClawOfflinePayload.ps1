[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$OpenClawImage = 'openclaw/openclaw:latest',
    [string]$OllamaImage = 'ollama/ollama:latest',
    [string[]]$HelperImage = @('alpine/socat:1.8.0.3'),
    [string]$WeixinPluginNpmSpec = '@tencent-weixin/openclaw-weixin',
    [string]$Model,
    [string]$OllamaModelsDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OutputRoot) {
    throw 'OutputRoot is required.'
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker is required to export offline payloads.'
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw 'npm is required to export the Weixin plugin tarball.'
}

$outputRootResolved = [IO.Path]::GetFullPath($OutputRoot)
$imagesDir = Join-Path $outputRootResolved 'images'
$modelsDir = Join-Path $outputRootResolved 'ollama-models'
$npmDir = Join-Path $outputRootResolved 'npm'

New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
New-Item -ItemType Directory -Path $modelsDir -Force | Out-Null
New-Item -ItemType Directory -Path $npmDir -Force | Out-Null

function Save-DockerImageArchive {
    param([Parameter(Mandatory)][string]$Image)

    $archiveName = ($Image -replace '/', '_' -replace ':', '_') + '.tar'
    $archivePath = Join-Path $imagesDir $archiveName
    docker pull $Image | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "docker pull failed for $Image"
    }
    docker save -o $archivePath $Image
    if ($LASTEXITCODE -ne 0) {
        throw "docker save failed for $Image"
    }
    return $archiveName
}

$archives = @()
foreach ($image in @($OpenClawImage, $OllamaImage) + $HelperImage) {
    $archives += Save-DockerImageArchive -Image $image
}

Push-Location $npmDir
try {
    npm pack $WeixinPluginNpmSpec | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "npm pack failed for $WeixinPluginNpmSpec"
    }

    $weixinTarball = Get-ChildItem -LiteralPath $npmDir -Filter *.tgz -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $weixinTarball) {
        throw "npm pack did not produce a tarball for $WeixinPluginNpmSpec"
    }
}
finally {
    Pop-Location
}

$modelArchiveName = $null
if ($OllamaModelsDir) {
    if (-not (Test-Path -LiteralPath $OllamaModelsDir)) {
        throw "Ollama models directory not found: $OllamaModelsDir"
    }
    $modelArchiveName = 'ollama-models.zip'
    $modelArchivePath = Join-Path $modelsDir $modelArchiveName
    if (Test-Path -LiteralPath $modelArchivePath) {
        Remove-Item -LiteralPath $modelArchivePath -Force
    }
    Compress-Archive -Path (Join-Path $OllamaModelsDir '*') -DestinationPath $modelArchivePath -Force
}

$manifest = [pscustomobject]@{
    images = $archives
    model = $Model
    modelArchive = $modelArchiveName
    weixinPlugin = @{
        npmSpec = $WeixinPluginNpmSpec
        archive = $weixinTarball.Name
    }
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputRootResolved 'offline-payload.json') -Encoding ascii
Write-Output $outputRootResolved
