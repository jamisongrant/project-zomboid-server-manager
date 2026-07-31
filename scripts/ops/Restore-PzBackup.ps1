param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    [switch]$Restart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

function Write-RestoreProgress {
    param(
        [string]$Phase,
        [string]$Status,
        [int]$Completed,
        [int]$Total = 6,
        [string]$LastError = ''
    )

    Write-PzStateJson -Config $config -Name 'restore-progress.json' -Data @{
        phase = $Phase
        status = $Status
        completed = $Completed
        total = $Total
        backupPath = $backupFullPath
        lastError = $LastError
    }
}

$resolvedBackup = Resolve-Path -LiteralPath $BackupPath
$backupRoot = [System.IO.Path]::GetFullPath($config.BackupDir)
$backupFullPath = [System.IO.Path]::GetFullPath($resolvedBackup.Path)
if (-not $backupFullPath.StartsWith($backupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup must be inside $backupRoot."
}

try {
    Write-RestoreProgress -Phase 'starting' -Status "Restore starting from $([System.IO.Path]::GetFileName($backupFullPath))." -Completed 0

    if ($null -ne (Get-PzServerProcess -Config $config)) {
        Write-RestoreProgress -Phase 'stopping-server' -Status 'Stopping server before save restore.' -Completed 1
        & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
    } else {
        Write-RestoreProgress -Phase 'server-stopped' -Status 'Server is already stopped.' -Completed 1
    }

    $savesRoot = Join-Path $config.ProfileDir 'Saves'
    if (Test-Path -LiteralPath $savesRoot) {
        Write-RestoreProgress -Phase 'pre-restore-backup' -Status 'Creating a pre-restore backup of the current Saves folder.' -Completed 2
        $preRestore = Join-Path $config.BackupDir ("pre-restore-saves-{0}.zip" -f (Get-PzTimestamp))
        Compress-Archive -LiteralPath $savesRoot -DestinationPath $preRestore -Force
        Write-RestoreProgress -Phase 'clearing-current-saves' -Status 'Removing current Saves folder before restore.' -Completed 3
        Remove-Item -LiteralPath $savesRoot -Recurse -Force
    } else {
        Write-RestoreProgress -Phase 'no-current-saves' -Status 'No current Saves folder was present.' -Completed 3
    }

    $extractDir = Join-Path $config.StagingDir ("restore-{0}" -f (Get-PzTimestamp))
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    Write-RestoreProgress -Phase 'extracting' -Status 'Extracting selected backup into staging.' -Completed 4
    Expand-Archive -LiteralPath $backupFullPath -DestinationPath $extractDir -Force

    $candidate = Get-ChildItem -LiteralPath $extractDir -Directory -Recurse | Where-Object { $_.Name -eq 'Saves' } | Select-Object -First 1
    if ($null -eq $candidate) {
        throw 'Backup archive did not contain a Saves directory.'
    }

    Write-RestoreProgress -Phase 'moving-saves' -Status 'Moving restored Saves folder into the active profile.' -Completed 5
    Move-Item -LiteralPath $candidate.FullName -Destination $savesRoot
    Write-PzLog -Config $config -Message "Restored backup ${backupFullPath} to ${savesRoot}." -Name 'backup'

    if ($Restart) {
        Write-RestoreProgress -Phase 'starting-server' -Status 'Starting server after restore.' -Completed 5
        & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
    }

    Write-RestoreProgress -Phase 'succeeded' -Status 'Restore completed successfully.' -Completed 6
} catch {
    Write-RestoreProgress -Phase 'failed' -Status 'Restore failed. Review the error before retrying.' -Completed 0 -LastError $_.Exception.Message
    throw
}

