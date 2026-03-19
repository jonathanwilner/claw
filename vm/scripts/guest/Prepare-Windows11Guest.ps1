Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Enable-Feature {
  param([Parameter(Mandatory)][string]$Name)

  $state = (dism.exe /online /Get-FeatureInfo /FeatureName:$Name 2>$null | Out-String)
  if ($state -match 'State : Enabled') {
    Write-Host "$Name already enabled"
    return
  }

  Write-Host "Enabling $Name"
  dism.exe /online /Enable-Feature /FeatureName:$Name /All /NoRestart | Out-Host
}

Write-Host "Preparing the Windows guest for WSL2 + Docker Desktop validation"

Enable-Feature -Name 'Microsoft-Windows-Subsystem-Linux'
Enable-Feature -Name 'VirtualMachinePlatform'

if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
  try {
    wsl.exe --set-default-version 2 | Out-Host
  } catch {
    Write-Warning "wsl.exe default-version setup failed. Re-run after reboot if the Windows build exposes WSL later in the boot flow."
  }
}

# This script intentionally stops short of installing a distribution. The
# packaged app harness owns that choice so the validation VM can stay generic.
