param(
  [string]$SmokeCommand = $env:SMOKE_COMMAND,
  [string]$SmokeHttpUrl = $env:SMOKE_HTTP_URL
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Command {
  param([Parameter(Mandatory)][string]$FileName, [string[]]$Args)

  Write-Host "Running $FileName $($Args -join ' ')"
  $process = Start-Process -FilePath $FileName -ArgumentList $Args -Wait -PassThru -NoNewWindow
  if ($process.ExitCode -ne 0) {
    throw "$FileName exited with code $($process.ExitCode)"
  }
}

if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
  Assert-Command -FileName 'wsl.exe' -Args @('--status')
  Assert-Command -FileName 'wsl.exe' -Args @('--list', '--verbose')
}

if (Get-Command docker.exe -ErrorAction SilentlyContinue) {
  Assert-Command -FileName 'docker.exe' -Args @('version')
  Assert-Command -FileName 'docker.exe' -Args @('info')
}

if ($SmokeHttpUrl) {
  Write-Host "Waiting for health endpoint: $SmokeHttpUrl"
  $deadline = (Get-Date).AddMinutes(5)
  do {
    try {
      $response = Invoke-WebRequest -Uri $SmokeHttpUrl -UseBasicParsing -TimeoutSec 10
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
        break
      }
    } catch {
      Start-Sleep -Seconds 10
    }
  } while ((Get-Date) -lt $deadline)

  if ((Get-Date) -ge $deadline) {
    throw "Timed out waiting for $SmokeHttpUrl"
  }
}

if ($SmokeCommand) {
  Write-Host "Running app smoke command: $SmokeCommand"
  $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $SmokeCommand) -Wait -PassThru -NoNewWindow
  if ($process.ExitCode -ne 0) {
    throw "App smoke command exited with code $($process.ExitCode)"
  }
}

# If no payload-specific command is provided, this still validates the WSL2 and
# Docker Desktop control plane that the packaged app depends on.
