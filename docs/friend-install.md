# Friend Install

## Requirements

- Windows 10 or newer
- PowerShell
- Node.js 20 or newer
- Router access if friends will connect over the internet

## Install

Extract the release zip to:

```text
C:\src\project-zomboid-server
```

Run PowerShell:

```powershell
cd C:\src\project-zomboid-server
.\RUN-SETUP-WIZARD.ps1
```

The guided setup wizard asks a few questions with defaults, installs the server manager, opens the admin panel, and sends the user to the `Setup` checklist. `START-HERE.ps1` is still available as a browser-first launcher.

If SteamCMD reports `Failed to install app '380870' (Missing configuration)`, rerun the wizard or run `scripts\install\Install-PzServer.ps1`. Current releases retry the Project Zomboid server download automatically.

For a mostly automatic install, run PowerShell as Administrator and use:

```powershell
.\scripts\install\Install-PzManager.ps1 -PublicName "My PZ Server" -JoinPassword "change-me" -StartServer -RegisterAutomation -InstallFirewallRules
```

For a non-technical friend, send them to `docs\STARTUP-GUIDE.md`.

Open:

```text
http://127.0.0.1:8787
```

After the panel opens, click `Setup`. Items marked `TODO` explain the next action. Firewall rules and scheduled automation usually require Administrator permission; the server can still run locally before those optional items are finished.

## Optional Admin Setup

Run PowerShell as Administrator:

```powershell
cd C:\src\project-zomboid-server
.\scripts\ops\Install-PzFirewallRules.ps1
.\scripts\tasks\Register-PzScheduledTasks.ps1 -IncludeSmartModRefresh
```

## Turn Off Automation

From the admin panel, use:

```text
Health > Disable Automation
```

Or run:

```powershell
.\scripts\tasks\Disable-PzAutomation.ps1
```

## Package A Release

```powershell
cd C:\src\project-zomboid-server
.\tests\Run-Regression.ps1
.\scripts\package\New-PzReleasePackage.ps1
```

The release zip excludes local secrets and local mod state.
