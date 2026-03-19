param(
  [string]$OutputDirectory = "$env:ProgramData\ClawValidation\logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Write-Log {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Text)
  $path = Join-Path $OutputDirectory $Name
  $Text | Set-Content -Path $path -Encoding utf8
}

$capture = @{}

foreach ($cmd in @(
  @{ Name = 'wsl-status.txt'; File = 'wsl.exe'; Args = @('--status') },
  @{ Name = 'wsl-list.txt'; File = 'wsl.exe'; Args = @('--list', '--verbose') },
  @{ Name = 'docker-version.txt'; File = 'docker.exe'; Args = @('version') },
  @{ Name = 'docker-info.txt'; File = 'docker.exe'; Args = @('info') }
) ) {
  if (Get-Command $cmd.File -ErrorAction SilentlyContinue) {
    $cmdArgs = $cmd.Args
    $capture[$cmd.Name] = (& $cmd.File @cmdArgs 2>&1 | Out-String)
  }
}

foreach ($entry in $capture.GetEnumerator()) {
  Write-Log -Name $entry.Key -Text $entry.Value
}

Write-Log -Name 'summary.txt' -Text @"
Captured: $(($capture.Keys | Sort-Object) -join ', ')
Timestamp: $(Get-Date -Format o)
"@

# This file stays runnable from either the guest itself or a Hyper-V host using
# PowerShell Direct. It is intentionally boring: capture first, interpret later.
