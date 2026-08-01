param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

& (Join-Path $PSScriptRoot 'Invoke-PzRequiredModsRestart.ps1')
