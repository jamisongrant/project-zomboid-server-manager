Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

Write-Host ''
Write-Host 'Project Zomboid Manager - Guided Setup'
Write-Host '======================================='
Write-Host ''
Write-Host 'This wizard will walk through the install choices, apply the server config,'
Write-Host 'start the admin panel, and open the setup checklist when it is done.'
Write-Host ''

& .\Setup-Wizard.ps1
