param(
  [string]$InstallerPath = $env:DOCKER_DESKTOP_INSTALLER_PATH,
  [string]$Arguments = $env:DOCKER_DESKTOP_ARGUMENTS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $InstallerPath) {
  Write-Host "Docker Desktop installer path not supplied; skipping install."
  return
}

if (-not (Test-Path $InstallerPath)) {
  throw "Docker Desktop installer not found: $InstallerPath"
}

Write-Host "Installing Docker Desktop from $InstallerPath"

switch ([IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()) {
  '.exe' {
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
      throw "Docker Desktop installer exited with code $($process.ExitCode)"
    }
  }
  '.msi' {
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $InstallerPath, '/qn', '/norestart') -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
      throw "msiexec exited with code $($process.ExitCode)"
    }
  }
  default {
    throw "Unsupported Docker Desktop installer type: $InstallerPath"
  }
}

if (Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue) {
  Start-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
}

# A real validation run should confirm WSL2 is active after Docker Desktop
# starts. Leave the detailed verification to the smoke-test step.
