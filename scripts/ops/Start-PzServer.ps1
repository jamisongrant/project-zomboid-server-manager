Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config

$existing = Get-PzServerProcess -Config $config
if ($null -ne $existing) {
    Write-PzLog -Config $config -Message "Server already appears to be running as PID $($existing.Id)." -Name 'ops'
    exit 0
}

$javaExe = Join-Path $config.ServerDir 'jre64\bin\java.exe'
if (-not (Test-Path -LiteralPath $javaExe)) {
    throw "Server Java runtime not found at ${javaExe}. Run scripts\install\Install-PzServer.ps1 first."
}

$logStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $config.LogDir "server-${logStamp}.log"
$errorLogPath = Join-Path $config.LogDir "server-${logStamp}.err.log"
$arguments = @(
    '-Djava.awt.headless=true',
    '-Dzomboid.steam=1',
    '-Dzomboid.znetlog=1',
    '-XX:+UseZGC',
    '-XX:-CreateCoredumpOnCrash',
    '-XX:-OmitStackTraceInFastThrow',
    "-Xms$($config.MemoryMin)",
    "-Xmx$($config.MemoryMax)",
    '-Djava.library.path=natives/',
    '-cp',
    'java/;java/projectzomboid.jar',
    'zombie.network.GameServer',
    '-statistic',
    '0',
    '-servername',
    $config.ServerName,
    "-cachedir=$($config.ProfileDir)"
)

if (-not [string]::IsNullOrWhiteSpace($config.AdminPassword)) {
    $arguments += @('-adminpassword', $config.AdminPassword)
}

Write-PzLog -Config $config -Message "Starting Project Zomboid server with profile $($config.ProfileDir)." -Name 'ops'
$process = Start-Process -FilePath $javaExe -ArgumentList $arguments -WorkingDirectory $config.ServerDir -RedirectStandardOutput $logPath -RedirectStandardError $errorLogPath -PassThru -WindowStyle Hidden
Set-Content -LiteralPath (Get-PzPidPath -Config $config) -Value $process.Id
Write-PzLog -Config $config -Message "Started server PID $($process.Id). Server output: ${logPath}; errors: ${errorLogPath}" -Name 'ops'
Start-Sleep -Seconds 5
$process.Refresh()
if ($process.HasExited) {
    Remove-Item -LiteralPath (Get-PzPidPath -Config $config) -Force -ErrorAction SilentlyContinue
    throw "Project Zomboid server exited during startup with code $($process.ExitCode). Review ${logPath} and ${errorLogPath}."
}
Write-PzLog -Config $config -Message "Server startup process verified as running (PID $($process.Id))." -Name 'ops'
