Describe 'Dependency update controller configuration' {
    It 'uses only the dedicated dependency-update App credentials' {
        $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath
        $controllerWorkflowPath = Join-Path $repositoryRoot '.github/workflows/update-powershell-dependencies.yml'
        $workflow = Get-Content -LiteralPath $controllerWorkflowPath -Raw

        $workflow | Should -Match 'vars\.DEPENDENCY_UPDATE_APP_CLIENT_ID'
        $workflow | Should -Match 'secrets\.DEPENDENCY_UPDATE_APP_PRIVATE_KEY'
        $workflow | Should -Not -Match 'ATLASSIANPS_RELEASE_APP_(?:CLIENT_ID|PRIVATE_KEY)'
    }

    It 'gives every configured target exactly one explicit release-intent label' {
        $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).ProviderPath
        $targetsPath = Join-Path $repositoryRoot 'dependency-updates/targets.json'
        $targets = @(Get-Content -LiteralPath $targetsPath -Raw | ConvertFrom-Json)

        foreach ($target in $targets) {
            $releaseLabels = @([String]$target.labels -split ',' |
                    ForEach-Object Trim |
                    Where-Object { $_ -match '^release:(?:none|patch|minor|major)$' })

            $releaseLabels | Should -HaveCount 1 -Because "$($target.repository) needs explicit release intent"
        }
    }
}
