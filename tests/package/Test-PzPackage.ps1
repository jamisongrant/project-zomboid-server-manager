param(
    [string]$PackagePath = '',
    [switch]$KeepExtracted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

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
$extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pz-manager-package-smoke-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

try {
    Expand-Archive -LiteralPath $resolvedPackage.Path -DestinationPath $extractRoot -Force
    Set-Location $extractRoot

    $required = @(
        'RUN-SETUP-WIZARD.ps1',
        'START-HERE.ps1',
        'Setup-Wizard.ps1',
        'Open-AdminPanel.ps1',
        'Stop-AdminPanel.ps1',
        'INSTALL-FIRST.ps1',
        'LICENSE',
        'NOTICE',
        'README.md',
        'SECURITY.md',
        'SUPPORT.md',
        'CONTRIBUTING.md',
        'docs\STARTUP-GUIDE.md',
        'docs\friend-install.md',
        'scripts\install\Install-PzManager.ps1',
        'scripts\tasks\Disable-PzAutomation.ps1',
        'tools\admin-panel\server.js',
        'tools\admin-panel\public\app.js',
        'tests\Run-Regression.ps1'
    )

    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing required packaged file: $path"
        }
    }

    foreach ($secret in @('config\server.env', 'config\mods.json')) {
        if (Test-Path -LiteralPath $secret) {
            throw "Package must not include $secret."
        }
    }

    & .\tests\Run-Regression.ps1 -SkipLiveApi
    if (-not $?) {
        throw 'Extracted package regression suite failed.'
    }

    Write-Host "Windows package smoke test passed: $($resolvedPackage.Path)"
    if ($KeepExtracted) {
        Write-Host "Extracted package kept at: $extractRoot"
    }
} finally {
    Set-Location $projectRoot
    if (-not $KeepExtracted) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
