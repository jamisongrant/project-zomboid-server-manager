param(
    [string]$ServerName = 'servertest',
    [string]$PublicName = 'Project Zomboid Server',
    [string]$JoinPassword = '',
    [string]$AdminPassword = '',
    [string]$RconPassword = '',
    [int]$MaxPlayers = 8,
    [string]$MemoryMin = '2048m',
    [string]$MemoryMax = '4096m',
    [switch]$StartServer,
    [switch]$RegisterAutomation,
    [switch]$InstallFirewallRules,
    [switch]$SkipServerInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

if ($null -eq (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw 'Node.js is required for the admin panel. Install Node.js 20 or newer, then re-run this installer.'
}

function New-LocalPassword {
    $bytes = New-Object byte[] 18
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'x').Replace('/', 'y')
}

$admin = if ([string]::IsNullOrWhiteSpace($AdminPassword)) { New-LocalPassword } else { $AdminPassword }
$rcon = if ([string]::IsNullOrWhiteSpace($RconPassword)) { New-LocalPassword } else { $RconPassword }

$configPath = Get-PzDefaultConfigPath
$content = @"
PZ_ROOT=C:\pz
PZ_STEAMCMD_DIR=C:\pz\steamcmd
PZ_SERVER_DIR=C:\pz\server
PZ_PROFILE_DIR=C:\pz\profile
PZ_BACKUP_DIR=C:\pz\backups
PZ_LOG_DIR=C:\pz\logs
PZ_STATE_DIR=C:\pz\state
PZ_STAGING_DIR=C:\pz\staging

PZ_APP_ID=380870
PZ_WORKSHOP_APP_ID=108600
PZ_SERVER_NAME=$ServerName
PZ_PUBLIC_NAME=$PublicName
PZ_PUBLIC_DESCRIPTION=Vanilla Project Zomboid dedicated server
PZ_PASSWORD=$JoinPassword
PZ_ADMIN_PASSWORD=$admin
PZ_RCON_PASSWORD=$rcon
PZ_MAX_PLAYERS=$MaxPlayers
PZ_MEMORY_MIN=$MemoryMin
PZ_MEMORY_MAX=$MemoryMax
PZ_PORT=16261
PZ_UDP_PORT=16262
PZ_RCON_PORT=27015
PZ_BACKUP_RETENTION_DAYS=14
PZ_WATCHDOG_MIN_RESTART_SECONDS=300
PZ_MOD_WARNING_SECONDS=60
PZ_AUTO_REFRESH_MODS=false
PZ_MOD_REFRESH_WINDOW_START=04:00
PZ_MOD_REFRESH_WINDOW_END=05:00
"@

Set-Content -LiteralPath $configPath -Value $content -Encoding ASCII

& (Join-Path $PSScriptRoot 'Initialize-Directories.ps1')

if (-not $SkipServerInstall) {
    & (Join-Path $PSScriptRoot 'Install-SteamCmd.ps1')
    & (Join-Path $PSScriptRoot 'Install-PzServer.ps1')
}

& (Join-Path $PSScriptRoot '..\ops\Apply-Config.ps1')

if ($InstallFirewallRules) {
    & (Join-Path $PSScriptRoot '..\ops\Install-PzFirewallRules.ps1')
}

if ($RegisterAutomation) {
    & (Join-Path $PSScriptRoot '..\tasks\Register-PzScheduledTasks.ps1') -IncludeSmartModRefresh
}

if ($StartServer) {
    & (Join-Path $PSScriptRoot '..\ops\Start-PzServer.ps1')
}

Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path (Get-PzProjectRoot) 'tools\admin-panel\Start-AdminPanel.ps1') -WindowStyle Hidden | Out-Null

Write-Host ''
Write-Host 'Project Zomboid manager installed.'
Write-Host "Admin panel: http://127.0.0.1:8787"
Write-Host "Join password: $JoinPassword"
Write-Host "Admin password: $admin"
Write-Host "RCON password: $rcon"
