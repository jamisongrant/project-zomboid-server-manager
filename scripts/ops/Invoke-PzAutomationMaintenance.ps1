param(
    [switch]$Force,
    [switch]$IgnoreWindow,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

$startedAt = (Get-Date).ToString('o')
$stateName = 'automation-maintenance.json'

function New-AutomationCheck {
    param(
        [string]$Id,
        [string]$Label,
        [bool]$Ok,
        [string]$Message,
        [string]$Severity = 'info'
    )

    return [pscustomobject]@{
        id = $Id
        label = $Label
        ok = $Ok
        message = $Message
        severity = $Severity
    }
}

function Write-AutomationState {
    param(
        [string]$Phase,
        [string]$Decision,
        [string]$Message,
        [object[]]$Checks,
        [string]$LastError = ''
    )

    Write-PzStateJson -Config $config -Name $stateName -Data @{
        phase = $Phase
        decision = $Decision
        status = $Message
        checks = $Checks
        startedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        lastError = $LastError
        force = [bool]$Force
        ignoreWindow = [bool]$IgnoreWindow
        checkOnly = [bool]$CheckOnly
    }
}

function Get-IniValue {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $escapedKey = [regex]::Escape($Key)
    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*${escapedKey}\s*=" } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return ''
    }

    return ($line -split '=', 2)[1].Trim()
}

function Split-PzList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split ';' |
            ForEach-Object { $_.Trim().TrimStart('\') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

try {
    Write-AutomationState -Phase 'checking' -Decision 'checking' -Message 'Automation maintenance safety checks are running.' -Checks @()

    $serverIni = Join-Path $config.ProfileDir "Server\$($config.ServerName).ini"
    $workshopItems = Split-PzList (Get-IniValue -Path $serverIni -Key 'WorkshopItems')
    $modLoadOrder = Split-PzList (Get-IniValue -Path $serverIni -Key 'Mods')
    $realModIds = @($modLoadOrder | Where-Object { $_ -notmatch '^\d+$' })
    $players = Get-PzPlayerCount -Config $config
    $backupCount = @(Get-ChildItem -LiteralPath $config.BackupDir -Filter 'pz-saves-*.zip' -ErrorAction SilentlyContinue).Count
    $stagedProgressPath = Join-Path $config.StateDir 'staged-update-progress.json'
    $stagedProgress = $null
    if (Test-Path -LiteralPath $stagedProgressPath) {
        $stagedProgress = Get-Content -LiteralPath $stagedProgressPath -Raw | ConvertFrom-Json
    }

    $checks = @()
    $checks += New-AutomationCheck -Id 'requiredModsTask' -Label 'Required-mods task' -Ok $true -Message "Required-mods automation checks every $($config.ModCheckMinutes) minutes and applies at most every $($config.ModRestartIntervalMinutes) minutes." -Severity 'ok'
    $checks += New-AutomationCheck -Id 'serverIni' -Label 'Server INI' -Ok (Test-Path -LiteralPath $serverIni) -Message $serverIni -Severity $(if (Test-Path -LiteralPath $serverIni) { 'ok' } else { 'danger' })
    $checks += New-AutomationCheck -Id 'workshopItems' -Label 'WorkshopItems' -Ok ($workshopItems.Count -gt 0) -Message "$($workshopItems.Count) Workshop item(s) found in active server.ini." -Severity $(if ($workshopItems.Count -gt 0) { 'ok' } else { 'danger' })
    $checks += New-AutomationCheck -Id 'mods' -Label 'Mods load order' -Ok ($realModIds.Count -gt 0) -Message "$($realModIds.Count) non-numeric mod load ID(s) found in active server.ini." -Severity $(if ($realModIds.Count -gt 0) { 'ok' } else { 'danger' })
    $checks += New-AutomationCheck -Id 'players' -Label 'Player count' -Ok ($Force -or $players -eq 0) -Message $(if ($players -eq 0) { 'No players are currently detected online.' } elseif ($players -lt 0) { 'Player count is unknown; automation will not risk a restart without Force.' } else { "$players player(s) are online; automation will defer." }) -Severity $(if ($players -eq 0) { 'ok' } elseif ($Force) { 'warning' } else { 'danger' })
    $checks += New-AutomationCheck -Id 'backups' -Label 'Visible backups' -Ok ($backupCount -gt 0) -Message "$backupCount save backup(s) visible to the manager." -Severity $(if ($backupCount -gt 0) { 'ok' } else { 'danger' })

    if ($null -ne $stagedProgress -and $stagedProgress.phase -eq 'failed') {
        $checks += New-AutomationCheck -Id 'lastStagedRun' -Label 'Last staged run' -Ok $false -Message 'The last staged workflow failed. Review Health before automation tries another refresh.' -Severity 'danger'
    } else {
        $checks += New-AutomationCheck -Id 'lastStagedRun' -Label 'Last staged run' -Ok $true -Message 'No failed staged workflow is blocking automation.' -Severity 'ok'
    }

    $blocking = @($checks | Where-Object { -not $_.ok })
    if ($blocking.Count -gt 0) {
        $reason = ($blocking | Select-Object -First 1).message
        Write-PzLog -Config $config -Message "Automation maintenance deferred: ${reason}" -Name 'automation' -Level 'WARN'
        Write-AutomationState -Phase 'deferred' -Decision 'deferred' -Message "Automation deferred: ${reason}" -Checks $checks
        exit 0
    }

    if ($CheckOnly) {
        Write-PzLog -Config $config -Message 'Automation maintenance check passed; no refresh requested.' -Name 'automation'
        Write-AutomationState -Phase 'ready' -Decision 'ready' -Message 'Automation checks passed. Smart mod refresh is allowed during the scheduled run.' -Checks $checks
        exit 0
    }

    Write-PzLog -Config $config -Message 'Automation maintenance approved; starting smart mod refresh.' -Name 'automation'
    Write-AutomationState -Phase 'running' -Decision 'refreshing' -Message 'Automation checks passed. Smart mod refresh is running.' -Checks $checks

    $smartRefresh = Join-Path $PSScriptRoot 'Invoke-PzSmartModRefresh.ps1'
    $args = @()
    if ($Force) {
        $args += '-Force'
    }
    if ($IgnoreWindow) {
        $args += '-IgnoreWindow'
    }
    & $smartRefresh @args
    if ($LASTEXITCODE -ne 0) {
        throw "Smart mod refresh returned exit code ${LASTEXITCODE}."
    }

    Write-AutomationState -Phase 'succeeded' -Decision 'completed' -Message 'Automation maintenance completed. Review Mod Update Progress and Blue/Green State for refresh details.' -Checks $checks
} catch {
    Write-PzLog -Config $config -Message "Automation maintenance failed: $($_.Exception.Message)" -Name 'automation' -Level 'ERROR'
    Write-AutomationState -Phase 'failed' -Decision 'review' -Message 'Automation maintenance failed. Review the error before running another automated refresh.' -Checks @() -LastError $_.Exception.Message
    throw
}
