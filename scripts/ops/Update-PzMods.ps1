Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$steamCmd = Assert-PzSteamCmd -Config $config
$workshopIds = @(Get-PzEnabledWorkshopIds -Config $config)

if ($workshopIds.Count -eq 0) {
    Write-PzLog -Config $config -Message 'No enabled Workshop IDs are configured; skipping mod update.' -Name 'mods'
    exit 0
}

foreach ($workshopId in $workshopIds) {
    Write-PzLog -Config $config -Message "Updating Workshop item ${workshopId} for app $($config.WorkshopAppId)." -Name 'mods'
    & $steamCmd +login anonymous +workshop_download_item $config.WorkshopAppId $workshopId validate +quit
    if ($LASTEXITCODE -ne 0) {
        throw "SteamCMD returned exit code ${LASTEXITCODE} while updating Workshop item ${workshopId}."
    }
}

Write-PzLog -Config $config -Message "Workshop mod update complete for $($workshopIds.Count) item(s)." -Name 'mods'

