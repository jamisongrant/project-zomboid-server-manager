Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$steamCmd = Assert-PzSteamCmd -Config $config
$workshopIds = @(Get-PzEnabledWorkshopIds -Config $config)

if ($workshopIds.Count -eq 0) {
    Write-PzLog -Config $config -Message 'No enabled Workshop IDs are configured; skipping mod update.' -Name 'mods'
    Write-PzStateJson -Config $config -Name 'mod-update.json' -Data @{
        phase = 'skipped'
        status = 'No enabled Workshop IDs are configured.'
        total = 0
        completed = 0
        restartRecommended = $false
        restartReason = 'No Workshop content was changed.'
    }
    exit 0
}

$startedAt = (Get-Date).ToString('o')
$completed = 0
$workshopId = ''

Write-PzStateJson -Config $config -Name 'mod-update.json' -Data @{
    phase = 'running'
    status = 'Starting Workshop mod update.'
    startedAt = $startedAt
    total = $workshopIds.Count
    completed = 0
    currentWorkshopId = ''
    restartRecommended = $false
    restartReason = ''
}

try {
    foreach ($id in $workshopIds) {
        $workshopId = [string]$id
        Write-PzStateJson -Config $config -Name 'mod-update.json' -Data @{
            phase = 'running'
            status = "Updating Workshop item ${workshopId}."
            startedAt = $startedAt
            total = $workshopIds.Count
            completed = $completed
            currentWorkshopId = $workshopId
            restartRecommended = $false
            restartReason = ''
        }

        Write-PzLog -Config $config -Message "Updating Workshop item ${workshopId} for app $($config.WorkshopAppId)." -Name 'mods'
        & $steamCmd +force_install_dir $config.ServerDir +login anonymous +workshop_download_item $config.WorkshopAppId $workshopId validate +quit
        if ($LASTEXITCODE -ne 0) {
            throw "SteamCMD returned exit code ${LASTEXITCODE} while updating Workshop item ${workshopId}."
        }

        $completed += 1
        Write-PzStateJson -Config $config -Name 'mod-update.json' -Data @{
            phase = 'running'
            status = "Updated Workshop item ${workshopId}."
            startedAt = $startedAt
            total = $workshopIds.Count
            completed = $completed
            currentWorkshopId = $workshopId
            restartRecommended = $false
            restartReason = ''
        }
    }

    Write-PzStateJson -Config $config -Name 'mod-update.json' -Data @{
        phase = 'succeeded'
        status = "Workshop mod update complete for $($workshopIds.Count) item(s)."
        startedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        total = $workshopIds.Count
        completed = $workshopIds.Count
        currentWorkshopId = ''
        restartRecommended = $true
        restartReason = 'Project Zomboid loads Workshop files at server startup. Restart after players are clear so the running server uses the refreshed files.'
    }
    Write-PzLog -Config $config -Message "Workshop mod update complete for $($workshopIds.Count) item(s)." -Name 'mods'
} catch {
    Write-PzStateJson -Config $config -Name 'mod-update.json' -Data @{
        phase = 'failed'
        status = 'Workshop mod update failed.'
        startedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        total = $workshopIds.Count
        completed = $completed
        currentWorkshopId = $workshopId
        restartRecommended = $false
        restartReason = 'Do not restart for this failed update until the failure is understood; the running server may still be using the last known-good files.'
        lastError = $_.Exception.Message
    }
    throw
}
