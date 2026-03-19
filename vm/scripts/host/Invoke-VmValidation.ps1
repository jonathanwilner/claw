param(
  [string]$PackerTemplate = (Join-Path $PSScriptRoot '..\..\packer\windows11-hyperv-validation.pkr.hcl'),
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$Win11IsoUrl = $env:CLAW_WIN11_ISO_URL,
  [string]$Win11IsoChecksum = $env:CLAW_WIN11_ISO_CHECKSUM,
  [string]$DockerDesktopInstallerPath = $env:DOCKER_DESKTOP_INSTALLER_PATH,
  [string]$AppInstallerPath = $env:CLAW_APP_INSTALLER_PATH,
  [string]$AppInstallerArguments = $env:CLAW_APP_INSTALLER_ARGUMENTS,
  [string]$SmokeCommand = $env:CLAW_SMOKE_COMMAND,
  [string]$SmokeHttpUrl = $(if ($env:CLAW_SMOKE_HTTP_URL) { $env:CLAW_SMOKE_HTTP_URL } else { 'http://127.0.0.1:18789/healthz' }),
  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Packer {
  param([Parameter(Mandatory)][string[]]$Arguments)

  & packer @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "packer $($Arguments[0]) failed with exit code $LASTEXITCODE"
  }
}

if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
  throw "packer is not on PATH"
}

function Get-AppInstallerKind {
  param([Parameter(Mandatory)][string]$Path)

  if (Test-Path $Path -PathType Container) {
    return 'zip'
  }

  switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    '.msi' { 'msi' }
    '.msix' { 'msix' }
    '.appx' { 'appx' }
    '.exe' { 'exe' }
    '.zip' { 'zip' }
    default { throw "Unsupported app installer type: $Path" }
  }
}

function Copy-StagedPayload {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$DestinationPath
  )

  $destinationDirectory = Split-Path -Parent $DestinationPath
  New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
  Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
}

function New-ZipPayloadFromDirectory {
  param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$DestinationPath
  )

  if (Test-Path -LiteralPath $DestinationPath) {
    Remove-Item -LiteralPath $DestinationPath -Force
  }

  Compress-Archive -Path (Join-Path $SourceDirectory '*') -DestinationPath $DestinationPath -Force
}

if (-not $AppInstallerPath) {
  $AppInstallerPath = $ProjectRoot
}

if (-not $ValidateOnly) {
  foreach ($required in @(
    @{ Name = 'Win11IsoUrl'; Value = $Win11IsoUrl },
    @{ Name = 'Win11IsoChecksum'; Value = $Win11IsoChecksum },
    @{ Name = 'DockerDesktopInstallerPath'; Value = $DockerDesktopInstallerPath },
    @{ Name = 'AppInstallerPath'; Value = $AppInstallerPath }
  )) {
    if ([string]::IsNullOrWhiteSpace($required.Value) -or $required.Value -like 'https://example.invalid/*' -or $required.Value -eq 'none') {
      throw "$($required.Name) must be set before running a real VM build"
    }
  }

  foreach ($path in @($DockerDesktopInstallerPath, $AppInstallerPath)) {
    if (-not (Test-Path $path)) {
      throw "Installer path not found: $path"
    }
  }
}

Push-Location (Split-Path -Parent $PackerTemplate)
try {
  if (-not $ValidateOnly) {
    $stagingRoot = Join-Path (Split-Path -Parent $PackerTemplate) '..\artifacts\staging'
    $dockerStaged = Join-Path $stagingRoot 'DockerDesktopInstaller.exe'
    $appStaged = Join-Path $stagingRoot 'OpenClawPackage.zip'

    Copy-StagedPayload -SourcePath $DockerDesktopInstallerPath -DestinationPath $dockerStaged

    $appInstallerKind = Get-AppInstallerKind -Path $AppInstallerPath
    if ($appInstallerKind -eq 'zip' -and (Test-Path $AppInstallerPath -PathType Container)) {
      New-ZipPayloadFromDirectory -SourceDirectory $AppInstallerPath -DestinationPath $appStaged
    }
    else {
      Copy-StagedPayload -SourcePath $AppInstallerPath -DestinationPath $appStaged
    }
  }
  else {
    $appInstallerKind = 'auto'
  }

  Invoke-Packer -Arguments @('init', (Split-Path -Leaf $PackerTemplate))
  Invoke-Packer -Arguments @('fmt', '-check', (Split-Path -Leaf $PackerTemplate))

  $validateArguments = @(
    'validate',
    "-var=win11_iso_url=$Win11IsoUrl",
    "-var=win11_iso_checksum=$Win11IsoChecksum",
    "-var=app_installer_kind=$appInstallerKind",
    "-var=app_installer_arguments=$AppInstallerArguments",
    "-var=smoke_command=$SmokeCommand",
    "-var=smoke_http_url=$SmokeHttpUrl",
    (Split-Path -Leaf $PackerTemplate)
  )

  Invoke-Packer -Arguments $validateArguments

  if (-not $ValidateOnly) {
    Invoke-Packer -Arguments @(
      'build',
      "-var=win11_iso_url=$Win11IsoUrl",
      "-var=win11_iso_checksum=$Win11IsoChecksum",
      "-var=app_installer_kind=$appInstallerKind",
      "-var=app_installer_arguments=$AppInstallerArguments",
      "-var=smoke_command=$SmokeCommand",
      "-var=smoke_http_url=$SmokeHttpUrl",
      (Split-Path -Leaf $PackerTemplate)
    )
  }
}
finally {
  Pop-Location
}
