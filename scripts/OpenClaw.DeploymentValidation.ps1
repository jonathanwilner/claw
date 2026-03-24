[CmdletBinding()]
param()

Set-StrictMode -Version Latest

function New-OpenClawValidationCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Passed', 'Failed', 'Skipped')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [object]$Data
    )

    [pscustomobject]@{
        Name    = $Name
        Status  = $Status
        Passed  = $Status -eq 'Passed'
        Skipped = $Status -eq 'Skipped'
        Message = $Message
        Data    = $Data
    }
}

function ConvertFrom-WslListOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    $items = foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) {
            continue
        }

        if ($trimmed -match '^(NAME|Windows Subsystem for Linux Distributions|The following is a list of valid distributions)') {
            continue
        }

        $parts = $trimmed -split '\s{2,}' | Where-Object { $_ }
        if ($parts.Count -lt 3) {
            continue
        }

        $nameToken = $parts[0].Trim()
        $isDefault = $nameToken.StartsWith('*')
        $name = $nameToken.TrimStart('*').Trim()
        $state = $parts[1].Trim()
        $version = 0
        [void][int]::TryParse($parts[2].Trim(), [ref]$version)

        [pscustomobject]@{
            Name      = $name
            State     = $state
            Version   = $version
            IsDefault = $isDefault
        }
    }

    if ($null -eq $items) {
        @()
    }
    else {
        @($items)
    }
}

function Get-WslDistributionInfo {
    [CmdletBinding()]
    param()

    $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wslCommand) {
        return [pscustomobject]@{
            Available      = $false
            RawOutput      = @()
            Distributions  = @()
            DefaultVersion2 = $false
        }
    }

    $wslPath = if ($wslCommand.Path) { $wslCommand.Path } else { $wslCommand.Source }
    $rawOutput = @(& $wslPath -l -v 2>&1)
    $distributions = ConvertFrom-WslListOutput -Lines $rawOutput
    $defaultVersion2 = $false
    if ($distributions.Count -gt 0) {
        $default = $distributions | Where-Object { $_.IsDefault } | Select-Object -First 1
        if ($default) {
            $defaultVersion2 = $default.Version -eq 2
        }
    }

    [pscustomobject]@{
        Available       = $true
        RawOutput       = $rawOutput
        Distributions   = $distributions
        DefaultVersion2  = $defaultVersion2
    }
}

function Test-Wsl2Availability {
    [CmdletBinding()]
    param()

    $info = Get-WslDistributionInfo
    if (-not $info.Available) {
        return New-OpenClawValidationCheck -Name 'WSL2 availability' -Status 'Failed' -Message 'wsl.exe was not found on PATH.' -Data $info
    }

    if ($info.Distributions.Count -eq 0) {
        return New-OpenClawValidationCheck -Name 'WSL2 availability' -Status 'Skipped' -Message 'WSL is available, but no installed distributions were reported by wsl.exe -l -v.' -Data $info
    }

    $version2 = @($info.Distributions | Where-Object { $_.Version -eq 2 })
    if ($version2.Count -gt 0) {
        $names = ($version2.Name -join ', ')
        return New-OpenClawValidationCheck -Name 'WSL2 availability' -Status 'Passed' -Message "WSL2 distributions detected: $names" -Data $info
    }

    $namesV1 = ($info.Distributions.Name -join ', ')
    return New-OpenClawValidationCheck -Name 'WSL2 availability' -Status 'Failed' -Message "WSL is installed, but only version 1 distributions were reported: $namesV1" -Data $info
}

function Test-CommandOnPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return New-OpenClawValidationCheck -Name "$CommandName on PATH" -Status 'Passed' -Message "$CommandName was found at $($command.Source)." -Data $command.Source
    }

    New-OpenClawValidationCheck -Name "$CommandName on PATH" -Status 'Failed' -Message "$CommandName was not found on PATH." -Data $null
}

function Get-DockerRunningContainerNames {
    [CmdletBinding()]
    param()

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCommand) {
        return @()
    }

    $dockerPath = if ($dockerCommand.Path) { $dockerCommand.Path } else { $dockerCommand.Source }
    $names = & $dockerPath ps --format '{{.Names}}' 2>$null
    @($names | Where-Object { $_ } | ForEach-Object { $_.Trim() })
}

function Test-DockerAvailability {
    [CmdletBinding()]
    param(
        [string[]]$RequiredContainers = @()
    )

    $dockerCommandCheck = Test-CommandOnPath -CommandName 'docker'
    if (-not $dockerCommandCheck.Passed) {
        return @($dockerCommandCheck)
    }

    $checks = @($dockerCommandCheck)

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    $dockerPath = if ($dockerCommand.Path) { $dockerCommand.Path } else { $dockerCommand.Source }
    $info = & $dockerPath info 2>&1
    if ($LASTEXITCODE -ne 0) {
        $checks += New-OpenClawValidationCheck -Name 'Docker daemon' -Status 'Failed' -Message "docker info failed: $($info -join [Environment]::NewLine)" -Data $info
        return @($checks)
    }

    $checks += New-OpenClawValidationCheck -Name 'Docker daemon' -Status 'Passed' -Message 'docker info succeeded.' -Data $info

    if ($RequiredContainers.Count -eq 0) {
        return @($checks)
    }

    $running = Get-DockerRunningContainerNames
    foreach ($container in $RequiredContainers) {
        if ($running -contains $container) {
            $checks += New-OpenClawValidationCheck -Name "Container $container running" -Status 'Passed' -Message "Container $container is running." -Data $running
        } else {
            $checks += New-OpenClawValidationCheck -Name "Container $container running" -Status 'Failed' -Message "Container $container was not found among running Docker containers." -Data $running
        }
    }

    @($checks)
}

function Test-HttpEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri,

        [int]$TimeoutSeconds = 15
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

    try {
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $contentType = if ($response.Content.Headers.ContentType) { $response.Content.Headers.ContentType.MediaType } else { $null }
        $summary = [pscustomobject]@{
            Uri         = $Uri.AbsoluteUri
            StatusCode   = [int]$response.StatusCode
            ReasonPhrase = $response.ReasonPhrase
            ContentType  = $contentType
            BodySnippet  = if ($body) { $body.Substring(0, [Math]::Min($body.Length, 256)) } else { '' }
        }

        if ($response.IsSuccessStatusCode) {
            return New-OpenClawValidationCheck -Name "HTTP endpoint $($Uri.AbsoluteUri)" -Status 'Passed' -Message "HTTP $($summary.StatusCode) from $($Uri.AbsoluteUri)." -Data $summary
        }

        return New-OpenClawValidationCheck -Name "HTTP endpoint $($Uri.AbsoluteUri)" -Status 'Failed' -Message "HTTP $($summary.StatusCode) from $($Uri.AbsoluteUri)." -Data $summary
    }
    catch {
        return New-OpenClawValidationCheck -Name "HTTP endpoint $($Uri.AbsoluteUri)" -Status 'Failed' -Message $_.Exception.Message -Data $null
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Test-WeixinPackagingMarker {
    [CmdletBinding()]
    param(
        [string]$MarkerPath
    )

    if (-not $MarkerPath) {
        return New-OpenClawValidationCheck -Name 'Weixin packaging marker' -Status 'Skipped' -Message 'No Weixin packaging marker path was provided.' -Data $null
    }

    if (-not (Test-Path -LiteralPath $MarkerPath)) {
        return New-OpenClawValidationCheck -Name 'Weixin packaging marker' -Status 'Skipped' -Message "Weixin packaging marker not found at $MarkerPath." -Data $null
    }

    try {
        $raw = Get-Content -LiteralPath $MarkerPath -Raw
        $data = $raw | ConvertFrom-Json
        if ($data.pluginId -eq 'openclaw-weixin') {
            return New-OpenClawValidationCheck -Name 'Weixin packaging marker' -Status 'Passed' -Message "Weixin packaging metadata found at $MarkerPath." -Data $data
        }

        return New-OpenClawValidationCheck -Name 'Weixin packaging marker' -Status 'Failed' -Message "Unexpected Weixin plugin marker contents at $MarkerPath." -Data $data
    }
    catch {
        return New-OpenClawValidationCheck -Name 'Weixin packaging marker' -Status 'Failed' -Message $_.Exception.Message -Data $null
    }
}

function Invoke-OpenClawDeploymentValidation {
    [CmdletBinding()]
    param(
        [string]$OpenClawUri,
        [string]$OllamaUri = 'http://127.0.0.1:11434/',
        [string]$WeixinMarkerPath,
        [string[]]$RequiredContainers = @(),
        [int]$TimeoutSeconds = 15
    )

    $checks = @()
    $checks += New-OpenClawValidationCheck -Name 'PowerShell runtime' -Status 'Passed' -Message "Running on $($PSVersionTable.PSVersion)." -Data $PSVersionTable
    $checks += Test-Wsl2Availability

    $dockerChecks = Test-DockerAvailability -RequiredContainers $RequiredContainers
    if ($dockerChecks.Count -gt 0) {
        $checks += $dockerChecks
    }

    if ($OllamaUri) {
        $checks += Test-HttpEndpoint -Uri ([uri]$OllamaUri) -TimeoutSeconds $TimeoutSeconds
    }

    if ($OpenClawUri) {
        $checks += Test-HttpEndpoint -Uri ([uri]$OpenClawUri) -TimeoutSeconds $TimeoutSeconds
    }

    $checks += Test-WeixinPackagingMarker -MarkerPath $WeixinMarkerPath

    $passed = @($checks | Where-Object { $_.Passed }).Count
    $failed = @($checks | Where-Object { $_.Status -eq 'Failed' }).Count
    $skipped = @($checks | Where-Object { $_.Status -eq 'Skipped' }).Count

    [pscustomobject]@{
        Timestamp = Get-Date
        Checks    = @($checks)
        Passed    = $passed
        Failed    = $failed
        Skipped   = $skipped
        Succeeded = $failed -eq 0
    }
}
