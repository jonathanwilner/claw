BeforeAll {
    . $PSScriptRoot/../scripts/OpenClaw.DeploymentValidation.ps1
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
}
