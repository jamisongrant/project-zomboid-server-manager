# Admin Panel

The local admin panel runs from `tools\admin-panel` and binds to `127.0.0.1`.

Start it with:

```powershell
cd C:\src\project-zomboid-server
.\tools\admin-panel\Start-AdminPanel.ps1
```

Open:

```text
http://127.0.0.1:8787
```

The panel can:

- view server status
- review setup readiness from the `Setup` tab
- start, stop, restart, update, back up, and run watchdog
- edit common server settings in the active file under `C:\pz\profile\Server`
- edit all parsed server INI and SandboxVars assignments from the `Config` tab
- import a replacement server INI or SandboxVars file from the `Config` tab with an automatic backup
- manage enabled Workshop IDs and Mod IDs
- check Steam Workshop metadata for upstream mod updates
- run a mod refresh flow that stops, backs up, updates Workshop items, restarts, and verifies health
- preserve a separate Mod ID load order for packs where one Workshop item exposes multiple PZ Mod IDs
- show pending enabled mod updates and guide staging before applying them
- show health, player count, watchdog state, backup count, and mod preflight status
- list backups and restore a selected backup
- list and tail local server/admin logs
- install Windows Firewall rules when the panel is run from an elevated context
- run a smart mod refresh that defers when players are online or outside the refresh window
- prepare a staged server update before downtime, then swap it in with rollback support

Mod changes update `WorkshopItems` and `Mods` in `server.ini`. Restart the server after saving mod changes.

The `Config` tab is for deeper server tuning. It loads the active server INI and SandboxVars files, shows searchable key/value rows with nearby comments, and saves only changed rows. Each save creates a timestamped backup in `C:\pz\backups` before writing.

The `Setup` tab runs the same lightweight checks as `scripts\install\Test-PzSetup.ps1`: Node.js, local config, passwords, SteamCMD, installed server runtime, active server config files, firewall rules, scheduled automation, admin panel status, and staged-update readiness. Optional hosting hardening can show as TODO without blocking core local use.

Large packs should be represented as:

- Workshop entries: one row per Steam Workshop item for metadata/update tracking.
- Mod ID load order: the exact semicolon-separated `Mods=` list Project Zomboid should load.

## Mod Refresh

Project Zomboid generally requires the server to restart before updated Workshop content is safely active. The panel makes this a short controlled maintenance pulse instead of a manual rebuild:

1. Check Workshop metadata.
2. Review pending enabled updates in the Mods tab.
3. Click `Stage Pending Updates` to prepare files before downtime.
4. Click `Apply Staged Refresh` during the refresh window.
5. The server warns players, stops through RCON, backs up saves, swaps staged files in, starts again, and runs watchdog verification.

Set `PZ_MOD_WARNING_SECONDS` in `config\server.env` to control the warning window.

Set `PZ_MOD_CHECK_MINUTES` to `5`, `10`, `15`, `30`, or `60` for the Workshop update check cadence. Set `PZ_MOD_RESTART_INTERVAL_MINUTES` to `15`, `30`, or `60` to cap how often an automatic restart can occur.

Set `PZ_AUTO_REFRESH_MODS=true` only after the automatic Workshop update flow has been tested with your mod pack. Automation stages updates while the server is live, warns players for `PZ_MOD_WARNING_SECONDS`, swaps the staged server, then verifies startup and rolls back if recovery fails.

Players may still need Steam Workshop to update their local client files before joining after a mod update. The manager can shorten and protect the server-side maintenance window, but it cannot force client Workshop updates.

## Staged Updates

Use staged updates when you want most download/validation work to happen before the outage:

1. Click `Prepare Staged Update`.
2. SteamCMD installs the next server build into `C:\pz\staging\server-next` and pre-downloads enabled Workshop items.
3. Click `Staged Refresh` during a maintenance window.
4. The manager warns players, stops the server, backs up saves, moves the current server to `C:\pz\staging\server-rollback`, moves the staged server into `C:\pz\server`, starts the server, and runs watchdog verification.
5. If verification fails, it stops the failed server, restores the rollback directory, and starts the previous build again.

This is not true hot swapping. Players still disconnect during the stop/start window, but the expensive update work is moved before the outage.
