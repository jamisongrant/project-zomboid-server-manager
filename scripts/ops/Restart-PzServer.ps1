param(
    [switch]$BackupFirst
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Enter-PzMaintenance -Config $config -Reason 'restart'
try {
    & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    if ($BackupFirst) {
        & (Join-Path $PSScriptRoot 'Backup-PzSaves.ps1')
    }
    & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
} finally {
    Exit-PzMaintenance -Config $config
}
