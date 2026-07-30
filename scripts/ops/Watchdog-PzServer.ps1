Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$healthPath = Join-Path $config.StateDir 'watchdog-health.json'
$lastRestartPath = Join-Path $config.StateDir 'watchdog-last-restart.txt'

if (Test-PzMaintenance -Config $config) {
    Write-PzLog -Config $config -Message "Maintenance lock is active; watchdog will not restart server." -Name 'watchdog'
    @{ checkedAt = (Get-Date).ToString('s'); running = $false; maintenance = $true } | ConvertTo-Json | Set-Content -LiteralPath $healthPath -Encoding ASCII
    exit 0
}

$process = Get-PzServerProcess -Config $config
if ($null -ne $process) {
    @{ checkedAt = (Get-Date).ToString('s'); running = $true; maintenance = $false; pid = $process.Id } | ConvertTo-Json | Set-Content -LiteralPath $healthPath -Encoding ASCII
    Write-PzLog -Config $config -Message "Server is healthy as PID $($process.Id)." -Name 'watchdog'
    exit 0
}

$now = Get-Date
if (Test-Path -LiteralPath $lastRestartPath) {
    $lastText = Get-Content -LiteralPath $lastRestartPath | Select-Object -First 1
    $lastRestart = [datetime]::MinValue
    if ([datetime]::TryParse($lastText, [ref]$lastRestart)) {
        $elapsed = ($now - $lastRestart).TotalSeconds
        if ($elapsed -lt $config.WatchdogMinRestartSeconds) {
            Write-PzLog -Config $config -Message "Server is down, but restart is rate-limited for $([int]($config.WatchdogMinRestartSeconds - $elapsed)) more seconds." -Name 'watchdog' -Level 'WARN'
            @{ checkedAt = $now.ToString('s'); running = $false; maintenance = $false; rateLimited = $true } | ConvertTo-Json | Set-Content -LiteralPath $healthPath -Encoding ASCII
            exit 2
        }
    }
}

Write-PzLog -Config $config -Message "Server is down; watchdog is starting it." -Name 'watchdog' -Level 'WARN'
Set-Content -LiteralPath $lastRestartPath -Value $now.ToString('s') -Encoding ASCII
& (Join-Path $PSScriptRoot 'Start-PzServer.ps1')
@{ checkedAt = $now.ToString('s'); running = $false; maintenance = $false; restarted = $true } | ConvertTo-Json | Set-Content -LiteralPath $healthPath -Encoding ASCII

