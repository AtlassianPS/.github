#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$RepositoryPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [String]$ModuleName,

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [String]$StandardsVersion = '0.3.1'
)

$ErrorActionPreference = 'Stop'

function Get-FileTextState {
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        $text = $text.Substring(1)
    }

    [PSCustomObject]@{
        Path    = $resolvedPath
        Text    = $text
        HasBom  = $hasBom
        NewLine = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    }
}

function Set-FileTextState {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'The parent script gates all writes with ShouldProcess.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$State,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [String]$Text
    )

    $normalizedText = $Text -replace "`r?`n", $State.NewLine
    if (-not $normalizedText.EndsWith($State.NewLine)) {
        $normalizedText += $State.NewLine
    }

    $encoding = [System.Text.UTF8Encoding]::new($State.HasBom)
    [System.IO.File]::WriteAllText($State.Path, $normalizedText, $encoding)
}

function Sync-StandardsWorkflowReference {
    param(
        [Parameter(Mandatory)]
        [String]$ProjectRoot,

        [Parameter(Mandatory)]
        [String]$Version
    )

    $headers = @{ Accept = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
    }

    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/AtlassianPS/AtlassianPS.Standards/commits/v$Version" `
        -Headers $headers `
        -ErrorAction Stop
    $commit = [String]$release.sha
    if ($commit -notmatch '^[0-9a-f]{40}$') {
        throw "GitHub did not return a valid commit for AtlassianPS.Standards v$Version."
    }

    $workflowRoot = Join-Path $ProjectRoot '.github/workflows'
    $workflows = Get-ChildItem -LiteralPath $workflowRoot -File -ErrorAction SilentlyContinue |
        Where-Object Extension -In @('.yml', '.yaml')
    foreach ($workflow in $workflows) {
        $state = Get-FileTextState -Path $workflow.FullName
        $updatedText = [regex]::Replace(
            $state.Text,
            '(?<prefix>AtlassianPS/AtlassianPS\.Standards/\.github/(?:actions/[^@\s]+|workflows/(?:module_ci|module_release)\.yml)@)[0-9a-f]{40}(?<suffix>\s+#\s+v)\d+\.\d+\.\d+',
            ('${prefix}' + $commit + '${suffix}' + $Version)
        )

        if ($updatedText -ne $state.Text) {
            Set-FileTextState -State $state -Text $updatedText
        }
    }
}

function Invoke-StandardsDependencyUpdate {
    param(
        [Parameter(Mandatory)]
        [Hashtable]$Parameters
    )

    AtlassianPS.Standards\Update-AtlassianPSDependencyReference @Parameters
}

function Invoke-RepositoryDependencyUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [String]$RepositoryPath,

        [Parameter(Mandatory)]
        [String]$ModuleName,

        [Parameter(Mandatory)]
        [String]$StandardsVersion
    )

    $resolvedRepositoryPath = (Resolve-Path -LiteralPath $RepositoryPath).ProviderPath
    $buildRequirementsPath = Join-Path $resolvedRepositoryPath 'Tools/build.requirements.psd1'
    $manifestPath = Join-Path $resolvedRepositoryPath "$ModuleName/$ModuleName.psd1"

    foreach ($requiredPath in @($buildRequirementsPath, $manifestPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required dependency file was not found: '$requiredPath'."
        }
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedRepositoryPath, 'Update PowerShell dependency references')) {
        return
    }

    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (-not $gallery) {
        Register-PSRepository -Default -ErrorAction Stop
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction Stop
    }

    if ($gallery.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
    }

    $installedStandards = Get-Module -ListAvailable -Name AtlassianPS.Standards |
        Where-Object Version -EQ ([Version]$StandardsVersion) |
        Select-Object -First 1

    if (-not $installedStandards) {
        Install-Module `
            -Name AtlassianPS.Standards `
            -RequiredVersion $StandardsVersion `
            -Repository PSGallery `
            -Scope CurrentUser `
            -AllowClobber `
            -Force `
            -ErrorAction Stop
    }

    Import-Module AtlassianPS.Standards -RequiredVersion $StandardsVersion -Force -ErrorAction Stop

    $updateParameters = @{
        BuildRequirementsPath = $buildRequirementsPath
        ManifestPath          = $manifestPath
        ErrorAction           = 'Stop'
    }

    $result = Invoke-StandardsDependencyUpdate -Parameters $updateParameters

    $requirements = Import-PowerShellDataFile -LiteralPath $buildRequirementsPath
    $standardsRequirement = $requirements |
        Where-Object ModuleName -EQ 'AtlassianPS.Standards' |
        Select-Object -First 1
    $updatedStandardsVersion = [String]$standardsRequirement.RequiredVersion
    if (-not $updatedStandardsVersion) {
        throw "AtlassianPS.Standards is missing from '$buildRequirementsPath'."
    }

    Sync-StandardsWorkflowReference `
        -ProjectRoot $resolvedRepositoryPath `
        -Version $updatedStandardsVersion

    $result
}

if ($MyInvocation.InvocationName -ne '.') {
    $invokeParameters = @{} + $PSBoundParameters
    $invokeParameters.StandardsVersion = $StandardsVersion
    Invoke-RepositoryDependencyUpdate @invokeParameters
}
