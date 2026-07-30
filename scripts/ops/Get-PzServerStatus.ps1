Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$process = Get-PzServerProcess -Config $config
$maintenance = Test-PzMaintenance -Config $config
$portsBound = $false
if ($null -ne $process) {
    $boundPorts = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $process.Id -and $_.LocalPort -in @($config.Port, $config.UdpPort) })
    $portsBound = @($boundPorts | Where-Object { $_.LocalPort -eq $config.Port }).Count -gt 0
}

if ($null -eq $process) {
    [pscustomobject]@{
        Running = $false
        Ready = $false
        Maintenance = $maintenance
        Pid = $null
        Port = $config.Port
        ProfileDir = $config.ProfileDir
    }
    exit 1
}

[pscustomobject]@{
    Running = $true
    Ready = $portsBound
    Maintenance = $maintenance
    Pid = $process.Id
    ProcessName = $process.ProcessName
    StartTime = $process.StartTime
    Port = $config.Port
    ProfileDir = $config.ProfileDir
}
