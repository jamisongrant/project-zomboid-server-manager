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
$progressName = 'staged-update-progress.json'
$startedAt = (Get-Date).ToString('o')

function Write-StagedRefreshProgress {
    param(
        [string]$Phase,
        [string]$Status,
        [bool]$SafeToApply = $false,
        [bool]$RestartRecommended = $false,
        [string]$RestartReason = '',
        [string]$LastError = ''
    )

    Write-PzStateJson -Config $config -Name $progressName -Data @{
        phase = $Phase
        status = $Status
        startedAt = $startedAt
        stageServerDir = $stageServerDir
        activeServerDir = $config.ServerDir
        rollbackServerDir = $rollbackServerDir
        failedServerDir = $failedServerDir
        wasRunning = $wasRunning
        safeToApply = $SafeToApply
        restartRecommended = $RestartRecommended
        restartReason = $RestartReason
        lastError = $LastError
    }
}

function Start-StagedServerWithRetry {
    param([int]$Attempts = 2)
    $timeoutSeconds = [int]$config.StartupTimeoutSeconds
    $pollSeconds = [int]$config.StartupPollSeconds
    for ($attempt = 1; $attempt -le $Attempts; $attempt += 1) {
        try {
            & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
            $elapsed = 0
            while ($elapsed -lt $timeoutSeconds) {
                $process = Get-PzServerProcess -Config $config
                if ($null -eq $process) {
                    throw 'Server process exited during startup.'
                }
                $ports = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object {
                    $_.OwningProcess -eq $process.Id -and $_.LocalPort -in @($config.Port, $config.UdpPort)
                } | Select-Object -ExpandProperty LocalPort -Unique)
                if ($ports -contains $config.Port -and $ports -contains $config.UdpPort) {
                    Write-PzLog -Config $config -Message "Server readiness verified: game ports $($config.Port) and $($config.UdpPort) are listening." -Name 'staged-update'
                    return
                }
                Write-StagedRefreshProgress -Phase 'starting-server' -Status "Server process is running; waiting for game ports ($elapsed/${timeoutSeconds}s)."
                Start-Sleep -Seconds $pollSeconds
                $elapsed += $pollSeconds
            }
            throw "Server did not bind game ports $($config.Port) and $($config.UdpPort) within ${timeoutSeconds} seconds."
        } catch {
            if ($attempt -ge $Attempts) { throw }
            Write-PzLog -Config $config -Message "Server start attempt ${attempt} failed; retrying once. $($_.Exception.Message)" -Name 'staged-update' -Level 'WARN'
            Start-Sleep -Seconds 5
        }
    }
}

Enter-PzMaintenance -Config $config -Reason 'staged-refresh'
try {
    Write-StagedRefreshProgress -Phase 'running' -Status 'Starting staged refresh workflow.'
    if (-not $SkipPrepare) {
        & (Join-Path $PSScriptRoot 'Prepare-PzStagedUpdate.ps1')
        $startedAt = (Get-Date).ToString('o')
        Write-StagedRefreshProgress -Phase 'running' -Status 'Staged server prepared; validating before swap.'
    }

    if (-not (Test-Path -LiteralPath $stageServerDir)) {
        throw "No staged server update found at ${stageServerDir}. Run Prepare-PzStagedUpdate.ps1 first."
    }

    if ($wasRunning -and -not $SkipWarning -and $config.ModWarningSeconds -gt 0) {
        Write-StagedRefreshProgress -Phase 'warning-players' -Status "Warning players for $($config.ModWarningSeconds) seconds before restart."
        Send-PzServerMessage -Config $config -Message "Server staged update in $($config.ModWarningSeconds) seconds. The server will restart automatically."
        Start-Sleep -Seconds $config.ModWarningSeconds
    }

    if ($wasRunning) {
        Write-StagedRefreshProgress -Phase 'stopping-server' -Status 'Stopping active server before staged swap.'
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    }

    Write-StagedRefreshProgress -Phase 'backup' -Status 'Backing up saves before staged swap.'
    & (Join-Path $PSScriptRoot 'Backup-PzSaves.ps1') -DeferCompression

    if (Test-Path -LiteralPath $rollbackServerDir) {
        Remove-Item -LiteralPath $rollbackServerDir -Recurse -Force
    }

    Write-PzLog -Config $config -Message "Swapping staged server into place." -Name 'staged-update'
    Write-StagedRefreshProgress -Phase 'swapping' -Status 'Swapping staged server into the active server directory.'
    if (Test-Path -LiteralPath $config.ServerDir) {
        Move-Item -LiteralPath $config.ServerDir -Destination $rollbackServerDir
    }
    Move-Item -LiteralPath $stageServerDir -Destination $config.ServerDir

    try {
        if ($wasRunning) {
            Write-StagedRefreshProgress -Phase 'starting-server' -Status 'Starting server after staged swap.'
            Start-StagedServerWithRetry
            Write-StagedRefreshProgress -Phase 'health-check' -Status 'Running watchdog health check after staged swap.'
            & (Join-Path $PSScriptRoot 'Watchdog-PzServer.ps1')
        }
        if (Test-Path -LiteralPath $manifestPath) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
        Write-StagedRefreshProgress -Phase 'succeeded' -Status 'Staged refresh completed successfully.' -RestartReason 'The staged version is active. No additional restart is recommended by this workflow.'
        Write-PzLog -Config $config -Message "Staged refresh completed successfully. Rollback copy retained at ${rollbackServerDir}." -Name 'staged-update'
    } catch {
        Write-PzLog -Config $config -Message "Staged refresh health check failed; rolling back. $($_.Exception.Message)" -Name 'staged-update' -Level 'ERROR'
        Write-StagedRefreshProgress -Phase 'rolling-back' -Status 'Health check failed; rolling back to previous server files.' -LastError $_.Exception.Message
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 45 -Force
        if (Test-Path -LiteralPath $config.ServerDir) {
            Move-Item -LiteralPath $config.ServerDir -Destination $failedServerDir
        }
        if (Test-Path -LiteralPath $rollbackServerDir) {
            Move-Item -LiteralPath $rollbackServerDir -Destination $config.ServerDir
        }
        if ($wasRunning) {
            Write-StagedRefreshProgress -Phase 'rolling-back-start' -Status 'Starting the rollback server and verifying game ports.'
            Start-StagedServerWithRetry
        }
        Write-StagedRefreshProgress -Phase 'failed' -Status 'Staged refresh failed and rollback was attempted.' -RestartRecommended $true -RestartReason 'Verify the server recovered after rollback. Restart manually only if the server is not running.' -LastError $_.Exception.Message
        throw
    }
} catch {
    Write-StagedRefreshProgress -Phase 'failed' -Status 'Staged refresh failed before the swap completed.' -RestartRecommended $false -RestartReason 'Review the staged update error before restarting or applying staged refresh again.' -LastError $_.Exception.Message
    throw
} finally {
    Exit-PzMaintenance -Config $config
}
