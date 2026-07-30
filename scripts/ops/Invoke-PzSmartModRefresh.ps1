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
    exit 2
}

$players = Get-PzPlayerCount -Config $config
if (-not $Force -and $players -ne 0) {
    Write-PzLog -Config $config -Message "Mod refresh deferred; player count is ${players}." -Name 'mods'
    exit 3
}

Write-PzLog -Config $config -Message 'Smart staged mod refresh starting.' -Name 'mods'
& (Join-Path $PSScriptRoot 'Invoke-PzStagedRefresh.ps1')
