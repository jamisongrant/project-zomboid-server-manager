param(
    [string]$TaskPrefix = 'PZ Vanilla',
    [string]$RestartTime = '04:00',
    [switch]$IncludeWeeklyUpdate,
    [switch]$IncludeSmartModRefresh
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
$restartScript = Join-Path $config.ProjectRoot 'scripts\ops\Restart-PzServer.ps1'
$updateScript = Join-Path $config.ProjectRoot 'scripts\ops\Update-PzServer.ps1'
$smartModRefreshScript = Join-Path $config.ProjectRoot 'scripts\ops\Invoke-PzAutomationMaintenance.ps1'
$adminPanelScript = Join-Path $config.ProjectRoot 'tools\admin-panel\Start-AdminPanel.ps1'

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "$TaskPrefix Start On Boot" -Action (New-PzTaskAction $startScript) -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix Admin Panel At Logon" -Action (New-PzTaskAction $adminPanelScript) -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $principal -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix Watchdog" -Action (New-PzTaskAction $watchdogScript) -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)) -Principal $principal -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName "$TaskPrefix Daily Restart" -Action (New-PzTaskAction $restartScript) -Trigger (New-ScheduledTaskTrigger -Daily -At $RestartTime) -Principal $principal -Settings $settings -Force | Out-Null

if ($IncludeWeeklyUpdate) {
    Register-ScheduledTask -TaskName "$TaskPrefix Weekly Update" -Action (New-PzTaskAction $updateScript) -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At '05:00') -Principal $principal -Settings $settings -Force | Out-Null
}

if ($IncludeSmartModRefresh) {
    Register-ScheduledTask -TaskName "$TaskPrefix Smart Mod Refresh" -Action (New-PzTaskAction $smartModRefreshScript) -Trigger (New-ScheduledTaskTrigger -Daily -At $config.ModRefreshWindowStart) -Principal $principal -Settings $settings -Force | Out-Null
}

Write-PzLog -Config $config -Message "Registered scheduled tasks with prefix '${TaskPrefix}'." -Name 'tasks'
