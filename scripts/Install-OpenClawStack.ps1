[CmdletBinding()]
param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$Model = 'glm-4.7-flash',
    [string]$Distro = 'Ubuntu',
    [string]$OpenClawImage = 'openclaw/openclaw:latest',
    [string]$OllamaImage = 'ollama/ollama:latest',
    [string]$WeixinPluginNpmSpec = '@tencent-weixin/openclaw-weixin',
    [string]$WeixinPluginTarballPath,
    [string]$GatewayPort = '18789',
    [string]$BridgePort = '18790',
    [string]$GatewayBind = '0.0.0.0',
    [string]$TimeZone = 'America/Los_Angeles',
    [string]$OllamaApiKey = 'ollama-local',
    [string]$WslMsiPath,
    [string]$DockerInstallerPath,
    [string]$DockerImageArchiveRoot,
    [string]$OllamaModelsArchivePath,
    [switch]$InstallWsl,
    [switch]$InstallDockerDesktop,
    [switch]$InstallWeixinPlugin,
    [switch]$WeixinQrLogin,
    [switch]$ResetConfig,
    [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'OpenClaw.WeixinPackaging.ps1')

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Name was not found on PATH."
    }

    $command
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$Arguments = @(),
        [switch]$IgnoreExitCode
    )

    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        throw "Command failed with exit code $exitCode: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-DockerCompose {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Push-Location $ProjectRoot
    try {
        Invoke-Native -FilePath 'docker' -Arguments @('compose', '--project-directory', $ProjectRoot, '-f', (Join-Path $ProjectRoot 'compose.yaml')) + $Arguments
    }
    finally {
        Pop-Location
    }
}

function Invoke-OpenClawCliCompose {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Invoke-DockerCompose -Arguments (@('run', '--rm', '-T', 'openclaw-cli') + $Arguments)
}

function Test-DockerImagePresent {
    param([Parameter(Mandatory)][string]$Image)

    & docker image inspect $Image *> $null
    return $LASTEXITCODE -eq 0
}

function Import-DockerImageArchives {
    param([string]$ArchiveRoot)

    if (-not $ArchiveRoot) {
        return
    }

    if (-not (Test-Path -LiteralPath $ArchiveRoot)) {
        throw "Docker image archive root not found: $ArchiveRoot"
    }

    $archives = Get-ChildItem -LiteralPath $ArchiveRoot -Filter *.tar -File -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($archive in $archives) {
        Write-Step "Loading Docker image archive $($archive.Name)"
        Invoke-Native -FilePath 'docker' -Arguments @('load', '-i', $archive.FullName)
    }
}

function Restore-OllamaModelArchive {
    param(
        [string]$ArchivePath,
        [string]$OllamaDataDirectory
    )

    if (-not $ArchivePath) {
        return
    }

    if (-not (Test-Path -LiteralPath $ArchivePath)) {
        throw "Ollama model archive not found: $ArchivePath"
    }

    $modelsPath = Join-Path $OllamaDataDirectory 'models'
    Ensure-Directory -Path $modelsPath

    Write-Step "Restoring Ollama model archive $ArchivePath"
    $extension = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    if ($extension -eq '.zip') {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $modelsPath -Force
        return
    }

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tar) {
        $tar = Get-Command tar -ErrorAction SilentlyContinue
    }
    if (-not $tar) {
        throw 'tar.exe or tar was not found, so the Ollama model archive cannot be restored.'
    }

    Invoke-Native -FilePath $tar.Source -Arguments @('-xf', $ArchivePath, '-C', $modelsPath)
}

function Wait-HttpEndpoint {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -Method Get -TimeoutSec 10 -UseBasicParsing
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 2
            continue
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Uri"
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-EnvFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values
    )

    $lines = foreach ($key in ($Values.Keys | Sort-Object)) {
        '{0}={1}' -f $key, $Values[$key]
    }

    Set-Content -LiteralPath $Path -Value ($lines -join [Environment]::NewLine) -Encoding ascii
}

function Configure-OpenClawWeixinPlugin {
    param(
        [Parameter(Mandatory)][string]$WorkspaceDirectory,
        [Parameter(Mandatory)][string]$ConfigDirectory
    )

    $resolvedPlugin = Resolve-OpenClawWeixinInstallSpec `
        -WorkspaceDirectory $WorkspaceDirectory `
        -WeixinPluginTarballPath $WeixinPluginTarballPath `
        -DefaultNpmSpec $WeixinPluginNpmSpec

    Write-Step "Installing OpenClaw Weixin plugin from $($resolvedPlugin.InstallSpec)"
    Invoke-OpenClawCliCompose -Arguments @('plugins', 'install', $resolvedPlugin.InstallSpec)

    Write-Step 'Enabling OpenClaw Weixin plugin'
    Invoke-OpenClawCliCompose -Arguments @('config', 'set', 'plugins.entries.openclaw-weixin.enabled', 'true')

    if ($WeixinQrLogin) {
        Write-Step 'Starting interactive Weixin QR login'
        Invoke-DockerCompose -Arguments @('run', '--rm', 'openclaw-cli', 'channels', 'login', '--channel', 'openclaw-weixin')
    }

    $markerPath = Get-OpenClawWeixinMarkerPath -ConfigDirectory $ConfigDirectory
    $marker = New-OpenClawWeixinMarker -InstallSpec $resolvedPlugin.InstallSpec -SourceKind $resolvedPlugin.SourceKind -QrLoginRequested:$WeixinQrLogin
    $marker | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $markerPath -Encoding ascii
}

function Install-PrereqsIfRequested {
    if (-not $InstallWsl -and -not $InstallDockerDesktop) {
        return
    }

    if (-not (Test-IsAdministrator)) {
        throw 'Installing WSL or Docker Desktop requires an elevated PowerShell session.'
    }

    $prereqScript = Join-Path $PSScriptRoot 'Install-OpenClawPrereqs.ps1'
    if (-not (Test-Path -LiteralPath $prereqScript)) {
        throw "Prerequisite installer not found: $prereqScript"
    }

    $prereqArguments = @(
        '-Distro', $Distro
    )

    if ($InstallDockerDesktop) {
        $prereqArguments += '-InstallDockerDesktop'
    }

    if ($WslMsiPath) {
        $prereqArguments += @('-WslMsiPath', $WslMsiPath)
    }

    if ($DockerInstallerPath) {
        $prereqArguments += @('-DockerInstallerPath', $DockerInstallerPath)
    }

    if (-not $InstallWsl) {
        $prereqArguments += '-SkipWsl'
    }

    Write-Step 'Installing or validating Windows prerequisites'
    & $prereqScript @prereqArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Prerequisite installer failed with exit code $LASTEXITCODE"
    }
}

$stateRoot = Join-Path $ProjectRoot 'state'
$openClawConfigDir = Join-Path $stateRoot 'openclaw-config'
$openClawWorkspaceDir = Join-Path $stateRoot 'openclaw-workspace'
$ollamaDataDir = Join-Path $stateRoot 'ollama'
$envPath = Join-Path $ProjectRoot '.env'

Write-Step 'Preparing prerequisites'
Install-PrereqsIfRequested
Assert-Command -Name 'docker' | Out-Null

try {
    Invoke-Native -FilePath 'docker' -Arguments @('info') | Out-Null
}
catch {
    throw 'Docker is installed but the daemon is not reachable. Start Docker Desktop and wait for it to finish initializing.'
}

Ensure-Directory -Path $stateRoot
Ensure-Directory -Path $openClawConfigDir
Ensure-Directory -Path $openClawWorkspaceDir
Ensure-Directory -Path $ollamaDataDir

Import-DockerImageArchives -ArchiveRoot $DockerImageArchiveRoot
Restore-OllamaModelArchive -ArchivePath $OllamaModelsArchivePath -OllamaDataDirectory $ollamaDataDir

if ($ResetConfig) {
    Write-Step 'Resetting generated OpenClaw state'
    if (Test-Path -LiteralPath $openClawConfigDir) {
        Remove-Item -LiteralPath $openClawConfigDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $openClawWorkspaceDir) {
        Remove-Item -LiteralPath $openClawWorkspaceDir -Recurse -Force
    }
    Ensure-Directory -Path $openClawConfigDir
    Ensure-Directory -Path $openClawWorkspaceDir
}

Write-Step 'Writing .env for the packaged stack'
Write-EnvFile -Path $envPath -Values @{
    OLLAMA_API_KEY                 = $OllamaApiKey
    OLLAMA_DATA_DIR                = './state/ollama'
    OLLAMA_IMAGE                   = $OllamaImage
    OLLAMA_MODEL                   = $Model
    OPENCLAW_ALLOW_INSECURE_PRIVATE_WS = '1'
    OPENCLAW_BRIDGE_PORT           = $BridgePort
    OPENCLAW_CONFIG_DIR            = './state/openclaw-config'
    OPENCLAW_GATEWAY_BIND          = $GatewayBind
    OPENCLAW_GATEWAY_PORT          = $GatewayPort
    OPENCLAW_GATEWAY_TOKEN         = ''
    OPENCLAW_IMAGE                 = $OpenClawImage
    OPENCLAW_TZ                    = $TimeZone
    OPENCLAW_WEIXIN_ENABLED        = if ($InstallWeixinPlugin) { 'true' } else { 'false' }
    OPENCLAW_WEIXIN_NPM_SPEC       = $WeixinPluginNpmSpec
    OPENCLAW_WORKSPACE_DIR         = './state/openclaw-workspace'
    PLAYWRIGHT_BROWSERS_PATH       = '/home/node/.cache/ms-playwright'
}

$requiredImages = @(
    $OpenClawImage,
    $OllamaImage,
    'alpine/socat:1.8.0.3'
)

$missingImages = @($requiredImages | Where-Object { -not (Test-DockerImagePresent -Image $_) })
if ($missingImages.Count -gt 0) {
    Write-Step "Pulling missing container images: $($missingImages -join ', ')"
    Invoke-DockerCompose -Arguments @('pull')
}
else {
    Write-Step 'All required container images are already present locally'
}

Write-Step 'Starting Ollama'
Invoke-DockerCompose -Arguments @('up', '-d', 'ollama')
Wait-HttpEndpoint -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSeconds 300

Write-Step "Pulling Ollama model $Model"
$listOutput = docker compose --project-directory $ProjectRoot -f (Join-Path $ProjectRoot 'compose.yaml') exec -T ollama ollama list 2>$null
if ($LASTEXITCODE -eq 0 -and ($listOutput | Select-String -SimpleMatch $Model)) {
    Write-Step "Ollama model $Model already present"
}
else {
    Invoke-DockerCompose -Arguments @('exec', '-T', 'ollama', 'ollama', 'pull', $Model)
}

Write-Step 'Starting OpenClaw gateway network services'
Invoke-DockerCompose -Arguments @('up', '-d', 'openclaw-gateway', 'ollama-loopback')

$onboardArgs = @(
    'run', '--rm', '-T',
    '-e', "OLLAMA_API_KEY=$OllamaApiKey",
    'openclaw-cli',
    'onboard',
    '--non-interactive',
    '--auth-choice', 'ollama',
    '--custom-base-url', 'http://127.0.0.1:11434',
    '--custom-model-id', $Model,
    '--accept-risk'
)

if ($ResetConfig) {
    $onboardArgs += '--reset'
}

Write-Step 'Running non-interactive OpenClaw onboarding'
Invoke-DockerCompose -Arguments $onboardArgs

if ($InstallWeixinPlugin) {
    Configure-OpenClawWeixinPlugin -WorkspaceDirectory $openClawWorkspaceDir -ConfigDirectory $openClawConfigDir
}

Write-Step 'Restarting the OpenClaw gateway with generated config'
Invoke-DockerCompose -Arguments @('restart', 'openclaw-gateway', 'ollama-loopback')
Wait-HttpEndpoint -Uri "http://127.0.0.1:$GatewayPort/healthz" -TimeoutSeconds 180

if (-not $SkipValidation) {
    Write-Step 'Running deployment validation'
    & (Join-Path $PSScriptRoot 'Invoke-OpenClawDeploymentValidation.ps1') `
        -OllamaUri 'http://127.0.0.1:11434/api/tags' `
        -OpenClawUri "http://127.0.0.1:$GatewayPort/healthz" `
        -WeixinMarkerPath (Get-OpenClawWeixinMarkerPath -ConfigDirectory $openClawConfigDir) `
        -RequiredContainers @('openclaw-ollama', 'openclaw-gateway', 'openclaw-ollama-loopback')

    if ($LASTEXITCODE -ne 0) {
        throw 'Deployment validation failed.'
    }
}

Write-Step 'OpenClaw packaged deployment is ready'
Write-Host "Gateway: http://127.0.0.1:$GatewayPort/"
Write-Host "Bridge:  http://127.0.0.1:$BridgePort/"
