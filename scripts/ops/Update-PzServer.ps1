Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$steamCmd = Assert-PzSteamCmd -Config $config
$wasRunning = $null -ne (Get-PzServerProcess -Config $config)

Enter-PzMaintenance -Config $config -Reason 'update'
try {
    if ($wasRunning) {
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    }

    & (Join-Path $PSScriptRoot 'Backup-PzSaves.ps1')

    Write-PzLog -Config $config -Message "Running SteamCMD update/validate for app $($config.AppId)." -Name 'update'
    & $steamCmd +force_install_dir $config.ServerDir +login anonymous +app_update $config.AppId validate +quit
    if ($LASTEXITCODE -ne 0) {
        throw "SteamCMD returned exit code ${LASTEXITCODE} during update."
    }

    Write-PzLog -Config $config -Message "Project Zomboid server update complete." -Name 'update'

    if ($wasRunning) {
        & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
    }
} finally {
    Exit-PzMaintenance -Config $config
}
