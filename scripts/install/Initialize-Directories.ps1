Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
Write-PzLog -Config $config -Message "Initialized Project Zomboid runtime directories under $($config.Root)." -Name 'install'

