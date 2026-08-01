Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
if ($config.ModRestartIntervalMinutes -lt 1 -or $config.ModRestartIntervalMinutes -gt 1440) {
    throw 'PZ_MOD_RESTART_INTERVAL_MINUTES must be between 1 and 1440.'
}
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

function Get-WorkshopMetadataFingerprint {
    $ids = @(Get-PzEnabledWorkshopIds -Config $config)
    if ($ids.Count -eq 0) { return '' }

    $details = @()
    for ($offset = 0; $offset -lt $ids.Count; $offset += 100) {
        $chunk = @($ids[$offset..([Math]::Min($offset + 99, $ids.Count - 1))])
        $form = @{ itemcount = $chunk.Count }
        for ($index = 0; $index -lt $chunk.Count; $index += 1) {
            $form["publishedfileids[$index]"] = [string]$chunk[$index]
        }
        $response = Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body $form
        $details += @($response.response.publishedfiledetails)
    }

    $text = ($details | Sort-Object publishedfileid | ForEach-Object {
        "{0}:{1}:{2}:{3}" -f $_.publishedfileid, $_.time_updated, $_.time_created, $_.result
    }) -join '|'
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

$previous = $null
if (Test-Path -LiteralPath $statePath) {
    try { $previous = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $previous = $null }
}

$before = ''
$metadataFingerprint = ''
Enter-PzMaintenance -Config $config -Reason 'required-mods-check'
try {
    $before = Get-WorkshopFingerprint
    try {
        $metadataFingerprint = Get-WorkshopMetadataFingerprint
    } catch {
        Write-PzLog -Config $config -Message "Workshop metadata precheck unavailable; falling back to full validation. $($_.Exception.Message)" -Name 'automation' -Level 'WARN'
    }

    if ($null -ne $previous -and
        -not [string]::IsNullOrWhiteSpace([string]$previous.metadataFingerprint) -and
        -not [string]::IsNullOrWhiteSpace($metadataFingerprint) -and
        [string]$previous.metadataFingerprint -eq $metadataFingerprint -and
        [string]$previous.fingerprint -eq $before -and
        -not [bool]$previous.pending) {
        Write-RequiredState @{ phase = 'unchanged'; status = 'No required Workshop mod update detected; skipped SteamCMD staging.'; checkedAt = (Get-Date).ToString('o'); fingerprint = $before; metadataFingerprint = $metadataFingerprint; lastAppliedAt = $previous.lastAppliedAt; pending = $false; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        exit 0
    }

    Write-PzLog -Config $config -Message 'Required-mods check started.' -Name 'automation'
    Write-RequiredState @{ phase = 'preparing'; status = 'Checking Workshop content for required updates.'; checkedAt = (Get-Date).ToString('o'); fingerprintBefore = $before; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
    & (Join-Path $PSScriptRoot 'Prepare-PzStagedUpdate.ps1')
    $after = Get-WorkshopFingerprint

    if ([string]::IsNullOrWhiteSpace($after)) {
        throw 'Workshop content directory is unavailable after preparation.'
    }

    if ($null -eq $previous -or [string]::IsNullOrWhiteSpace([string]$previous.fingerprint)) {
        Write-RequiredState @{ phase = 'baseline'; status = 'Required-mods baseline recorded; no restart needed.'; checkedAt = (Get-Date).ToString('o'); fingerprint = $after; metadataFingerprint = $metadataFingerprint; lastAppliedAt = $null; pending = $false; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'server-next') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'staged-update.json') -Force -ErrorAction SilentlyContinue
        exit 0
    }

    if ([string]$previous.fingerprint -eq $after) {
        Write-RequiredState @{ phase = 'unchanged'; status = 'No required Workshop mod update detected.'; checkedAt = (Get-Date).ToString('o'); fingerprint = $after; metadataFingerprint = $metadataFingerprint; lastAppliedAt = $previous.lastAppliedAt; pending = [bool]$previous.pending; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'server-next') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $config.StagingDir 'staged-update.json') -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $lastApplied = [datetime]::MinValue
    if ($previous.lastAppliedAt) { [datetime]::TryParse([string]$previous.lastAppliedAt, [ref]$lastApplied) | Out-Null }
    $eligible = ((Get-Date) - $lastApplied).TotalMinutes -ge $config.ModRestartIntervalMinutes
    if (-not $eligible) {
        Write-RequiredState @{ phase = 'pending'; status = "Required mod updates staged; waiting for the $($config.ModRestartIntervalMinutes)-minute restart interval."; checkedAt = (Get-Date).ToString('o'); fingerprint = [string]$previous.fingerprint; metadataFingerprint = $metadataFingerprint; stagedFingerprint = $after; lastAppliedAt = $previous.lastAppliedAt; pending = $true; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
        exit 0
    }

    Write-RequiredState @{ phase = 'restarting'; status = "Required mod updates found. Restarting with a $($config.ModWarningSeconds)-second player warning."; checkedAt = (Get-Date).ToString('o'); fingerprint = [string]$previous.fingerprint; metadataFingerprint = $metadataFingerprint; stagedFingerprint = $after; lastAppliedAt = $previous.lastAppliedAt; pending = $true; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
    & (Join-Path $PSScriptRoot 'Invoke-PzStagedRefresh.ps1') -SkipPrepare
    $appliedAt = (Get-Date).ToString('o')
    Write-RequiredState @{ phase = 'ready'; status = 'Required mod restart completed and server recovery was verified.'; checkedAt = $appliedAt; fingerprint = $after; metadataFingerprint = $metadataFingerprint; lastAppliedAt = $appliedAt; pending = $false; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
} catch {
    Write-PzLog -Config $config -Message "Required-mods restart failed: $($_.Exception.Message)" -Name 'automation' -Level 'ERROR'
    Write-RequiredState @{ phase = 'failed'; status = 'Required mod restart failed. Review Health before retrying.'; checkedAt = (Get-Date).ToString('o'); fingerprint = if ($previous) { [string]$previous.fingerprint } else { $before }; metadataFingerprint = $metadataFingerprint; pending = $true; lastError = $_.Exception.Message; restartIntervalMinutes = $config.ModRestartIntervalMinutes }
    throw
} finally {
    Exit-PzMaintenance -Config $config
}
