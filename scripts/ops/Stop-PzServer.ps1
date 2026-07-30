param(
    [int]$TimeoutSeconds = 60,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$process = Get-PzServerProcess -Config $config

if ($null -eq $process) {
    Write-PzLog -Config $config -Message "Server is not running." -Name 'ops'
    exit 0
}

Write-PzLog -Config $config -Message "Stopping server process PID $($process.Id)." -Name 'ops'
$rconShutdownIssued = $false
try {
    Write-PzLog -Config $config -Message 'Sending RCON save command.' -Name 'ops'
    Invoke-PzRconCommand -Config $config -Command 'save' | Out-Null
    Start-Sleep -Seconds 3
    Write-PzLog -Config $config -Message 'Sending RCON quit command.' -Name 'ops'
    Invoke-PzRconCommand -Config $config -Command 'quit' | Out-Null
    $rconShutdownIssued = $true
} catch {
    Write-PzLog -Config $config -Message "RCON graceful shutdown failed: $($_.Exception.Message)" -Name 'ops' -Level 'WARN'
    try {
        $process.CloseMainWindow() | Out-Null
    } catch {
        Write-PzLog -Config $config -Message "CloseMainWindow fallback failed: $($_.Exception.Message)" -Name 'ops' -Level 'WARN'
    }
}

$process.WaitForExit($TimeoutSeconds * 1000) | Out-Null
if (-not $process.HasExited) {
    if ($Force) {
        $path = if ($rconShutdownIssued) { 'after RCON quit' } else { 'without RCON shutdown' }
        Write-PzLog -Config $config -Message "Server did not stop within ${TimeoutSeconds}s ${path}; forcing process termination." -Name 'ops' -Level 'WARN'
        Stop-Process -Id $process.Id -Force
    } else {
        throw "Server did not stop within ${TimeoutSeconds}s. Re-run with -Force if needed."
    }
}

$pidPath = Get-PzPidPath -Config $config
if (Test-Path -LiteralPath $pidPath) {
    Remove-Item -LiteralPath $pidPath -Force
}

Write-PzLog -Config $config -Message "Server stopped." -Name 'ops'
