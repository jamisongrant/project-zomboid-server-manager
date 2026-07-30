Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

$steamCmdExe = Join-Path $config.SteamCmdDir 'steamcmd.exe'
if (Test-Path -LiteralPath $steamCmdExe) {
    Write-PzLog -Config $config -Message "SteamCMD already installed at ${steamCmdExe}." -Name 'install'
    exit 0
}

$zipPath = Join-Path $config.StagingDir 'steamcmd.zip'
$url = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'

Write-PzLog -Config $config -Message "Downloading SteamCMD from ${url}." -Name 'install'
Invoke-WebRequest -Uri $url -OutFile $zipPath

Write-PzLog -Config $config -Message "Extracting SteamCMD to $($config.SteamCmdDir)." -Name 'install'
Expand-Archive -LiteralPath $zipPath -DestinationPath $config.SteamCmdDir -Force

if (-not (Test-Path -LiteralPath $steamCmdExe)) {
    throw "SteamCMD extraction completed but steamcmd.exe was not found at ${steamCmdExe}."
}

Write-PzLog -Config $config -Message "SteamCMD installed at ${steamCmdExe}." -Name 'install'

