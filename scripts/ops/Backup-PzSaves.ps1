Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

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
Compress-Archive -LiteralPath $savesRoot -DestinationPath $destination -Force

$backup = Get-Item -LiteralPath $destination
Write-PzLog -Config $config -Message "Backup complete: $($backup.FullName) ($($backup.Length) bytes)." -Name 'backup'
