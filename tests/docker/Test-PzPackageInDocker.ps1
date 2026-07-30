param(
    [string]$PackagePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$dockerDir = Resolve-Path $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    $latest = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'dist') -Filter 'pz-manager-*.zip' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        throw 'No package found in dist. Run scripts\package\New-PzReleasePackage.ps1 first.'
    }
    $PackagePath = $latest.FullName
}

$resolvedPackage = Resolve-Path -LiteralPath $PackagePath
Copy-Item -LiteralPath $resolvedPackage.Path -Destination (Join-Path $dockerDir 'package.zip') -Force

function Invoke-CheckedDocker {
    param(
        [string[]]$Arguments
    )

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($Arguments -join ' ') failed with exit code ${LASTEXITCODE}."
    }
}

try {
    Invoke-CheckedDocker -Arguments @('build', '-t', 'pz-manager-package-smoke', $dockerDir)
    Invoke-CheckedDocker -Arguments @('run', '--rm', 'pz-manager-package-smoke')
} finally {
    Remove-Item -LiteralPath (Join-Path $dockerDir 'package.zip') -Force -ErrorAction SilentlyContinue
}
