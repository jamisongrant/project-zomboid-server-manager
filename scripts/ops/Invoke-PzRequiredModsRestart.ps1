Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$stateName = 'required-mods-restart.json'
$statePath = Join-Path $config.StateDir $stateName
$contentRoot = Join-Path $config.SteamCmdDir "steamapps\workshop\content\$($config.WorkshopAppId)"

function Get-WorkshopFingerprint {
    if (-not (Test-Path -LiteralPath $contentRoot)) { return '' }
    $items = @(Get-ChildItem -LiteralPath $contentRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { "$($_.Name):$($_.LastWriteTimeUtc.Ticks):$($_.Length)" })
    $text = ($items -join '|')
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Write-RequiredState {
    param([hashtable]$Data)
    Write-PzStateJson -Config $config -Name $stateName -Data $Data
}

$previous = $null
if (Test-Path -LiteralPath $statePath) {
    try { $previous = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $previous = $null }
}

$before = ''
Enter-PzMaintenance -Config $config -Reason 'required-mods-check'
try {
    $before = Get-WorkshopFingerprint
    Write-PzLog -Config $config -Message 'Required-mods check started.' -Name 'automation'
    Write-RequiredState @{ phase = 'preparing'; status = 'Checking Workshop content for required updates.'; checkedAt = (Get-Date).ToString('o'); fingerprintBefore = $before; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
    & (Join-Path $PSScriptRoot 'Prepare-PzStagedUpdate.ps1')
    $after = Get-WorkshopFingerprint

    if ([string]::IsNullOrWhiteSpace($after)) {
        throw 'Workshop content directory is unavailable after preparation.'
    }

    if ($null -eq $previous -or [string]::IsNullOrWhiteSpace([string]$previous.fingerprint)) {
        Write-RequiredState @{ phase = 'baseline'; status = 'Required-mods baseline recorded; no restart needed.'; checkedAt = (Get-Date).ToString('o'); fingerprint = $after; lastAppliedAt = $null; pending = $false; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'server-next') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'staged-update.json') -Force -ErrorAction SilentlyContinue
        exit 0
    }

    if ([string]$previous.fingerprint -eq $after) {
        Write-RequiredState @{ phase = 'unchanged'; status = 'No required Workshop mod update detected.'; checkedAt = (Get-Date).ToString('o'); fingerprint = $after; lastAppliedAt = $previous.lastAppliedAt; pending = [bool]$previous.pending; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'server-next') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'staged-update.json') -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $lastApplied = [datetime]::MinValue
    if ($previous.lastAppliedAt) { [datetime]::TryParse([string]$previous.lastAppliedAt, [ref]$lastApplied) | Out-Null }
    $eligible = ((Get-Date) - $lastApplied).TotalMinutes -ge $config.ModRestartIntervalMinutes
    if (-not $eligible) {
        Write-RequiredState @{ phase = 'pending'; status = "Required mod updates staged; waiting for the $($config.ModRestartIntervalMinutes)-minute restart interval."; checkedAt = (Get-Date).ToString('o'); fingerprint = [string]$previous.fingerprint; stagedFingerprint = $after; lastAppliedAt = $previous.lastAppliedAt; pending = $true; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        exit 0
    }

    Write-RequiredState @{ phase = 'restarting'; status = "Required mod updates found. Restarting with a $($config.ModWarningSeconds)-second player warning."; checkedAt = (Get-Date).ToString('o'); fingerprint = [string]$previous.fingerprint; stagedFingerprint = $after; lastAppliedAt = $previous.lastAppliedAt; pending = $true; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
    & (Join-Path $PSScriptRoot 'Invoke-PzStagedRefresh.ps1') -SkipPrepare
    $appliedAt = (Get-Date).ToString('o')
    Write-RequiredState @{ phase = 'ready'; status = 'Required mod restart completed and server recovery was verified.'; checkedAt = $appliedAt; fingerprint = $after; lastAppliedAt = $appliedAt; pending = $false; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
} catch {
    Write-PzLog -Config $config -Message "Required-mods restart failed: $($_.Exception.Message)" -Name 'automation' -Level 'ERROR'
    Write-RequiredState @{ phase = 'failed'; status = 'Required mod restart failed. Review Health before retrying.'; checkedAt = (Get-Date).ToString('o'); fingerprint = if ($previous) { [string]$previous.fingerprint } else { $before }; pending = $true; lastError = $_.Exception.Message; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
    throw
} finally {
    Exit-PzMaintenance -Config $config
}
