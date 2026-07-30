Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

function Invoke-PzServerAppUpdate {
    param(
        [pscustomobject]$Config,
        [string]$SteamCmd,
        [int]$Attempts = 4
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-PzLog -Config $Config -Message "SteamCMD app_update attempt ${attempt} of ${Attempts} for app $($Config.AppId)." -Name 'install'
        & $SteamCmd +force_install_dir $Config.ServerDir +login anonymous +app_update $Config.AppId validate +quit
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return
        }

        if ($attempt -lt $Attempts) {
            $delaySeconds = 10 * $attempt
            Write-PzLog -Config $Config -Message "SteamCMD returned exit code ${exitCode}. Retrying in ${delaySeconds} seconds." -Name 'install' -Level 'WARN'
            Start-Sleep -Seconds $delaySeconds
        } else {
            throw "SteamCMD returned exit code ${exitCode} while installing Project Zomboid server after ${Attempts} attempts."
        }
    }
}

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$steamCmd = Assert-PzSteamCmd -Config $config

Write-PzLog -Config $config -Message "Installing or updating Project Zomboid dedicated server app $($config.AppId) into $($config.ServerDir)." -Name 'install'
Invoke-PzServerAppUpdate -Config $config -SteamCmd $steamCmd

$serverExecutable = Get-PzServerExecutable -Config $config
if (-not (Test-Path -LiteralPath $serverExecutable)) {
    Write-PzLog -Config $config -Message "Server install finished, but the expected startup script was not found yet: ${serverExecutable}." -Name 'install' -Level 'WARN'
}

Write-PzLog -Config $config -Message "Project Zomboid server install/update complete." -Name 'install'

