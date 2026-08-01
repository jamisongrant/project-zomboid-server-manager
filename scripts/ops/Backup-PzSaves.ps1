param(
    [switch]$DeferCompression,
    [string]$CompressSnapshotPath = '',
    [string]$CompressDestinationPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

if ($CompressSnapshotPath) {
    if (-not (Test-Path -LiteralPath $CompressSnapshotPath)) {
        throw "Backup snapshot was not found at ${CompressSnapshotPath}."
    }
    if (-not $CompressDestinationPath) {
        throw 'CompressDestinationPath is required when compressing a snapshot.'
    }

    Write-PzLog -Config $config -Message "Compressing deferred save snapshot into ${CompressDestinationPath}." -Name 'backup'
    Compress-Archive -Path (Join-Path $CompressSnapshotPath 'Saves') -DestinationPath $CompressDestinationPath -Force
    $backup = Get-Item -LiteralPath $CompressDestinationPath
    Remove-Item -LiteralPath $CompressSnapshotPath -Recurse -Force
    Write-PzLog -Config $config -Message "Deferred backup complete: $($backup.FullName) ($($backup.Length) bytes)." -Name 'backup'
    exit 0
}

if ($null -ne (Get-PzServerProcess -Config $config)) {
    throw 'The server is running and save files may be locked. Stop the server first or use Restart-PzServer.ps1 -BackupFirst.'
}

$savesRoot = Join-Path $config.ProfileDir 'Saves'
if (-not (Test-Path -LiteralPath $savesRoot)) {
    Write-PzLog -Config $config -Message "No saves directory exists yet at ${savesRoot}; skipping backup." -Name 'backup' -Level 'WARN'
    exit 0
}

$timestamp = Get-PzTimestamp
$destination = Join-Path $config.BackupDir "pz-saves-${timestamp}.zip"
Write-PzLog -Config $config -Message "Creating save backup ${destination} from ${savesRoot}." -Name 'backup'

if ($DeferCompression) {
    $snapshot = Join-Path $config.BackupDir "pending-pz-saves-${timestamp}"
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
    Copy-Item -LiteralPath $savesRoot -Destination $snapshot -Recurse -Force

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-CompressSnapshotPath', $snapshot,
        '-CompressDestinationPath', $destination
    )
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $arguments | Out-Null
    Write-PzLog -Config $config -Message "Save snapshot complete at ${snapshot}; compression continues after server startup." -Name 'backup'
    exit 0
}

Compress-Archive -LiteralPath $savesRoot -DestinationPath $destination -Force

$backup = Get-Item -LiteralPath $destination
Write-PzLog -Config $config -Message "Backup complete: $($backup.FullName) ($($backup.Length) bytes)." -Name 'backup'
