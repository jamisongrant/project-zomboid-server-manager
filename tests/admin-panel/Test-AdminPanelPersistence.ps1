param(
    [string]$BaseUrl = 'http://127.0.0.1:8787',
    [switch]$StartPanel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$configDir = Join-Path $projectRoot 'config'
$envPath = Join-Path $configDir 'server.env'
$modsPath = Join-Path $configDir 'mods.json'
$serverName = 'regressiontest'
$runtimeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pz-admin-persistence-$(Get-Date -Format 'yyyyMMddHHmmss')"
$backupRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pz-admin-persistence-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
$panelProcess = $null

function Invoke-JsonApi {
    param(
        [string]$Path,
        [string]$Method = 'GET',
        [object]$Body = $null
    )

    $uri = "${BaseUrl}${Path}"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $uri -Method $Method -TimeoutSec 10
    }

    return Invoke-RestMethod -Uri $uri -Method $Method -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 8) -TimeoutSec 10
}

function Wait-AdminPanel {
    $deadline = (Get-Date).AddSeconds(20)
    do {
        try {
            Invoke-JsonApi -Path '/api/health' | Out-Null
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    } while ((Get-Date) -lt $deadline)

    throw "Admin panel did not respond at ${BaseUrl}."
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

try {
    if (Test-Path -LiteralPath $envPath) {
        Copy-Item -LiteralPath $envPath -Destination (Join-Path $backupRoot 'server.env') -Force
    }
    if (Test-Path -LiteralPath $modsPath) {
        Copy-Item -LiteralPath $modsPath -Destination (Join-Path $backupRoot 'mods.json') -Force
    }

    $serverConfigDir = Join-Path $runtimeRoot 'profile\Server'
    New-Item -ItemType Directory -Path $serverConfigDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'backups') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'logs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'state') -Force | Out-Null

    Set-Content -LiteralPath $envPath -Encoding ASCII -Value @"
PZ_ROOT=$runtimeRoot
PZ_STEAMCMD_DIR=$runtimeRoot\steamcmd
PZ_SERVER_DIR=$runtimeRoot\server
PZ_PROFILE_DIR=$runtimeRoot\profile
PZ_BACKUP_DIR=$runtimeRoot\backups
PZ_LOG_DIR=$runtimeRoot\logs
PZ_STATE_DIR=$runtimeRoot\state
PZ_STAGING_DIR=$runtimeRoot\staging

PZ_APP_ID=380870
PZ_WORKSHOP_APP_ID=108600
PZ_SERVER_NAME=$serverName
PZ_PUBLIC_NAME=Before Name
PZ_PUBLIC_DESCRIPTION=Before Description
PZ_PASSWORD=before-password
PZ_ADMIN_PASSWORD=before-admin
PZ_RCON_PASSWORD=before-rcon
PZ_MAX_PLAYERS=8
PZ_MEMORY_MIN=2048m
PZ_MEMORY_MAX=4096m
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

    Set-Content -LiteralPath (Join-Path $serverConfigDir "${serverName}.ini") -Encoding ASCII -Value @"
PublicName=Before Name
PublicDescription=Before Description
Password=before-password
MaxPlayers=8
DefaultPort=16261
UDPPort=16262
RCONPort=27015
RCONPassword=before-rcon
Map=Muldraugh, KY
Mods=
WorkshopItems=
"@

    Set-Content -LiteralPath (Join-Path $serverConfigDir "${serverName}_SandboxVars.lua") -Encoding ASCII -Value @'
SandboxVars = {
    VERSION = 5,
    Zombies = 3,
}
'@

    if ($StartPanel) {
        $port = ([uri]$BaseUrl).Port
        $panelProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $projectRoot 'tools\admin-panel\Start-AdminPanel.ps1'), '-Port', ([string]$port) -PassThru -WindowStyle Hidden
    }

    Wait-AdminPanel

    $settingsResult = Invoke-JsonApi -Path '/api/settings' -Method 'POST' -Body @{
        settings = @{
            PublicName = 'After Name'
            PublicDescription = 'After Description'
            Password = 'after-password'
            MaxPlayers = '25'
            DefaultPort = '16261'
            UDPPort = '16262'
            RCONPort = '27015'
            RCONPassword = 'after-rcon'
            Map = 'Muldraugh, KY'
            Public = 'false'
            Open = 'true'
        }
    }
    if (-not $settingsResult.ok) {
        throw 'Settings save endpoint did not return ok.'
    }

    $envText = Get-Content -LiteralPath $envPath -Raw
    foreach ($expected in @(
        'PZ_PUBLIC_NAME=After Name',
        'PZ_PUBLIC_DESCRIPTION=After Description',
        'PZ_PASSWORD=after-password',
        'PZ_MAX_PLAYERS=25',
        'PZ_RCON_PASSWORD=after-rcon'
    )) {
        if ($envText -notmatch [regex]::Escape($expected)) {
            throw "Settings save did not sync ${expected} into server.env."
        }
    }

    $config = Invoke-JsonApi -Path '/api/config-files'
    $nameEntry = @($config.files.ini.entries | Where-Object { $_.key -eq 'PublicName' })[0]
    if ($null -eq $nameEntry) {
        throw 'Config parser did not return PublicName.'
    }
    Invoke-JsonApi -Path '/api/config-files' -Method 'POST' -Body @{
        file = 'ini'
        updates = @(@{
            index = $nameEntry.index
            key = 'PublicName'
            value = 'Line Edited Name'
        })
    } | Out-Null

    $iniText = Get-Content -LiteralPath (Join-Path $serverConfigDir "${serverName}.ini") -Raw
    if ($iniText -notmatch 'PublicName=Line Edited Name') {
        throw 'Config file line edit did not persist.'
    }

    Invoke-JsonApi -Path '/api/mods' -Method 'POST' -Body @{
        mods = @(@{
            name = 'Regression Mod'
            workshopId = '123456'
            modId = 'RegressionMod'
            enabled = $true
            notes = 'test'
        })
        modLoadOrder = @('RegressionMod')
    } | Out-Null

    $modsText = Get-Content -LiteralPath $modsPath -Raw
    if ($modsText -notmatch 'Regression Mod') {
        throw 'Mods endpoint did not persist mods.json.'
    }
    $iniText = Get-Content -LiteralPath (Join-Path $serverConfigDir "${serverName}.ini") -Raw
    if ($iniText -notmatch 'WorkshopItems=123456' -or $iniText -notmatch 'Mods=RegressionMod') {
        throw 'Mods endpoint did not sync server.ini WorkshopItems/Mods.'
    }

    Write-Host 'Admin panel persistence test passed.'
} finally {
    if ($null -ne $panelProcess -and -not $panelProcess.HasExited) {
        Stop-Process -Id $panelProcess.Id -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath (Join-Path $backupRoot 'server.env')) {
        Copy-Item -LiteralPath (Join-Path $backupRoot 'server.env') -Destination $envPath -Force
    } else {
        Remove-Item -LiteralPath $envPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $backupRoot 'mods.json')) {
        Copy-Item -LiteralPath (Join-Path $backupRoot 'mods.json') -Destination $modsPath -Force
    } else {
        Remove-Item -LiteralPath $modsPath -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
}
