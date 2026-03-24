[CmdletBinding()]
param()

Set-StrictMode -Version Latest

function Resolve-OpenClawWeixinInstallSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceDirectory,

        [string]$WeixinPluginTarballPath,

        [string]$DefaultNpmSpec = '@tencent-weixin/openclaw-weixin'
    )

    if (-not $WeixinPluginTarballPath) {
        return [pscustomobject]@{
            SourceKind    = 'npm'
            InstallSpec   = $DefaultNpmSpec
            HostPath      = $null
            ContainerPath = $null
        }
    }

    if (-not (Test-Path -LiteralPath $WeixinPluginTarballPath)) {
        throw "Weixin plugin tarball not found: $WeixinPluginTarballPath"
    }

    $pluginsDirectory = Join-Path $WorkspaceDirectory 'plugins'
    if (-not (Test-Path -LiteralPath $pluginsDirectory)) {
        New-Item -ItemType Directory -Path $pluginsDirectory -Force | Out-Null
    }

    $fileName = [IO.Path]::GetFileName($WeixinPluginTarballPath)
    $stagedPath = Join-Path $pluginsDirectory $fileName
    Copy-Item -LiteralPath $WeixinPluginTarballPath -Destination $stagedPath -Force

    [pscustomobject]@{
        SourceKind    = 'tarball'
        InstallSpec   = "/home/node/.openclaw/workspace/plugins/$fileName"
        HostPath      = $stagedPath
        ContainerPath = "/home/node/.openclaw/workspace/plugins/$fileName"
    }
}

function Get-OpenClawWeixinMarkerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigDirectory
    )

    Join-Path $ConfigDirectory 'openclaw-weixin-packaging.json'
}

function New-OpenClawWeixinMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallSpec,

        [Parameter(Mandatory)]
        [string]$SourceKind,

        [switch]$QrLoginRequested
    )

    [pscustomobject]@{
        pluginId         = 'openclaw-weixin'
        npmSpec          = '@tencent-weixin/openclaw-weixin'
        installSpec      = $InstallSpec
        sourceKind       = $SourceKind
        qrLoginRequested = [bool]$QrLoginRequested
        configuredAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
    }
}
