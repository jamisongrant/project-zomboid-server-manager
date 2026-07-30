Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\PzServer.Common.ps1')

$config = Get-PzConfig
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$rules = @(
    @{ Name = 'Project Zomboid UDP Game'; Port = $config.Port; Protocol = 'UDP' },
    @{ Name = 'Project Zomboid UDP Player'; Port = $config.UdpPort; Protocol = 'UDP' }
)

foreach ($rule in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -DisplayName $rule.Name -Enabled True -Direction Inbound -Action Allow | Out-Null
        Set-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -Protocol $rule.Protocol -LocalPort $rule.Port | Out-Null
    } else {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol $rule.Protocol -LocalPort $rule.Port | Out-Null
    }
}

Write-PzLog -Config $config -Message "Installed firewall rules for UDP $($config.Port) and $($config.UdpPort)." -Name 'ops'

