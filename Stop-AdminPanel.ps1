Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pidPath = 'C:\pz\state\admin-panel.pid'
if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Host 'Admin panel PID file not found. It may already be stopped.'
    exit 0
}

$pidText = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pidText -match '^\d+$') {
    Stop-Process -Id ([int]$pidText) -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
Write-Host 'Admin panel stopped.'

