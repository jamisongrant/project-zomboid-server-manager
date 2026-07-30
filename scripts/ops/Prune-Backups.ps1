param(
    [int]$RetentionDays = -1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
if ($RetentionDays -lt 0) {
    $RetentionDays = $config.BackupRetentionDays
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
$oldBackups = Get-ChildItem -LiteralPath $config.BackupDir -Filter 'pz-saves-*.zip' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }

foreach ($backup in $oldBackups) {
    Write-PzLog -Config $config -Message "Pruning old backup $($backup.FullName)." -Name 'backup'
    Remove-Item -LiteralPath $backup.FullName -Force
}

Write-PzLog -Config $config -Message "Backup pruning complete. Retention: ${RetentionDays} days." -Name 'backup'

