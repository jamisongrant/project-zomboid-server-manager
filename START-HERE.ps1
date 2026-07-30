Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

Write-Host ''
Write-Host 'Project Zomboid Server Manager'
Write-Host '================================'
Write-Host ''

if ($null -eq (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    Write-Host 'Node.js 20 or newer is required for the admin panel.'
    Write-Host 'Install Node.js, then run START-HERE.ps1 again.'
    Write-Host 'Download: https://nodejs.org/'
    exit 1
}

Write-Host 'Running setup check...'
& .\scripts\install\Test-PzSetup.ps1
Write-Host ''

$configPath = Join-Path $PSScriptRoot 'config\server.env'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host 'First run detected. Opening browser setup wizard.'
    .\Open-AdminPanel.ps1
    Start-Sleep -Seconds 1
    Start-Process 'http://127.0.0.1:8787/#wizard'
    exit 0
} else {
    Write-Host 'Existing config found. Starting admin panel.'
    .\Open-AdminPanel.ps1
}

Write-Host ''
Write-Host 'Admin panel: http://127.0.0.1:8787'
Start-Process 'http://127.0.0.1:8787'
