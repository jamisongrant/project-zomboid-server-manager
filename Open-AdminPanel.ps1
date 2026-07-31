param(
    [int]$Port = 8787,
    [switch]$Relaunched
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Relaunched) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Relaunched -Port $Port"
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments | Out-Null
        Write-Host 'Administrator permission requested. Approve the UAC prompt to start the admin panel.'
        exit 0
    }
}

$stateDir = 'C:\pz\state'
$pidPath = Join-Path $stateDir 'admin-panel.pid'

if (Test-Path -LiteralPath $pidPath) {
    $pidText = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pidText -match '^\d+$') {
        $process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            Start-Process "http://127.0.0.1:$Port"
            Write-Host "Admin panel already running at http://127.0.0.1:$Port"
            exit 0
        }
    }
}

Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'tools\admin-panel\Start-AdminPanel.ps1'), '-Port', $Port -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 2
Start-Process "http://127.0.0.1:$Port"
Write-Host "Admin panel started at http://127.0.0.1:$Port"

