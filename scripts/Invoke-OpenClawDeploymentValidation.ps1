[CmdletBinding()]
param(
    [string]$OpenClawUri,
    [string]$OllamaUri = 'http://127.0.0.1:11434/',
    [string]$WeixinMarkerPath,
    [string[]]$RequiredContainers = @(),
    [int]$TimeoutSeconds = 15,
    [switch]$AsJson
)

. $PSScriptRoot/OpenClaw.DeploymentValidation.ps1

$result = Invoke-OpenClawDeploymentValidation -OpenClawUri $OpenClawUri -OllamaUri $OllamaUri -WeixinMarkerPath $WeixinMarkerPath -RequiredContainers $RequiredContainers -TimeoutSeconds $TimeoutSeconds

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result.Checks | Format-Table -AutoSize Name, Status, Message
    ''
    "Passed:  {0}" -f $result.Passed
    "Failed:  {0}" -f $result.Failed
    "Skipped: {0}" -f $result.Skipped
}

if (-not $result.Succeeded) {
    exit 1
}

exit 0
