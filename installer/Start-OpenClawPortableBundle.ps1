[CmdletBinding()]
param(
    [string]$BundleRoot = (Resolve-Path $PSScriptRoot).Path,
    [ValidateSet('auto', 'x64', 'arm64')]
    [string]$Architecture = 'auto',
    [string]$ProjectRoot,
    [string]$Model = 'glm-4.7-flash',
    [string]$OpenClawImage = 'openclaw/openclaw:latest',
    [string]$OllamaImage = 'ollama/ollama:latest',
    [string]$GatewayPort = '18789',
    [string]$BridgePort = '18790',
    [string]$GatewayBind = '0.0.0.0',
    [string]$TimeZone = 'America/Los_Angeles',
    [string]$OllamaApiKey = 'ollama-local',
    [switch]$InstallWsl,
    [switch]$InstallDockerDesktop,
    [switch]$InstallWeixinPlugin,
    [switch]$WeixinQrLogin,
    [switch]$ResetConfig,
    [switch]$SkipValidation,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message"
}

function Get-OpenClawArchitecture {
    param(
        [Parameter(Mandatory)]
        [string]$RequestedArchitecture
    )

    if ($RequestedArchitecture -ne 'auto') {
        return $RequestedArchitecture
    }

    $archToken = $env:PROCESSOR_ARCHITEW6432
    if (-not $archToken) {
        $archToken = $env:PROCESSOR_ARCHITECTURE
    }

    if (-not $archToken) {
        throw 'Unable to determine the host architecture.'
    }

    switch ($archToken.ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'X86' { throw '32-bit Windows is not supported by this bundle. Use a 64-bit x64 or arm64 host.' }
        default { throw "Unsupported host architecture token: $archToken" }
    }
}

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Resolve-OpenClawProjectRoot {
    param(
        [Parameter(Mandatory)]
        [string]$BundleRoot,

        [Parameter(Mandatory)]
        [string]$ResolvedArchitecture,

        [string]$ExplicitProjectRoot
    )

    if ($ExplicitProjectRoot) {
        $resolved = Resolve-ExistingPath -Candidates @($ExplicitProjectRoot)
        if (-not $resolved) {
            throw "Project root not found: $ExplicitProjectRoot"
        }

        return $resolved
    }

    $payloadRoot = Join-Path -Path (Join-Path -Path $BundleRoot -ChildPath 'payload') -ChildPath $ResolvedArchitecture
    $candidateRoots = @(
        $BundleRoot,
        (Split-Path -Path $BundleRoot -Parent),
        (Join-Path $BundleRoot 'project'),
        (Join-Path -Path $payloadRoot -ChildPath 'project'),
        $payloadRoot
    )

    foreach ($candidateRoot in $candidateRoots) {
        if (-not $candidateRoot) {
            continue
        }

        $installerPath = Join-Path $candidateRoot 'scripts/Install-OpenClawStack.ps1'
        $composePath = Join-Path $candidateRoot 'compose.yaml'
        if ((Test-Path -LiteralPath $installerPath) -and (Test-Path -LiteralPath $composePath)) {
            return (Resolve-Path -LiteralPath $candidateRoot).Path
        }
    }

    throw 'Could not find a runnable OpenClaw project tree. Copy the repository contents into the bundle or pass -ProjectRoot.'
}

function Resolve-OpenClawPayloadRoot {
    param(
        [Parameter(Mandatory)]
        [string]$BundleRoot,

        [Parameter(Mandatory)]
        [string]$ResolvedArchitecture
    )

    $payloadRoot = Join-Path -Path (Join-Path -Path $BundleRoot -ChildPath 'payload') -ChildPath $ResolvedArchitecture
    if (Test-Path -LiteralPath $payloadRoot) {
        return (Resolve-Path -LiteralPath $payloadRoot).Path
    }

    return $null
}

function Resolve-OptionalPayloadFile {
    param(
        [string]$PayloadRoot,
        [string[]]$Candidates
    )

    if (-not $PayloadRoot) {
        return $null
    }

    foreach ($candidate in $Candidates) {
        $path = Join-Path $PayloadRoot $candidate
        if ($candidate.Contains('*') -or $candidate.Contains('?')) {
            $match = Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
        elseif (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $null
}

$bundleRootResolved = Resolve-ExistingPath -Candidates @($BundleRoot)
if (-not $bundleRootResolved) {
    throw "Bundle root not found: $BundleRoot"
}

$machineArchitecture = Get-OpenClawArchitecture -RequestedArchitecture $Architecture
$payloadRoot = Resolve-OpenClawPayloadRoot -BundleRoot $bundleRootResolved -ResolvedArchitecture $machineArchitecture
$projectRootResolved = Resolve-OpenClawProjectRoot -BundleRoot $bundleRootResolved -ResolvedArchitecture $machineArchitecture -ExplicitProjectRoot $ProjectRoot
$installerPath = Join-Path $projectRootResolved 'scripts/Install-OpenClawStack.ps1'
$wslMsiPath = Resolve-OptionalPayloadFile -PayloadRoot $payloadRoot -Candidates @('wsl.msi', 'wsl.x64.msi', 'wsl.arm64.msi')
$dockerInstallerPath = Resolve-OptionalPayloadFile -PayloadRoot $payloadRoot -Candidates @('DockerDesktopInstaller.exe')
$dockerImageArchiveRoot = Resolve-OptionalPayloadFile -PayloadRoot $payloadRoot -Candidates @('images')
$weixinPluginTarballPath = Resolve-OptionalPayloadFile -PayloadRoot $payloadRoot -Candidates @(
    'npm/tencent-weixin-openclaw-weixin-*.tgz',
    'npm/tencent-weixin-openclaw-weixin.tgz',
    'npm/openclaw-weixin*.tgz'
)
$ollamaModelsArchivePath = Resolve-OptionalPayloadFile -PayloadRoot $payloadRoot -Candidates @(
    'ollama-models/ollama-models.tar.gz',
    'ollama-models/ollama-models.zip'
)

Set-Item -Path Env:OPENCLAW_PORTABLE_BUNDLE_ROOT -Value $bundleRootResolved
Set-Item -Path Env:OPENCLAW_PORTABLE_ARCHITECTURE -Value $machineArchitecture
Set-Item -Path Env:OPENCLAW_PORTABLE_PROJECT_ROOT -Value $projectRootResolved
if ($payloadRoot) {
    Set-Item -Path Env:OPENCLAW_PORTABLE_PAYLOAD_ROOT -Value $payloadRoot
}

Write-Step "Bundle root: $bundleRootResolved"
Write-Step "Selected architecture: $machineArchitecture"
Write-Step "Project root: $projectRootResolved"
if ($payloadRoot) {
    Write-Step "Payload root: $payloadRoot"
}
else {
    Write-Step 'Payload root: not staged yet'
}

if ($DryRun) {
    Write-Step 'Dry run requested; not invoking the installer.'
    return
}

$installerArguments = @(
    '-ProjectRoot', $projectRootResolved,
    '-Model', $Model,
    '-OpenClawImage', $OpenClawImage,
    '-OllamaImage', $OllamaImage,
    '-GatewayPort', $GatewayPort,
    '-BridgePort', $BridgePort,
    '-GatewayBind', $GatewayBind,
    '-TimeZone', $TimeZone,
    '-OllamaApiKey', $OllamaApiKey
)

if ($wslMsiPath) {
    $installerArguments += @('-WslMsiPath', $wslMsiPath)
}

if ($dockerInstallerPath) {
    $installerArguments += @('-DockerInstallerPath', $dockerInstallerPath)
}

if ($dockerImageArchiveRoot) {
    $installerArguments += @('-DockerImageArchiveRoot', $dockerImageArchiveRoot)
}

if ($ollamaModelsArchivePath) {
    $installerArguments += @('-OllamaModelsArchivePath', $ollamaModelsArchivePath)
}

if ($weixinPluginTarballPath) {
    $installerArguments += @('-WeixinPluginTarballPath', $weixinPluginTarballPath)
}

if ($InstallWsl) {
    $installerArguments += '-InstallWsl'
}

if ($InstallDockerDesktop) {
    $installerArguments += '-InstallDockerDesktop'
}

if ($InstallWeixinPlugin) {
    $installerArguments += '-InstallWeixinPlugin'
}

if ($WeixinQrLogin) {
    $installerArguments += '-WeixinQrLogin'
}

if ($ResetConfig) {
    $installerArguments += '-ResetConfig'
}

if ($SkipValidation) {
    $installerArguments += '-SkipValidation'
}

Write-Step "Invoking installer: $installerPath"
& $installerPath @installerArguments
