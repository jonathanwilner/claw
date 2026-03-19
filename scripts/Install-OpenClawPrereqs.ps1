[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu',
    [string]$DownloadDirectory = "$env:TEMP\OpenClawPrereqs",
    [string]$WslMsiPath,
    [string]$DockerInstallerPath,
    [switch]$InstallDockerDesktop,
    [switch]$SkipWsl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Invoke-WebDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
}

function Get-WindowsArchitecture {
    $arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $arch -match 'ARM') {
        return 'arm64'
    }
    return 'x64'
}

function Get-LatestWslReleaseAssetUrl {
    param([Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture)

    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/WSL/releases/latest'
    $assetName = "wsl.$($release.tag_name.TrimStart('v')).0.$Architecture.msi"

    $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -like "*.${Architecture}.msi" } | Select-Object -First 1
    }

    if (-not $asset) {
        throw "Could not find a WSL MSI asset for architecture $Architecture in the latest WSL release."
    }

    [pscustomobject]@{
        Tag = $release.tag_name
        Name = $asset.name
        Url = $asset.browser_download_url
    }
}

function Install-WslFromMsi {
    param([Parameter(Mandatory)][string]$Path)

    Write-Step "Installing WSL from MSI $Path"
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $Path, '/qn', '/norestart') -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "WSL MSI install failed with exit code $($process.ExitCode)"
    }
}

function Ensure-WslFeatureSet {
    $features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
    $rebootNeeded = $false

    foreach ($feature in $features) {
        $info = Get-WindowsOptionalFeature -Online -FeatureName $feature
        if ($info.State -ne 'Enabled') {
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
            $rebootNeeded = $true
        }
    }

    if ($rebootNeeded) {
        Write-Warning 'WSL prerequisite features were enabled. Reboot Windows before continuing if WSL install still fails.'
    }
}

function Ensure-WslInstalled {
    param(
        [Parameter(Mandatory)][string]$Architecture,
        [string]$ProvidedMsiPath,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$TargetDistro
    )

    Ensure-WslFeatureSet

    $versionCheck = & wsl.exe --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Step 'Modern WSL is already installed'
    }
    else {
        $wslMessage = ($versionCheck | Out-String)
        $needsSideload = $wslMessage -match 'Windows Subsystem for Linux is not installed'
        if ($needsSideload) {
            $msiPath = $ProvidedMsiPath
            if (-not $msiPath) {
                New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
                $asset = Get-LatestWslReleaseAssetUrl -Architecture $Architecture
                $msiPath = Join-Path $TargetDirectory $asset.Name
                Write-Step "Downloading WSL $($asset.Tag) MSI for $Architecture"
                Invoke-WebDownload -Uri $asset.Url -OutFile $msiPath
            }

            Install-WslFromMsi -Path $msiPath
        }
    }

    Write-Step "Installing WSL distro $TargetDistro"
    & wsl.exe --install -d $TargetDistro
    if ($LASTEXITCODE -ne 0) {
        throw 'wsl.exe --install failed after the WSL MSI/bootstrap path.'
    }
}

function Get-DockerDesktopUrl {
    param([Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture)

    switch ($Architecture) {
        'x64' { 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe?utm_campaign=docs-driven-download-win-amd64&utm_medium=webreferral&utm_source=docker' }
        'arm64' { 'https://desktop.docker.com/win/main/arm64/Docker%20Desktop%20Installer.exe?utm_campaign=docs-driven-download-win-arm64&utm_medium=webreferral&utm_source=docker' }
    }
}

function Ensure-DockerDesktopInstalled {
    param(
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [string]$ProvidedInstallerPath
    )

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        Write-Step 'Docker CLI already present'
        return
    }

    if (-not $InstallDockerDesktop) {
        throw 'Docker Desktop is not installed. Re-run with -InstallDockerDesktop or provide -DockerInstallerPath.'
    }

    $installerPath = $ProvidedInstallerPath
    if (-not $installerPath) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
        $installerPath = Join-Path $TargetDirectory 'DockerDesktopInstaller.exe'
        $url = Get-DockerDesktopUrl -Architecture $Architecture
        Write-Step "Downloading Docker Desktop installer for $Architecture"
        Invoke-WebDownload -Uri $url -OutFile $installerPath
    }

    Write-Step 'Installing Docker Desktop'
    $process = Start-Process -FilePath $installerPath -ArgumentList @('install', '--quiet', '--accept-license', '--backend=wsl-2', '--always-run-service') -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Docker Desktop install failed with exit code $($process.ExitCode)"
    }
}

$architecture = Get-WindowsArchitecture
Write-Step "Detected Windows architecture: $architecture"

if (-not $SkipWsl) {
    Ensure-WslInstalled -Architecture $architecture -ProvidedMsiPath $WslMsiPath -TargetDirectory $DownloadDirectory -TargetDistro $Distro
}

Ensure-DockerDesktopInstalled -Architecture $architecture -TargetDirectory $DownloadDirectory -ProvidedInstallerPath $DockerInstallerPath
