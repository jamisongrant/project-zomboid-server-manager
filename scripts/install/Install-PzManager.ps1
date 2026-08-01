param(
    [string]$RuntimeRoot = 'C:\pz',
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
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'x').Replace('/', 'y')
}

$admin = if ([string]::IsNullOrWhiteSpace($AdminPassword)) { New-LocalPassword } else { $AdminPassword }
$rcon = if ([string]::IsNullOrWhiteSpace($RconPassword)) { New-LocalPassword } else { $RconPassword }
$runtime = $RuntimeRoot.Trim()
if ([string]::IsNullOrWhiteSpace($runtime)) {
    $runtime = 'C:\pz'
}
$runtime = $runtime.TrimEnd('\', '/')

$configPath = Get-PzDefaultConfigPath
$content = @"
PZ_ROOT=$runtime
PZ_STEAMCMD_DIR=$runtime\steamcmd
PZ_SERVER_DIR=$runtime\server
PZ_PROFILE_DIR=$runtime\profile
PZ_BACKUP_DIR=$runtime\backups
PZ_LOG_DIR=$runtime\logs
PZ_STATE_DIR=$runtime\state
PZ_STAGING_DIR=$runtime\staging

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
PZ_LOG_RETENTION_DAYS=14
PZ_WATCHDOG_MIN_RESTART_SECONDS=300
PZ_MOD_WARNING_SECONDS=60
PZ_AUTO_REFRESH_MODS=false
PZ_MOD_CHECK_MINUTES=10
PZ_MOD_RESTART_INTERVAL_MINUTES=60
PZ_STARTUP_TIMEOUT_SECONDS=300
PZ_STARTUP_POLL_SECONDS=5
"@

Set-Content -LiteralPath $configPath -Value $content -Encoding ASCII

& (Join-Path $PSScriptRoot 'Initialize-Directories.ps1')

$serverJava = Join-Path $runtime 'server\jre64\bin\java.exe'
if ($SkipServerInstall -and -not (Test-Path -LiteralPath $serverJava)) {
    Write-Host "Existing server files were requested, but the Project Zomboid runtime was not found at $serverJava."
    Write-Host 'Installing the dedicated server files now.'
    $SkipServerInstall = $false
}

if (-not $SkipServerInstall) {
    & (Join-Path $PSScriptRoot 'Install-SteamCmd.ps1')
    & (Join-Path $PSScriptRoot 'Install-PzServer.ps1')
}

& (Join-Path $PSScriptRoot '..\ops\Apply-Config.ps1')

if ($InstallFirewallRules) {
    & (Join-Path $PSScriptRoot '..\ops\Install-PzFirewallRules.ps1')
}

if ($RegisterAutomation) {
    & (Join-Path $PSScriptRoot '..\tasks\Register-PzScheduledTasks.ps1')
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
