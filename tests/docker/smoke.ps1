Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$extract = '/workspace/pkg'
New-Item -ItemType Directory -Path $extract -Force | Out-Null
Expand-Archive -LiteralPath '/workspace/package.zip' -DestinationPath $extract -Force
Set-Location $extract

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
    'docs/STARTUP-GUIDE.md',
    'scripts/install/Install-PzManager.ps1',
    'scripts/tasks/Disable-PzAutomation.ps1',
    'tools/admin-panel/server.js',
    'tools/admin-panel/public/app.js',
    'tests/Run-Regression.ps1'
)

foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required packaged file: $path"
    }
}

if (Test-Path -LiteralPath 'config/server.env') {
    throw 'Package must not include config/server.env'
}

if (Test-Path -LiteralPath 'config/mods.json') {
    throw 'Package must not include config/mods.json'
}

node --check tools/admin-panel/server.js
if ($LASTEXITCODE -ne 0) {
    throw 'Node backend syntax check failed.'
}

node --check tools/admin-panel/public/app.js
if ($LASTEXITCODE -ne 0) {
    throw 'Node frontend syntax check failed.'
}

./tests/Run-Regression.ps1 -SkipLiveApi
if (-not $?) {
    throw 'Packaged regression suite failed.'
}

Write-Host 'Docker package smoke test passed.'
