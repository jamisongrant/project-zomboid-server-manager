param(
    [switch]$Force,
    [switch]$IgnoreWindow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

if (-not $IgnoreWindow -and -not (Test-PzTimeWindow -Start $config.ModRefreshWindowStart -End $config.ModRefreshWindowEnd)) {
    Write-PzLog -Config $config -Message "Mod refresh deferred; outside window $($config.ModRefreshWindowStart)-$($config.ModRefreshWindowEnd)." -Name 'mods'
    Write-PzStateJson -Config $config -Name 'staged-update-progress.json' -Data @{
        phase = 'deferred'
        status = "Smart refresh deferred; outside maintenance window $($config.ModRefreshWindowStart)-$($config.ModRefreshWindowEnd)."
        safeToApply = $false
        restartRecommended = $false
        restartReason = 'Smart refresh will not restart the server outside the configured maintenance window unless forced from PowerShell.'
    }
    exit 0
}

$players = Get-PzPlayerCount -Config $config
if (-not $Force -and $players -ne 0) {
    Write-PzLog -Config $config -Message "Mod refresh deferred; player count is ${players}." -Name 'mods'
    Write-PzStateJson -Config $config -Name 'staged-update-progress.json' -Data @{
        phase = 'deferred'
        status = "Smart refresh deferred; player count is ${players}."
        players = $players
        safeToApply = $false
        restartRecommended = $false
        restartReason = 'Smart refresh avoids restarting while players are online. Run during the maintenance window with no players, or use an explicit staged refresh when you accept the disconnect.'
    }
    exit 0
}

Write-PzLog -Config $config -Message 'Smart staged mod refresh starting.' -Name 'mods'
Write-PzStateJson -Config $config -Name 'staged-update-progress.json' -Data @{
    phase = 'running'
    status = 'Smart staged mod refresh starting.'
    safeToApply = $false
    restartRecommended = $false
}
& (Join-Path $PSScriptRoot 'Invoke-PzStagedRefresh.ps1')
