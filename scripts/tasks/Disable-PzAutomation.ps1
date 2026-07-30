param(
    [switch]$StopAdminPanel,
    [switch]$StopServer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig

& (Join-Path $PSScriptRoot 'Unregister-PzScheduledTasks.ps1')

if ($StopAdminPanel) {
    $adminPidPath = Join-Path $config.StateDir 'admin-panel.pid'
    if (Test-Path -LiteralPath $adminPidPath) {
        $pidText = Get-Content -LiteralPath $adminPidPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pidText -match '^\d+$') {
            Stop-Process -Id ([int]$pidText) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $adminPidPath -Force -ErrorAction SilentlyContinue
    }
}

if ($StopServer) {
    & (Join-Path $PSScriptRoot '..\ops\Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
}

Write-PzLog -Config $config -Message 'Automation disabled.' -Name 'tasks'

