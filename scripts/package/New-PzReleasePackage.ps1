param(
    [string]$OutputDir = 'C:\src\project-zomboid-server\dist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $OutputDir "pz-manager-${stamp}"
$zip = "${stage}.zip"

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$items = @('.editorconfig', '.github', '.gitignore', 'CONTRIBUTING.md', 'INSTALL-GUI.cmd', 'INSTALL-GUI.ps1', 'LICENSE', 'NOTICE', 'Open-AdminPanel.ps1', 'README.md', 'RUN-SETUP-WIZARD.ps1', 'SECURITY.md', 'Setup-Wizard.ps1', 'START-HERE.ps1', 'Stop-AdminPanel.ps1', 'SUPPORT.md', 'config', 'docs', 'scripts', 'templates', 'tools', 'tests')
foreach ($item in $items) {
    $source = Join-Path $projectRoot $item
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
    }
}

Remove-Item -LiteralPath (Join-Path $stage 'config\server.env') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $stage 'config\mods.json') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $stage '.git') -Recurse -Force -ErrorAction SilentlyContinue

Set-Content -LiteralPath (Join-Path $stage 'INSTALL-FIRST.ps1') -Encoding ASCII -Value @'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "INSTALL-GUI.ps1")
'@

Set-Content -LiteralPath (Join-Path $stage 'INSTALL-FIRST.cmd') -Encoding ASCII -Value @'
@echo off
setlocal
cd /d "%~dp0"
call "%~dp0INSTALL-GUI.cmd"
'@

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force

[pscustomobject]@{
    Package = $zip
    Staging = $stage
}
