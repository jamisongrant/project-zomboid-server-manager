param(
    [int]$Port = 8787
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
if ($null -eq $nodeCommand) {
    throw 'Node.js is required to run the admin panel. Install Node.js 20 or newer, then re-run this script.'
}
$node = $nodeCommand.Source
$env:PZ_ADMIN_PANEL_PORT = [string]$Port

Push-Location $PSScriptRoot
try {
    & $node .\server.js
} finally {
    Pop-Location
}
