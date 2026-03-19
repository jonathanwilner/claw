[CmdletBinding()]
param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputRoot = (Join-Path $ProjectRoot 'dist\openclaw-portable-bundle'),
    [string]$BundleName = 'openclaw-portable-bundle',
    [string]$WslX64,
    [string]$WslArm64,
    [string]$DockerX64,
    [string]$DockerArm64,
    [string]$DockerImagesX64Root,
    [string]$DockerImagesArm64Root,
    [string]$OllamaModelArchiveX64,
    [string]$OllamaModelArchiveArm64
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Copy-Tree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Copy-OptionalFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not $Source) {
        return
    }

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Optional payload file not found: $Source"
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-OptionalDirectory {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not $Source) {
        return
    }

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Optional payload directory not found: $Source"
    }

    Copy-Tree -Source $Source -Destination $Destination
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$outputRootResolved = [IO.Path]::GetFullPath($OutputRoot)

if (Test-Path -LiteralPath $outputRootResolved) {
    Remove-Item -LiteralPath $outputRootResolved -Recurse -Force
}
New-Item -ItemType Directory -Path $outputRootResolved -Force | Out-Null

$includeDirs = @('docs', 'installer', 'scripts', 'tests', 'vm')
$includeFiles = @('.env.example', 'README.md', 'RUNBOOK.md', 'WINDOWS_WSL2_DOCKER_CODEX_PROMPT.md', 'compose.yaml')

foreach ($dir in $includeDirs) {
    Copy-Tree -Source (Join-Path $projectRootResolved $dir) -Destination (Join-Path $outputRootResolved $dir)
}

foreach ($file in $includeFiles) {
    Copy-Item -LiteralPath (Join-Path $projectRootResolved $file) -Destination (Join-Path $outputRootResolved $file) -Force
}

$payloadX64 = Join-Path $outputRootResolved 'installer\payload\x64'
$payloadArm64 = Join-Path $outputRootResolved 'installer\payload\arm64'

Copy-OptionalFile -Source $WslX64 -Destination (Join-Path $payloadX64 'wsl.msi')
Copy-OptionalFile -Source $WslArm64 -Destination (Join-Path $payloadArm64 'wsl.msi')
Copy-OptionalFile -Source $DockerX64 -Destination (Join-Path $payloadX64 'DockerDesktopInstaller.exe')
Copy-OptionalFile -Source $DockerArm64 -Destination (Join-Path $payloadArm64 'DockerDesktopInstaller.exe')
Copy-OptionalDirectory -Source $DockerImagesX64Root -Destination (Join-Path $payloadX64 'images')
Copy-OptionalDirectory -Source $DockerImagesArm64Root -Destination (Join-Path $payloadArm64 'images')
Copy-OptionalFile -Source $OllamaModelArchiveX64 -Destination (Join-Path $payloadX64 ('ollama-models\' + [IO.Path]::GetFileName($OllamaModelArchiveX64)))
Copy-OptionalFile -Source $OllamaModelArchiveArm64 -Destination (Join-Path $payloadArm64 ('ollama-models\' + [IO.Path]::GetFileName($OllamaModelArchiveArm64)))

$manifestPath = Join-Path $outputRootResolved 'installer\BundleManifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName builtBundleRoot -NotePropertyValue $outputRootResolved -Force
$manifest | Add-Member -NotePropertyName packagedPayloads -NotePropertyValue @{
    x64 = @(Get-ChildItem -LiteralPath $payloadX64 -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($payloadX64.Length + 1).Replace('\', '/') })
    arm64 = @(Get-ChildItem -LiteralPath $payloadArm64 -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($payloadArm64.Length + 1).Replace('\', '/') })
} -Force
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding ascii

Write-Output $outputRootResolved
