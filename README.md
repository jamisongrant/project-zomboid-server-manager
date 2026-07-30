# Project Zomboid Server Manager

Windows admin panel and automation toolkit for self-hosted Project Zomboid dedicated servers.

This project helps a local server owner install, configure, monitor, back up, update, and recover a Project Zomboid dedicated server without living in config files all day. The admin panel runs locally at `http://127.0.0.1:8787` and is designed for a single trusted machine.

Project files can live wherever you extract the release zip. Runtime server files, saves, logs, backups, and state default to `C:\pz`, and the setup wizard can point them at another drive such as `D:\pz`.

## What It Does

- Installs and updates the Project Zomboid dedicated server through SteamCMD
- Provides a local system admin panel for server controls and settings
- Starts, stops, restarts, backs up, restores, and watches the server
- Manages server INI and SandboxVars settings from a searchable UI
- Tracks Workshop mod metadata and highlights pending updates
- Supports staged blue/green-style refreshes with rollback copies
- Defers smart mod refreshes around player activity and maintenance windows
- Registers optional Windows scheduled tasks for hands-off operation
- Adds optional Windows Firewall rules for hosted play
- Builds friend-ready release zips that exclude local secrets and runtime state

## Requirements

- Windows 10 or newer
- PowerShell 5.1 or newer
- Node.js 20 or newer for the admin panel
- Router access if friends will connect from outside your home network

## Quick Start

Download `PzManagerSetup-*.exe` from the latest release, double-click it, choose an install folder, and continue through the GUI wizard.

The release zip is still available as a fallback. If you use the zip, extract it to:

```text
C:\src\project-zomboid-server
```

Then double-click:

```text
INSTALL-FIRST.cmd
```

Or run the GUI directly:

```powershell
cd C:\src\project-zomboid-server
.\INSTALL-GUI.ps1
```

The GUI wizard asks for the runtime folder, server name, join password, player count, memory, firewall/automation options, and whether to start the server. It includes a folder picker for the runtime location and pre-fills from existing Project Zomboid server files when they are present.

When setup finishes, open:

```text
http://127.0.0.1:8787
```

For the easiest full setup, run PowerShell as Administrator before launching the wizard. Administrator mode is only needed for Windows Firewall rules and scheduled automation.

## Daily Use

Open the admin panel:

```powershell
.\Open-AdminPanel.ps1
```

Close only the admin panel:

```powershell
.\Stop-AdminPanel.ps1
```

Closing the admin panel does not stop the Project Zomboid server.

## Updating

Run the latest `PzManagerSetup-*.exe` and choose the existing manager install folder. Existing local config, mod state, runtime files, saves, logs, backups, and staging files are preserved; the installer opens the admin panel instead of rerunning first-time setup.

Use the installer for updates. The zip is intended for manual inspection or recovery, not for extracting over an existing install.

## Admin Panel Controls

- `Overview`: server status, player count, recent health, and primary actions
- `Setup`: readiness checklist and first-run setup guidance
- `Settings`: common server settings such as name, passwords, ports, memory, and player limits
- `Config`: searchable editor and importer for the active server INI and SandboxVars files
- `Mods`: Workshop item list, load order, metadata checks, pending updates, staging, and refresh actions
- `Health`: watchdog status, automation controls, firewall/setup checks, and admin panel shutdown
- `Backups`: save backup list and restore entry points
- `Logs`: local manager and server log viewing
- `Ops`: direct operational actions for start, stop, restart, update, backup, rollback, and staged refresh
- `Output`: command output from the most recent admin action

## Mod Updates And Uptime

Project Zomboid servers still need a restart when server-side mods change, and players may also need Steam Workshop updates on their own machines. This manager reduces the outage window by staging server updates ahead of time, warning players, stopping cleanly, swapping the staged server into place, checking health, and rolling back if the refreshed server does not come up cleanly.

This is not true hot swapping or sharding. The goal is a short, predictable maintenance blip instead of a manual teardown.

## Manual Install

The wizard is the recommended path. For manual setup:

1. Copy `config\server.env.example` to `config\server.env`.
2. Edit `config\server.env` for your runtime folder, server name, password, admin password, RCON password, and memory.
3. Run `scripts\install\Initialize-Directories.ps1`.
4. Run `scripts\install\Install-SteamCmd.ps1`.
5. Run `scripts\install\Install-PzServer.ps1`.
6. Run `scripts\ops\Apply-Config.ps1`.
7. Run `scripts\ops\Start-PzServer.ps1`.

## Package A Release

```powershell
.\tests\Run-Regression.ps1
.\scripts\package\New-PzReleasePackage.ps1
.\scripts\package\New-PzReleaseInstaller.ps1
```

Release zips and Windows installer exes are written to `dist\`. They exclude local secrets/state such as `config\server.env` and `config\mods.json`.

## More Docs

- `docs\STARTUP-GUIDE.md`: non-technical first-run guide
- `docs\friend-install.md`: sharing/installing a release zip
- `docs\admin-panel.md`: admin panel behavior
- `docs\operations.md`: daily server operations
- `docs\recovery.md`: backup and restore guidance
- `docs\open-source-readiness.md`: publishing checklist

## Project Status

This project is community tooling and is not affiliated with, endorsed by, or sponsored by The Indie Stone, Project Zomboid, Valve, or Steam.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE` and `NOTICE`.
