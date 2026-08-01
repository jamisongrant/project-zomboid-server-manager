param(
    [string]$TaskPrefix = 'PZ Vanilla',
    [int]$ModCheckMinutes = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
Initialize-PzDirectories -Config $config
$pwsh = (Get-Command powershell.exe).Source

function New-PzTaskAction {
    param([string]$ScriptPath)
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    return New-ScheduledTaskAction -Execute $pwsh -Argument $args
}

$startScript = Join-Path $config.ProjectRoot 'scripts\ops\Start-PzServer.ps1'
$watchdogScript = Join-Path $config.ProjectRoot 'scripts\ops\Watchdog-PzServer.ps1'
$requiredModsScript = Join-Path $config.ProjectRoot 'scripts\ops\Invoke-PzRequiredModsRestart.ps1'
$adminPanelScript = Join-Path $config.ProjectRoot 'tools\admin-panel\Start-AdminPanel.ps1'

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "$TaskPrefix Start On Boot" -Action (New-PzTaskAction $startScript) -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix Admin Panel At Logon" -Action (New-PzTaskAction $adminPanelScript) -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $principal -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix Watchdog" -Action (New-PzTaskAction $watchdogScript) -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)) -Principal $principal -Settings $settings -Force | Out-Null
$interval = if ($ModCheckMinutes -gt 0) { $ModCheckMinutes } else { $config.ModCheckMinutes }
if ($interval -notin @(5, 10, 15, 30, 60)) {
    throw 'Mod check interval must be 5, 10, 15, 30, or 60 minutes.'
}
Register-ScheduledTask -TaskName "$TaskPrefix Required Mods Restart" -Action (New-PzTaskAction $requiredModsScript) -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes $interval) -RepetitionDuration (New-TimeSpan -Days 3650)) -Principal $principal -Settings $settings -Force | Out-Null

Write-PzLog -Config $config -Message "Registered required-mods restart task with ${interval}-minute checks." -Name 'tasks'
