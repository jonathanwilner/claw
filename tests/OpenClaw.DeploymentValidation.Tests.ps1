BeforeAll {
    . $PSScriptRoot/../scripts/OpenClaw.DeploymentValidation.ps1
    . $PSScriptRoot/../scripts/OpenClaw.WeixinPackaging.ps1
}

Describe 'OpenClaw deployment validation helpers' {
    It 'creates standardized validation checks' {
        $check = New-OpenClawValidationCheck -Name 'sample' -Status 'Passed' -Message 'ok' -Data 42

        $check.Name | Should -Be 'sample'
        $check.Status | Should -Be 'Passed'
        $check.Passed | Should -BeTrue
        $check.Skipped | Should -BeFalse
        $check.Data | Should -Be 42
    }

    It 'parses wsl -l -v output into structured records' {
        $sample = @(
            '  NAME            STATE           VERSION'
            '* Ubuntu-24.04    Running         2'
            '  docker-desktop   Stopped         2'
        )

        $items = ConvertFrom-WslListOutput -Lines $sample

        $items.Count | Should -Be 2
        $items[0].Name | Should -Be 'Ubuntu-24.04'
        $items[0].IsDefault | Should -BeTrue
        $items[0].Version | Should -Be 2
        $items[1].Name | Should -Be 'docker-desktop'
        $items[1].Version | Should -Be 2
    }

    It 'summarizes a validation run without throwing' {
        $result = Invoke-OpenClawDeploymentValidation -TimeoutSeconds 1 -OllamaUri ''

        $result | Should -Not -BeNullOrEmpty
        $result.Checks | Should -Not -BeNullOrEmpty
        $result.Passed | Should -BeGreaterOrEqual 0
        $result.Failed | Should -BeGreaterOrEqual 0
        $result.Succeeded | Should -BeOfType 'System.Boolean'
    }

    It 'resolves the default Weixin npm install spec when no tarball is staged' {
        $workspace = Join-Path $TestDrive 'workspace'
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null

        $resolved = Resolve-OpenClawWeixinInstallSpec -WorkspaceDirectory $workspace

        $resolved.SourceKind | Should -Be 'npm'
        $resolved.InstallSpec | Should -Be '@tencent-weixin/openclaw-weixin'
        $resolved.HostPath | Should -BeNullOrEmpty
    }

    It 'stages a Weixin tarball into the OpenClaw workspace when provided' {
        $workspace = Join-Path $TestDrive 'workspace'
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        $tarball = Join-Path $TestDrive 'openclaw-weixin-1.0.3.tgz'
        Set-Content -LiteralPath $tarball -Value 'dummy' -Encoding ascii

        $resolved = Resolve-OpenClawWeixinInstallSpec -WorkspaceDirectory $workspace -WeixinPluginTarballPath $tarball

        $resolved.SourceKind | Should -Be 'tarball'
        $resolved.InstallSpec | Should -Be '/home/node/.openclaw/workspace/plugins/openclaw-weixin-1.0.3.tgz'
        Test-Path -LiteralPath $resolved.HostPath | Should -BeTrue
    }

    It 'passes validation when the Weixin packaging marker is present' {
        $markerPath = Join-Path $TestDrive 'openclaw-weixin-packaging.json'
        $marker = New-OpenClawWeixinMarker -InstallSpec '@tencent-weixin/openclaw-weixin' -SourceKind 'npm'
        $marker | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $markerPath -Encoding ascii

        $check = Test-WeixinPackagingMarker -MarkerPath $markerPath

        $check.Status | Should -Be 'Passed'
        $check.Data.pluginId | Should -Be 'openclaw-weixin'
    }
}
