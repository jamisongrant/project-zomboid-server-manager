---
name: project-zomboid-vanilla-server-builder
description: Build and operate a stable vanilla Project Zomboid dedicated server on Windows from a C:\src project repo with runtime state in C:\pz. Use when planning, implementing, validating, or maintaining SteamCMD install scripts, server config templates, backups, graceful restarts, watchdog recovery, scheduled tasks, update handling, logging, and recovery runbooks for a self-hosted Project Zomboid server.
---

# Project Zomboid Vanilla Server Builder

## Mission

Build a stable, recoverable, vanilla Project Zomboid dedicated server on Windows.

Keep source-controlled automation in `C:\src\project-zomboid-server`. Keep runtime files, saves, backups, logs, and mutable state in `C:\pz`.

The server should be boring to operate: installable, restartable, backed up, updateable, observable, and able to recover after crashes or host reboots.

## Operating Model

Use this path layout:

```text
C:\src\project-zomboid-server
├── config
├── docs
├── scripts
│   ├── install
│   ├── ops
│   └── tasks
├── templates
└── tools

C:\pz
├── steamcmd
├── server
├── profile
├── saves
├── backups
├── logs
├── state
└── staging
```

Use `C:\src\project-zomboid-server` for maintained project assets only. Do not store live saves, SteamCMD downloads, installed server binaries, large logs, or generated backups in the repo.

## Guardrails

- Preserve vanilla gameplay unless the user explicitly asks for mods.
- Prefer PowerShell scripts for Windows operations.
- Use idempotent scripts: rerunning them should be safe.
- Never delete live saves or backups as part of normal install/update/start flows.
- Back up saves before updates, restarts, config migrations, or scheduled maintenance.
- Gracefully stop the server before backup or update when possible.
- Keep secrets, passwords, and admin tokens out of Git.
- Avoid OneDrive-backed runtime paths for live server files.
- Treat networking and firewall changes as host-specific; document them before applying broad changes.

## Phases

### 1. Repository Foundation

Create:

- `.gitignore`
- `README.md`
- `config\server.env.example`
- `config\paths.ps1`
- `docs\architecture.md`
- `docs\operations.md`
- `docs\recovery.md`

Define all mutable paths in one place. Scripts should import the shared path/config file instead of hardcoding paths repeatedly.

### 2. Install Foundation

Create install scripts:

- `scripts\install\Install-SteamCmd.ps1`
- `scripts\install\Install-PzServer.ps1`
- `scripts\install\Initialize-Directories.ps1`

Install Project Zomboid dedicated server through SteamCMD into `C:\pz\server`.

Use the Project Zomboid dedicated server Steam app id `380870` unless current official documentation or Steam metadata indicates otherwise.

### 3. Configuration

Create template files:

- `templates\server.ini.template`
- `templates\servertest_SandboxVars.lua.template`
- `templates\spawnregions.lua.template`

Create config apply script:

- `scripts\ops\Apply-Config.ps1`

Keep user-editable values in `config\server.env` or equivalent local config ignored by Git. Generated server config should land in the runtime profile path, not only in the repo.

### 4. Lifecycle Commands

Create operational scripts:

- `scripts\ops\Start-PzServer.ps1`
- `scripts\ops\Stop-PzServer.ps1`
- `scripts\ops\Restart-PzServer.ps1`
- `scripts\ops\Get-PzServerStatus.ps1`

Start should:

- load config
- verify install paths
- create logs/state directories
- launch the server process
- record enough state for later inspection

Stop should:

- prefer graceful shutdown
- wait for exit
- escalate only after a timeout
- log the shutdown path used

### 5. Backups

Create:

- `scripts\ops\Backup-PzSaves.ps1`
- `scripts\ops\Prune-Backups.ps1`

Backups should be timestamped and written to `C:\pz\backups`.

Backup policy:

- create a backup before update/restart maintenance
- retain enough recent backups for practical rollback
- avoid pruning if backup creation failed
- log backup size, source, destination, and result

### 6. Updates

Create:

- `scripts\ops\Update-PzServer.ps1`

Update should:

- check current server status
- back up saves first
- stop the server gracefully if running
- run SteamCMD update validation
- restart the server if it was running before the update
- log the update result

### 7. Watchdog And Recovery

Create:

- `scripts\ops\Watchdog-PzServer.ps1`

The watchdog should:

- check whether the server process is alive
- optionally check listening ports
- restart the server if it is down and maintenance is not active
- write health state to `C:\pz\state`
- rate-limit restarts to avoid tight crash loops
- produce clear logs under `C:\pz\logs`

Use a maintenance lock file in `C:\pz\state` so scheduled updates and manual work do not fight the watchdog.

### 8. Scheduled Tasks

Create:

- `scripts\tasks\Register-PzScheduledTasks.ps1`
- `scripts\tasks\Unregister-PzScheduledTasks.ps1`

Recommended tasks:

- start server on host boot
- run watchdog every 1-5 minutes
- run daily graceful restart during low-traffic hours
- run daily or pre-maintenance backup
- run optional update window on a defined schedule

Scheduled tasks should call repo scripts by absolute path and log output to `C:\pz\logs`.

### 9. Documentation

Keep docs operational, not ornamental.

Document:

- architecture and paths
- first install
- start/stop/restart/status
- port forwarding and firewall notes
- backup restore procedure
- update procedure
- watchdog behavior
- scheduled tasks
- common failure recovery

## Validation Gates

Before calling the project ready:

- Run directory initialization twice and verify it is idempotent.
- Run install scripts on a clean or partially-created runtime folder.
- Start the server and verify a persistent process exists.
- Stop the server and verify the process exits cleanly.
- Create a backup and verify a restorable archive exists.
- Run update script with the server stopped.
- Run update script with the server running.
- Simulate a crashed process and verify watchdog restarts it.
- Register scheduled tasks and verify they point to existing scripts.
- Confirm logs are written under `C:\pz\logs`.
- Confirm Git status excludes runtime artifacts and local secrets.

## Implementation Style

PowerShell scripts should:

- use `Set-StrictMode -Version Latest`
- use explicit parameters with safe defaults
- fail loudly on invalid paths or missing prerequisites
- return non-zero exit codes on failed operations
- write human-readable logs
- avoid interactive prompts in scheduled-task paths
- keep destructive behavior behind explicit flags

Prefer shared helpers when repeated behavior appears three or more times, especially for logging, path resolution, maintenance locks, and process detection.

## Definition Of Done

The project is done when a user can:

1. Clone or open `C:\src\project-zomboid-server`.
2. Fill in local config from an example.
3. Install SteamCMD and the vanilla server.
4. Apply server config.
5. Start, stop, restart, update, and back up the server through scripts.
6. Register scheduled tasks.
7. Reboot the host and have the server come back.
8. Recover from a server crash through watchdog restart.
9. Restore from a documented backup.

The result should feel like a small dependable service, not a collection of one-off commands.
