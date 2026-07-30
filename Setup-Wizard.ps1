Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

function Read-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )

    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { 'Y/n' } else { 'y/N' }
    $value = Read-Host "$Prompt [$suffix]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value.Trim().ToLowerInvariant().StartsWith('y')
}

function New-FriendlyPassword {
    $bytes = New-Object byte[] 9
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ('pz-' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'x').Replace('/', 'y'))
}

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SetupDefaults {
    $defaults = @{
        PublicName = 'Project Zomboid Server'
        JoinPassword = (New-FriendlyPassword)
        MaxPlayers = '8'
        MemoryMin = '2048m'
        MemoryMax = '4096m'
    }

    try {
        $setupJson = & .\scripts\install\Test-PzSetup.ps1 -Json | Out-String
        $setup = $setupJson | ConvertFrom-Json
        if ($null -ne $setup.defaults) {
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.publicName)) {
                $defaults.PublicName = [string]$setup.defaults.publicName
            }
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.joinPassword)) {
                $defaults.JoinPassword = [string]$setup.defaults.joinPassword
            }
            if ($null -ne $setup.defaults.maxPlayers) {
                $defaults.MaxPlayers = [string]$setup.defaults.maxPlayers
            }
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.memoryMin)) {
                $defaults.MemoryMin = [string]$setup.defaults.memoryMin
            }
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.memoryMax)) {
                $defaults.MemoryMax = [string]$setup.defaults.memoryMax
            }
        }
    } catch {
        Write-Host 'Could not read existing setup defaults. Using fresh install defaults.'
    }

    return $defaults
}

Write-Host ''
Write-Host 'Project Zomboid Manager Setup Wizard'
Write-Host '===================================='
Write-Host ''
Write-Host 'Press Enter to accept a default. You can change these later in the admin panel.'
Write-Host ''

if ($null -eq (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    Write-Host 'Node.js 20 or newer is required for the admin panel.'
    Write-Host 'Install Node.js from https://nodejs.org/ and run this wizard again.'
    exit 1
}

$serverName = 'servertest'
$defaults = Get-SetupDefaults
$publicName = Read-WithDefault 'Server display name' $defaults.PublicName
$joinPassword = Read-WithDefault 'Join password' $defaults.JoinPassword
$maxPlayersText = Read-WithDefault 'Max players' $defaults.MaxPlayers
$memoryMin = Read-WithDefault 'Min server memory' $defaults.MemoryMin
$memoryMax = Read-WithDefault 'Max server memory' $defaults.MemoryMax
$startServer = Read-YesNo 'Start the server after install?' $true

$serverRuntimeExists = Test-Path -LiteralPath 'C:\pz\server\jre64\bin\java.exe'
$skipServerInstall = $false
if ($serverRuntimeExists) {
    $skipServerInstall = Read-YesNo 'Existing Project Zomboid server files found. Reuse them?' $true
}

$isAdmin = Test-IsAdministrator
$installFirewall = $false
$registerAutomation = $false
if ($isAdmin) {
    $installFirewall = Read-YesNo 'Install Windows Firewall rules?' $true
    $registerAutomation = Read-YesNo 'Enable scheduled automation?' $true
} else {
    Write-Host ''
    Write-Host 'Not running as Administrator. Firewall rules and scheduled automation can be enabled later from Setup/Ops.'
}

$maxPlayers = 8
if (-not [int]::TryParse($maxPlayersText, [ref]$maxPlayers)) {
    $maxPlayers = 8
}
$maxPlayers = [Math]::Min(100, [Math]::Max(1, $maxPlayers))

$installArgs = @{
    ServerName = $serverName
    PublicName = $publicName
    JoinPassword = $joinPassword
    MaxPlayers = $maxPlayers
    MemoryMin = $memoryMin
    MemoryMax = $memoryMax
}
if ($startServer) { $installArgs.StartServer = $true }
if ($skipServerInstall) { $installArgs.SkipServerInstall = $true }
if ($installFirewall) { $installArgs.InstallFirewallRules = $true }
if ($registerAutomation) { $installArgs.RegisterAutomation = $true }

Write-Host ''
Write-Host 'Installing with selected settings...'
& .\scripts\install\Install-PzManager.ps1 @installArgs

Write-Host ''
Write-Host 'Setup summary'
Write-Host '-------------'
Write-Host "Server name: $publicName"
Write-Host "Join password: $joinPassword"
Write-Host "Admin panel: http://127.0.0.1:8787"
Write-Host ''
Write-Host 'Opening the admin panel. Click Setup to review any remaining TODO items.'
Start-Process 'http://127.0.0.1:8787/#setup'
