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
$progressName = 'staged-update-progress.json'
$startedAt = (Get-Date).ToString('o')
$workshopIds = @(Get-PzEnabledWorkshopIds -Config $config)
$completed = 0
$workshopId = ''

Write-PzStateJson -Config $config -Name $progressName -Data @{
    phase = 'preparing'
    status = 'Preparing staged server directory.'
    startedAt = $startedAt
    stageServerDir = $stageServerDir
    activeServerDir = $config.ServerDir
    total = $workshopIds.Count
    completed = 0
    currentWorkshopId = ''
    safeToApply = $false
    restartRecommended = $false
}

try {
    if (Test-Path -LiteralPath $stageServerDir) {
        Remove-Item -LiteralPath $stageServerDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stageServerDir -Force | Out-Null

    Write-PzLog -Config $config -Message "Preparing staged Project Zomboid server update in ${stageServerDir}." -Name 'staged-update'
    & $steamCmd +force_install_dir $stageServerDir +login anonymous +app_update $config.AppId validate +quit
    if ($LASTEXITCODE -ne 0) {
        throw "SteamCMD returned exit code ${LASTEXITCODE} while preparing staged server update."
    }

    if (-not $SkipMods -and $workshopIds.Count -gt 0) {
        foreach ($id in $workshopIds) {
            $workshopId = [string]$id
            Write-PzStateJson -Config $config -Name $progressName -Data @{
                phase = 'preparing-mods'
                status = "Pre-downloading Workshop item ${workshopId}."
                startedAt = $startedAt
                stageServerDir = $stageServerDir
                activeServerDir = $config.ServerDir
                total = $workshopIds.Count
                completed = $completed
                currentWorkshopId = $workshopId
                safeToApply = $false
                restartRecommended = $false
            }

            Write-PzLog -Config $config -Message "Pre-downloading Workshop item ${workshopId} for app $($config.WorkshopAppId)." -Name 'staged-update'
            & $steamCmd +login anonymous +workshop_download_item $config.WorkshopAppId $workshopId validate +quit
            if ($LASTEXITCODE -ne 0) {
                throw "SteamCMD returned exit code ${LASTEXITCODE} while staging Workshop item ${workshopId}."
            }
            $completed += 1
        }
    } else {
        $completed = $workshopIds.Count
    }

    $manifest = [ordered]@{
        PreparedAt = (Get-Date).ToString('o')
        StageServerDir = $stageServerDir
        TargetServerDir = $config.ServerDir
        WorkshopCount = $workshopIds.Count
        ModsStaged = -not $SkipMods
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

    Write-PzStateJson -Config $config -Name $progressName -Data @{
        phase = 'prepared'
        status = 'Staged update is ready to apply.'
        startedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        stageServerDir = $stageServerDir
        activeServerDir = $config.ServerDir
        total = $workshopIds.Count
        completed = $completed
        currentWorkshopId = ''
        safeToApply = $true
        restartRecommended = $true
        restartReason = 'A staged server build is ready. Applying it will stop the active server, back up saves, swap directories, and restart if the server was running.'
    }

    Write-PzLog -Config $config -Message "Staged update prepared. Manifest: ${manifestPath}" -Name 'staged-update'
    [pscustomobject]$manifest
} catch {
    Write-PzStateJson -Config $config -Name $progressName -Data @{
        phase = 'failed'
        status = 'Staged update preparation failed.'
        startedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        stageServerDir = $stageServerDir
        activeServerDir = $config.ServerDir
        total = $workshopIds.Count
        completed = $completed
        currentWorkshopId = $workshopId
        safeToApply = $false
        restartRecommended = $false
        restartReason = 'Do not apply staged refresh until preparation succeeds.'
        lastError = $_.Exception.Message
    }
    throw
}
