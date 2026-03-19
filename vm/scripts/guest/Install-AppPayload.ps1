param(
  [string]$InstallerPath = $env:APP_INSTALLER_PATH,
  [string]$Arguments = $env:APP_INSTALLER_ARGUMENTS,
  [string]$InstallerKind = $env:APP_INSTALLER_KIND,
  [string]$ExtractRoot = 'C:\OpenClawPackage'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $InstallerPath) {
  Write-Host "App installer path not supplied; skipping app install."
  return
}

if (-not (Test-Path $InstallerPath)) {
  throw "App installer not found: $InstallerPath"
}

Write-Host "Installing app payload from $InstallerPath"

if (-not $InstallerKind -or $InstallerKind -eq 'auto') {
  $InstallerKind = [IO.Path]::GetExtension($InstallerPath).TrimStart('.').ToLowerInvariant()
}

switch ($InstallerKind.ToLowerInvariant()) {
  'msi' {
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $InstallerPath, '/qn', '/norestart') -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
      throw "msiexec exited with code $($process.ExitCode)"
    }
  }
  'msix' {
    Add-AppxPackage -Path $InstallerPath -ForceApplicationShutdown
  }
  'appx' {
    Add-AppxPackage -Path $InstallerPath -ForceApplicationShutdown
  }
  'exe' {
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
      throw "app installer exited with code $($process.ExitCode)"
    }
  }
  'zip' {
    if (Test-Path -LiteralPath $ExtractRoot) {
      Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
    }

    Expand-Archive -Path $InstallerPath -DestinationPath $ExtractRoot -Force
    $installScript = Join-Path $ExtractRoot 'scripts\Install-OpenClawStack.ps1'
    if (-not (Test-Path -LiteralPath $installScript)) {
      throw "Expected packaged install script was not found at $installScript"
    }

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoLogo',
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', $installScript,
      '-ProjectRoot', $ExtractRoot,
      '-SkipValidation'
    ) -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
      throw "Packaged install script exited with code $($process.ExitCode)"
    }
  }
  default {
    throw "Unsupported app installer type: $InstallerPath"
  }
}

# The installer wrapper only proves the payload can be staged. The command-level
# behavior is verified separately by the smoke-test script.
