Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

if (-not (Test-Path -LiteralPath $config.ConfigPath)) {
    throw "Missing local config at $($config.ConfigPath). Copy config\server.env.example to config\server.env first."
}

if ([string]::IsNullOrWhiteSpace($config.AdminPassword) -or $config.AdminPassword -eq 'change-this-before-start') {
    throw "Set PZ_ADMIN_PASSWORD in config\server.env before applying config."
}

if ([string]::IsNullOrWhiteSpace($config.RconPassword) -or $config.RconPassword -eq 'change-this-before-start') {
    throw "Set PZ_RCON_PASSWORD in config\server.env before applying config."
}

$serverConfigDir = Join-Path $config.ProfileDir 'Server'
New-Item -ItemType Directory -Path $serverConfigDir -Force | Out-Null

$tokens = @{
    '{{PZ_PUBLIC_NAME}}' = $config.PublicName
    '{{PZ_PUBLIC_DESCRIPTION}}' = $config.PublicDescription
    '{{PZ_PASSWORD}}' = $config.Password
    '{{PZ_MAX_PLAYERS}}' = [string]$config.MaxPlayers
    '{{PZ_PORT}}' = [string]$config.Port
    '{{PZ_UDP_PORT}}' = [string]$config.UdpPort
    '{{PZ_RCON_PORT}}' = [string]$config.RconPort
    '{{PZ_RCON_PASSWORD}}' = $config.RconPassword
}

function Expand-Template {
    param(
        [string]$Source,
        [string]$Destination,
        [hashtable]$Tokens
    )

    $content = Get-Content -LiteralPath $Source -Raw
    foreach ($key in $Tokens.Keys) {
        $content = $content.Replace($key, $Tokens[$key])
    }
    Set-Content -LiteralPath $Destination -Value $content -Encoding ASCII
}

$projectRoot = $config.ProjectRoot
Expand-Template -Source (Join-Path $projectRoot 'templates\server.ini.template') -Destination (Join-Path $serverConfigDir "$($config.ServerName).ini") -Tokens $tokens
Expand-Template -Source (Join-Path $projectRoot 'templates\servertest_SandboxVars.lua.template') -Destination (Join-Path $serverConfigDir "$($config.ServerName)_SandboxVars.lua") -Tokens $tokens
Expand-Template -Source (Join-Path $projectRoot 'templates\spawnregions.lua.template') -Destination (Join-Path $serverConfigDir "$($config.ServerName)_spawnregions.lua") -Tokens $tokens

Write-PzLog -Config $config -Message "Applied server config to ${serverConfigDir}." -Name 'ops'
