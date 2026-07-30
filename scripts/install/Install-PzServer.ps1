Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$steamCmd = Assert-PzSteamCmd -Config $config

Write-PzLog -Config $config -Message "Installing or updating Project Zomboid dedicated server app $($config.AppId) into $($config.ServerDir)." -Name 'install'
& $steamCmd +force_install_dir $config.ServerDir +login anonymous +app_update $config.AppId validate +quit
if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD returned exit code ${LASTEXITCODE} while installing Project Zomboid server."
}

$serverExecutable = Get-PzServerExecutable -Config $config
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    Write-PzLog -Config $config -Message "Server install finished, but the expected startup script was not found yet: ${serverExecutable}." -Name 'install' -Level 'WARN'
}

Write-PzLog -Config $config -Message "Project Zomboid server install/update complete." -Name 'install'

