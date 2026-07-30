param(
    [switch]$Restart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

$rollbackServerDir = Join-Path $config.StagingDir 'server-rollback'
$currentToReplace = Join-Path $config.StagingDir ("server-replaced-{0}" -f (Get-PzTimestamp))
$wasRunning = $null -ne (Get-PzServerProcess -Config $config)

if (-not (Test-Path -LiteralPath $rollbackServerDir)) {
    throw "No rollback server directory found at ${rollbackServerDir}."
}

Enter-PzMaintenance -Config $config -Reason 'staged-rollback'
try {
    if ($wasRunning) {
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    }

    & (Join-Path $PSScriptRoot 'Backup-PzSaves.ps1')

    if (Test-Path -LiteralPath $config.ServerDir) {
        Move-Item -LiteralPath $config.ServerDir -Destination $currentToReplace
    }
    Move-Item -LiteralPath $rollbackServerDir -Destination $config.ServerDir

    if ($Restart -or $wasRunning) {
        & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
    }

    Write-PzLog -Config $config -Message "Rollback restored from ${rollbackServerDir}. Replaced copy kept at ${currentToReplace}." -Name 'staged-update'
} finally {
    Exit-PzMaintenance -Config $config
}
