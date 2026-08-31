#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7'; MaximumVersion = '5.999' }

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '../Update-RepositoryDependencies.ps1'
    . $scriptPath -RepositoryPath $TestDrive -ModuleName TestModule

    function New-TestRepository {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'This helper only creates isolated Pester TestDrive fixtures.'
        )]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String]$Path
        )

        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Tools') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'TestModule') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $Path '.github/workflows') -Force

        @"
@(
    @{ ModuleName = 'AtlassianPS.Standards'; RequiredVersion = '0.3.1'; MaximumVersion = '0.3.1' }
)
"@ | Set-Content -LiteralPath (Join-Path $Path 'Tools/build.requirements.psd1')
        "@{ RequiredModules = @() }" |
            Set-Content -LiteralPath (Join-Path $Path 'TestModule/TestModule.psd1')
    }
}

Describe 'Update-RepositoryDependencies' {
    It 'fails before mutation when required dependency files are missing' {
        $repositoryPath = Join-Path $TestDrive 'missing-files'
        $null = New-Item -ItemType Directory -Path $repositoryPath

        { Invoke-RepositoryDependencyUpdate -RepositoryPath $repositoryPath -ModuleName TestModule -StandardsVersion '0.3.1' } |
            Should -Throw '*Required dependency file was not found*'
    }

    It 'does not initialize dependency tooling under WhatIf' {
        $repositoryPath = Join-Path $TestDrive 'what-if'
        New-TestRepository -Path $repositoryPath
        Mock Get-PSRepository { throw 'Should not be called' }

        Invoke-RepositoryDependencyUpdate `
            -RepositoryPath $repositoryPath `
            -ModuleName TestModule `
            -StandardsVersion '0.3.1' `
            -WhatIf

        Should -Invoke Get-PSRepository -Times 0
    }

    It 'uses the default Standards version from the script entry point' {
        $repositoryPath = Join-Path $TestDrive 'entry-point'
        New-TestRepository -Path $repositoryPath

        {
            & $scriptPath -RepositoryPath $repositoryPath -ModuleName TestModule -WhatIf
        } | Should -Not -Throw
    }

    It 'passes the declared files to Standards without enabling major upgrades' {
        $repositoryPath = Join-Path $TestDrive 'delegation'
        New-TestRepository -Path $repositoryPath
        Set-Content `
            -LiteralPath (Join-Path $repositoryPath '.github/workflows/ci.yml') `
            -Value 'uses: AtlassianPS/AtlassianPS.Standards/.github/workflows/module_ci.yml@0000000000000000000000000000000000000000 # v0.3.0'

        Mock Get-PSRepository { [PSCustomObject]@{ InstallationPolicy = 'Trusted' } }
        Mock Get-Module { [PSCustomObject]@{ Version = [Version]'0.3.1' } }
        Mock Import-Module
        Mock Invoke-StandardsDependencyUpdate { [PSCustomObject]@{ Changed = $true } }
        Mock Invoke-RestMethod { [PSCustomObject]@{ sha = 'a' * 40 } }

        $result = Invoke-RepositoryDependencyUpdate `
            -RepositoryPath $repositoryPath `
            -ModuleName TestModule `
            -StandardsVersion '0.3.1'

        $result.Changed | Should -BeTrue
        Should -Invoke Invoke-StandardsDependencyUpdate -Times 1 -ParameterFilter {
            $Parameters.BuildRequirementsPath -eq (Join-Path $repositoryPath 'Tools/build.requirements.psd1') -and
            $Parameters.ManifestPath -eq (Join-Path $repositoryPath 'TestModule/TestModule.psd1') -and
            -not $Parameters.ContainsKey('AllowMajorVersionUpgrade')
        }
    }

    It 'updates yml and yaml references while preserving encoding and newlines' {
        $repositoryPath = Join-Path $TestDrive 'workflow-files'
        New-TestRepository -Path $repositoryPath
        $workflowRoot = Join-Path $repositoryPath '.github/workflows'
        $oldReference = 'uses: AtlassianPS/AtlassianPS.Standards/.github/workflows/module_ci.yml@0000000000000000000000000000000000000000 # v0.3.0'
        $newSha = 'b' * 40

        $bomPath = Join-Path $workflowRoot 'ci.yml'
        $plainPath = Join-Path $workflowRoot 'release.yaml'
        [System.IO.File]::WriteAllText($bomPath, "$oldReference`r`n", [System.Text.UTF8Encoding]::new($true))
        [System.IO.File]::WriteAllText($plainPath, "$oldReference`n", [System.Text.UTF8Encoding]::new($false))
        Mock Invoke-RestMethod { [PSCustomObject]@{ sha = $newSha } }

        Sync-StandardsWorkflowReference -ProjectRoot $repositoryPath -Version '0.3.1'

        $bomBytes = [System.IO.File]::ReadAllBytes($bomPath)
        $bomBytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        [System.Text.Encoding]::UTF8.GetString($bomBytes) | Should -Match "# v0\.3\.1`r`n$"
        (Get-Content -LiteralPath $plainPath -Raw) | Should -Match "# v0\.3\.1`n$"
        [System.IO.File]::ReadAllBytes($plainPath)[0] | Should -Not -Be 0xEF
    }

    It 'fails when GitHub does not return a commit SHA' {
        $repositoryPath = Join-Path $TestDrive 'invalid-sha'
        New-TestRepository -Path $repositoryPath
        Mock Invoke-RestMethod { [PSCustomObject]@{ sha = 'invalid' } }

        { Sync-StandardsWorkflowReference -ProjectRoot $repositoryPath -Version '0.3.1' } |
            Should -Throw '*valid commit*'
    }
}
