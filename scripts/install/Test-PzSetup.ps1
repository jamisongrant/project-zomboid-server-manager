param(
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

function New-Check {
    param(
        [string]$Id,
        [string]$Label,
        [bool]$Ok,
        [string]$Detail,
        [string]$Next = ''
    )

    [pscustomobject]@{
        id = $Id
        label = $Label
        ok = $Ok
        detail = $Detail
        next = $Next
    }
}

$config = Get-PzConfig
$envValues = Read-PzEnvFile
$checks = New-Object System.Collections.Generic.List[object]
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$node = Get-Command node.exe -ErrorAction SilentlyContinue
$nodeVersion = ''
$nodeOk = $false
if ($null -ne $node) {
    $nodeVersion = (& $node.Source --version 2>$null).Trim()
    $major = 0
    if ($nodeVersion -match '^v?(\d+)') {
        $major = [int]$Matches[1]
    }
    $nodeOk = $major -ge 20
}
$checks.Add((New-Check 'node' 'Node.js 20+' $nodeOk ($(if ($nodeOk) { $nodeVersion } elseif ($nodeVersion) { "Found ${nodeVersion}" } else { 'Not found' })) 'Install Node.js 20 or newer from https://nodejs.org/.'))

$configExists = Test-Path -LiteralPath $config.ConfigPath
$checks.Add((New-Check 'localConfig' 'Local config' $configExists $config.ConfigPath 'Run START-HERE.ps1 or scripts\install\Install-PzManager.ps1.'))

$adminSecretOk = -not [string]::IsNullOrWhiteSpace($config.AdminPassword) -and $config.AdminPassword -ne 'change-this-before-start'
$rconSecretOk = -not [string]::IsNullOrWhiteSpace($config.RconPassword) -and $config.RconPassword -ne 'change-this-before-start'
$checks.Add((New-Check 'secrets' 'Admin/RCON passwords' ($adminSecretOk -and $rconSecretOk) ($(if ($adminSecretOk -and $rconSecretOk) { 'Configured' } else { 'Missing or placeholder value' })) 'Set passwords in config\server.env or rerun the installer.'))

$steamCmdPath = Join-Path $config.SteamCmdDir 'steamcmd.exe'
$checks.Add((New-Check 'steamcmd' 'SteamCMD' (Test-Path -LiteralPath $steamCmdPath) $steamCmdPath 'Run scripts\install\Install-SteamCmd.ps1.'))

$javaPath = Join-Path $config.ServerDir 'jre64\bin\java.exe'
$checks.Add((New-Check 'serverRuntime' 'Project Zomboid server files' (Test-Path -LiteralPath $javaPath) $javaPath 'Run scripts\install\Install-PzServer.ps1.'))

$serverIni = Join-Path $config.ProfileDir "Server\$($config.ServerName).ini"
$sandboxVars = Join-Path $config.ProfileDir "Server\$($config.ServerName)_SandboxVars.lua"
$checks.Add((New-Check 'serverIni' 'Server INI' (Test-Path -LiteralPath $serverIni) $serverIni 'Run scripts\ops\Apply-Config.ps1.'))
$checks.Add((New-Check 'sandboxVars' 'SandboxVars' (Test-Path -LiteralPath $sandboxVars) $sandboxVars 'Run scripts\ops\Apply-Config.ps1.'))

$iniDefaults = @{}
if (Test-Path -LiteralPath $serverIni) {
    foreach ($line in Get-Content -LiteralPath $serverIni) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith('#') -and $trimmed.Contains('=')) {
            $parts = $trimmed -split '=', 2
            $iniDefaults[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
}

function Get-IniOrConfigDefault {
    param(
        [string]$IniKey,
        [string]$ConfigValue
    )

    if ($iniDefaults.ContainsKey($IniKey) -and -not [string]::IsNullOrWhiteSpace($iniDefaults[$IniKey])) {
        return $iniDefaults[$IniKey]
    }
    return $ConfigValue
}

$firewallRules = @(
    Get-NetFirewallRule -DisplayName 'Project Zomboid UDP Game' -ErrorAction SilentlyContinue
    Get-NetFirewallRule -DisplayName 'Project Zomboid UDP Player' -ErrorAction SilentlyContinue
) | Where-Object { $null -ne $_ }
$checks.Add((New-Check 'firewall' 'Windows Firewall rules' (@($firewallRules).Count -ge 2) ("$(@($firewallRules).Count) of 2 rules found") 'Run scripts\ops\Install-PzFirewallRules.ps1 as Administrator.'))

$tasks = @(Get-ScheduledTask -TaskName 'PZ Vanilla *' -ErrorAction SilentlyContinue)
$checks.Add((New-Check 'automation' 'Scheduled automation' ($tasks.Count -ge 4) ("$($tasks.Count) task(s) found") 'Run scripts\tasks\Register-PzScheduledTasks.ps1 as Administrator, or use Enable Automation.'))

$adminPidPath = Join-Path $config.StateDir 'admin-panel.pid'
$adminRunning = $false
if (Test-Path -LiteralPath $adminPidPath) {
    $pidText = Get-Content -LiteralPath $adminPidPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pidText -match '^\d+$') {
        $adminRunning = $null -ne (Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue)
    }
}
$checks.Add((New-Check 'adminPanel' 'Admin panel' $adminRunning 'http://127.0.0.1:8787' 'Run Open-AdminPanel.ps1.'))

$stagedDir = Join-Path $config.StagingDir 'server-next'
$rollbackDir = Join-Path $config.StagingDir 'server-rollback'
$checks.Add((New-Check 'stagedUpdate' 'Staged update prepared' (Test-Path -LiteralPath $stagedDir) $stagedDir 'Use Mods > Stage Pending Updates before applying a staged refresh.'))
$checks.Add((New-Check 'rollback' 'Rollback copy available' (Test-Path -LiteralPath $rollbackDir) $rollbackDir 'Created automatically after a staged refresh.'))

$blockingIssues = @($checks | Where-Object { -not $_.ok -and $_.id -notin @('firewall', 'automation', 'stagedUpdate', 'rollback') })
$summary = New-Object psobject
$summary | Add-Member -NotePropertyName 'ok' -NotePropertyValue ($blockingIssues.Count -eq 0)
$summary | Add-Member -NotePropertyName 'generatedAt' -NotePropertyValue ((Get-Date).ToString('o'))
$summary | Add-Member -NotePropertyName 'projectRoot' -NotePropertyValue ([string]$config.ProjectRoot)
$summary | Add-Member -NotePropertyName 'runtimeRoot' -NotePropertyValue ([string]$config.Root)
$summary | Add-Member -NotePropertyName 'isAdministrator' -NotePropertyValue $isAdministrator
$summary | Add-Member -NotePropertyName 'defaults' -NotePropertyValue ([pscustomobject]@{
    runtimeRoot = [string]$config.Root
    publicName = [string](Get-IniOrConfigDefault 'PublicName' $config.PublicName)
    joinPassword = [string](Get-IniOrConfigDefault 'Password' $config.Password)
    maxPlayers = [int](Get-IniOrConfigDefault 'MaxPlayers' ([string]$config.MaxPlayers))
    memoryMin = [string]$config.MemoryMin
    memoryMax = [string]$config.MemoryMax
})
$checkArray = @()
foreach ($check in $checks) {
    $checkArray += $check
}
$summary | Add-Member -NotePropertyName 'checks' -NotePropertyValue $checkArray

if ($Json) {
    $summary | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host ''
Write-Host 'Project Zomboid Manager Setup Check'
Write-Host '==================================='
foreach ($check in $checks) {
    $mark = if ($check.ok) { '[OK]' } else { '[TODO]' }
    Write-Host "$mark $($check.label): $($check.detail)"
    if (-not $check.ok -and $check.next) {
        Write-Host "     Next: $($check.next)"
    }
}

if ($summary.ok) {
    Write-Host ''
    Write-Host 'Core setup is ready.'
} else {
    Write-Host ''
    Write-Host 'Core setup still needs attention.'
}
