param(
    [switch]$SkipMods
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$steamCmd = Assert-PzSteamCmd -Config $config

$stageServerDir = Join-Path $config.StagingDir 'server-next'
$manifestPath = Join-Path $config.StagingDir 'staged-update.json'

if (Test-Path -LiteralPath $stageServerDir) {
    Remove-Item -LiteralPath $stageServerDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stageServerDir -Force | Out-Null

Write-PzLog -Config $config -Message "Preparing staged Project Zomboid server update in ${stageServerDir}." -Name 'staged-update'
& $steamCmd +force_install_dir $stageServerDir +login anonymous +app_update $config.AppId validate +quit
if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD returned exit code ${LASTEXITCODE} while preparing staged server update."
}

$workshopIds = @(Get-PzEnabledWorkshopIds -Config $config)
if (-not $SkipMods -and $workshopIds.Count -gt 0) {
    foreach ($workshopId in $workshopIds) {
        Write-PzLog -Config $config -Message "Pre-downloading Workshop item ${workshopId} for app $($config.WorkshopAppId)." -Name 'staged-update'
        & $steamCmd +login anonymous +workshop_download_item $config.WorkshopAppId $workshopId validate +quit
        if ($LASTEXITCODE -ne 0) {
            throw "SteamCMD returned exit code ${LASTEXITCODE} while staging Workshop item ${workshopId}."
        }
    }
}

$manifest = [ordered]@{
    PreparedAt = (Get-Date).ToString('o')
    StageServerDir = $stageServerDir
    TargetServerDir = $config.ServerDir
    WorkshopCount = $workshopIds.Count
    ModsStaged = -not $SkipMods
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

Write-PzLog -Config $config -Message "Staged update prepared. Manifest: ${manifestPath}" -Name 'staged-update'
[pscustomobject]$manifest
