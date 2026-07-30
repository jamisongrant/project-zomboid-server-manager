# Operations

Run commands from `C:\src\project-zomboid-server`.

## First Install

```powershell
Copy-Item .\config\server.env.example .\config\server.env
notepad .\config\server.env
.\scripts\install\Initialize-Directories.ps1
.\scripts\install\Install-SteamCmd.ps1
.\scripts\install\Install-PzServer.ps1
.\scripts\ops\Apply-Config.ps1
.\scripts\ops\Start-PzServer.ps1
```

## Daily Commands

```powershell
.\scripts\ops\Get-PzServerStatus.ps1
.\scripts\ops\Restart-PzServer.ps1 -BackupFirst
.\scripts\ops\Backup-PzSaves.ps1
.\scripts\ops\Update-PzServer.ps1
```

`Backup-PzSaves.ps1` expects the server to be stopped so database files are not locked. Use `Restart-PzServer.ps1 -BackupFirst` or `Update-PzServer.ps1` for maintenance flows that stop, back up, then start again.

## Scheduled Tasks

Run this from an elevated PowerShell session:

```powershell
.\scripts\tasks\Register-PzScheduledTasks.ps1
```

To include a weekly update window:

```powershell
.\scripts\tasks\Register-PzScheduledTasks.ps1 -IncludeWeeklyUpdate
```

To include a daily smart mod-refresh task:

```powershell
.\scripts\tasks\Register-PzScheduledTasks.ps1 -IncludeSmartModRefresh
```

Install firewall rules from an elevated PowerShell session:

```powershell
.\scripts\ops\Install-PzFirewallRules.ps1
```

## Networking

Forward the Project Zomboid game port from your router to this host. The default is UDP `16261`, with additional player traffic typically starting at UDP `16262`.

Firewall and router settings are host-specific. Document the final rule names and router mappings after applying them.
