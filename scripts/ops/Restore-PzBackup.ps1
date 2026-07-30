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

$resolvedBackup = Resolve-Path -LiteralPath $BackupPath
$backupRoot = [System.IO.Path]::GetFullPath($config.BackupDir)
$backupFullPath = [System.IO.Path]::GetFullPath($resolvedBackup.Path)
if (-not $backupFullPath.StartsWith($backupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup must be inside $backupRoot."
}

if ($null -ne (Get-PzServerProcess -Config $config)) {
    & (Join-Path $PSScriptRoot 'Stop-PzServer.ps1') -TimeoutSeconds 90 -Force
}

$savesRoot = Join-Path $config.ProfileDir 'Saves'
if (Test-Path -LiteralPath $savesRoot) {
    $preRestore = Join-Path $config.BackupDir ("pre-restore-saves-{0}.zip" -f (Get-PzTimestamp))
    Compress-Archive -LiteralPath $savesRoot -DestinationPath $preRestore -Force
    Remove-Item -LiteralPath $savesRoot -Recurse -Force
}

$extractDir = Join-Path $config.StagingDir ("restore-{0}" -f (Get-PzTimestamp))
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
Expand-Archive -LiteralPath $backupFullPath -DestinationPath $extractDir -Force

$candidate = Get-ChildItem -LiteralPath $extractDir -Directory -Recurse | Where-Object { $_.Name -eq 'Saves' } | Select-Object -First 1
if ($null -eq $candidate) {
    throw 'Backup archive did not contain a Saves directory.'
}

Move-Item -LiteralPath $candidate.FullName -Destination $savesRoot
Write-PzLog -Config $config -Message "Restored backup ${backupFullPath} to ${savesRoot}." -Name 'backup'

if ($Restart) {
    & (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
}

