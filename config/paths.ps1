Set-StrictMode -Version Latest

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:DefaultConfigPath = Join-Path $script:ProjectRoot 'config\server.env'

function Get-PzProjectRoot {
    return $script:ProjectRoot
}

function Get-PzDefaultConfigPath {
    return $script:DefaultConfigPath
}

