Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
$count = Get-PzPlayerCount -Config $config

[pscustomobject]@{
    PlayerCount = $count
    QueryReliable = $count -ge 0
}

