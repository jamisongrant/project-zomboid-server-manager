param(
    [switch]$SkipWarning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$wasRunning = $null -ne (Get-PzServerProcess -Config $config)

Enter-PzMaintenance -Config $config -Reason 'mod-refresh'
try {
    if ($wasRunning -and -not $SkipWarning -and $config.ModWarningSeconds -gt 0) {
        Send-PzServerMessage -Config $config -Message "Server mod refresh in $($config.ModWarningSeconds) seconds. The server will restart automatically."
        Start-Sleep -Seconds $config.ModWarningSeconds
    }

    if ($wasRunning) {
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    }

    & (Join-Path $PSScriptRoot 'Backup-PzSaves.ps1')
    & (Join-Path $PSScriptRoot 'Update-PzMods.ps1')

    if ($wasRunning) {
        & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
        Start-Sleep -Seconds 15
        & (Join-Path $PSScriptRoot 'Watchdog-PzServer.ps1')
    }
} finally {
    Exit-PzMaintenance -Config $config
}

