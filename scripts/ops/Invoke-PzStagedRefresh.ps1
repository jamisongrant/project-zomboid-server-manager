param(
    [switch]$SkipPrepare,
    [switch]$SkipWarning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

$stageServerDir = Join-Path $config.StagingDir 'server-next'
$rollbackServerDir = Join-Path $config.StagingDir 'server-rollback'
$failedServerDir = Join-Path $config.StagingDir ("server-failed-{0}" -f (Get-PzTimestamp))
$manifestPath = Join-Path $config.StagingDir 'staged-update.json'
$wasRunning = $null -ne (Get-PzServerProcess -Config $config)

Enter-PzMaintenance -Config $config -Reason 'staged-refresh'
try {
    if (-not $SkipPrepare) {
        & (Join-Path $PSScriptRoot 'Prepare-PzStagedUpdate.ps1')
    }

    if (-not (Test-Path -LiteralPath $stageServerDir)) {
        throw "No staged server update found at ${stageServerDir}. Run Prepare-PzStagedUpdate.ps1 first."
    }

    if ($wasRunning -and -not $SkipWarning -and $config.ModWarningSeconds -gt 0) {
        Send-PzServerMessage -Config $config -Message "Server staged update in $($config.ModWarningSeconds) seconds. The server will restart automatically."
        Start-Sleep -Seconds $config.ModWarningSeconds
    }

    if ($wasRunning) {
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    }

    & (Join-Path $PSScriptRoot 'Backup-PzSaves.ps1')

    if (Test-Path -LiteralPath $rollbackServerDir) {
        Remove-Item -LiteralPath $rollbackServerDir -Recurse -Force
    }

    Write-PzLog -Config $config -Message "Swapping staged server into place." -Name 'staged-update'
    if (Test-Path -LiteralPath $config.ServerDir) {
        Move-Item -LiteralPath $config.ServerDir -Destination $rollbackServerDir
    }
    Move-Item -LiteralPath $stageServerDir -Destination $config.ServerDir

    try {
        if ($wasRunning) {
            & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
            Start-Sleep -Seconds 15
            & (Join-Path $PSScriptRoot 'Watchdog-PzServer.ps1')
        }
        if (Test-Path -LiteralPath $manifestPath) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
        Write-PzLog -Config $config -Message "Staged refresh completed successfully. Rollback copy retained at ${rollbackServerDir}." -Name 'staged-update'
    } catch {
        Write-PzLog -Config $config -Message "Staged refresh health check failed; rolling back. $($_.Exception.Message)" -Name 'staged-update' -Level 'ERROR'
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 45 -Force
        if (Test-Path -LiteralPath $config.ServerDir) {
            Move-Item -LiteralPath $config.ServerDir -Destination $failedServerDir
        }
        if (Test-Path -LiteralPath $rollbackServerDir) {
            Move-Item -LiteralPath $rollbackServerDir -Destination $config.ServerDir
        }
        if ($wasRunning) {
            & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
        }
        throw
    }
} finally {
    Exit-PzMaintenance -Config $config
}
