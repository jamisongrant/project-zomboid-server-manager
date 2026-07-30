# Validation

Use this file as the readiness checklist while building the server.

## Completed

- PowerShell scripts parse successfully.
- Runtime directory initialization is idempotent.
- Runtime folders are created under `C:\pz`.
- SteamCMD installed successfully.
- Project Zomboid dedicated server app `380870` installed successfully after SteamCMD completed its first self-update.
- Local config applied into `C:\pz\profile\Server`.
- Server started successfully and bound UDP `16261` and `16262`.
- Watchdog detected the running server as healthy.
- RCON-backed graceful stop worked with `save` then `quit`.
- Save backup created successfully after graceful stop.
- Admin panel backend passed Node syntax validation.
- Admin panel loaded in Edge through Playwright on desktop and mobile viewport sizes with no horizontal overflow.
- Admin panel API read live server state and ran the watchdog action successfully.
- Mod manager UI loaded in Edge and exposed add/save/check/refresh controls.
- Steam Workshop metadata check endpoint returned successfully with zero configured mods.
- `Update-PzMods.ps1` exits safely when no Workshop IDs are configured.
- Imported provided mod pack: 194 Workshop items and 238 Project Zomboid Mod IDs.
- Steam Workshop metadata resolved titles for all 194 imported Workshop items.
- Admin panel loaded the imported pack with 194 rows and 238 load-order IDs.
- PowerShell mod updater helper reads the imported object-shaped `mods.json` schema.
- Join-password hide/show toggle passed browser interaction validation.
- Health, Backups, Logs, Ops, and Settings tabs passed browser smoke validation with no horizontal overflow.
- Player count probe returned 0 players and marked the query reliable.
- Backup listing endpoint returned 1 save backup.
- Log listing endpoint returned local logs successfully.
- Mod preflight reported 194 Workshop items, 238 Mod IDs, and clean status.
- Regression suite `tests\Run-Regression.ps1` passed.
- Release package creation passed.
- Release package excludes `config\server.env` and `config\mods.json`.
- Release package includes `INSTALL-FIRST.ps1`, installer scripts, and regression tests.
- Admin panel `Disable Automation` action returned success without stopping the server.
- Health and Ops tabs expose Enable Automation and Disable Automation controls.
- Open-source readiness pass added README improvements, `CONTRIBUTING.md`, `SECURITY.md`, issue templates, PR template, EditorConfig, and GitHub Actions CI.
- Live regression and static CI-style regression both passed.
- Release package includes GitHub/open-source files and still excludes local secrets/state.
- Regression suite now checks config key parity, package secret exclusions, admin action script references, static admin assets, friend docs, and example mod JSON.
- Docker clean-room package smoke passed with `tests\docker\Test-PzPackageInDocker.ps1`.
- Docker package smoke validates the extracted zip with Node 22, PowerShell 7.4, git, and the non-live regression suite.
- Windows clean-package smoke passed with `tests\package\Test-PzPackage.ps1`.
- Live regression now checks the admin panel root page, state payload shape, backups, logs, and health endpoints.
- Imported downloaded server INI and SandboxVars files into the active profile with timestamped backups.
- Config tab endpoint parsed 144 INI settings and 747 SandboxVars assignments from the active files.
- Join-password hide/show control now renders as a visible CSS eye button.
- Added staged update scripts for prepare, swap/verify/rollback, and manual rollback.
- Mods tab now highlights pending enabled Workshop updates and separates staging from applying.
- Smart mod refresh now uses the staged refresh workflow.
- Added `scripts\install\Test-PzSetup.ps1` and the admin panel `Setup` tab for friend-facing readiness checks.
- Live regression now covers the setup checklist endpoint.
- Added `Setup-Wizard.ps1` as the guided first-run wrapper used by `START-HERE.ps1`.
- Added browser setup wizard modal with defaulted install options and admin-aware firewall/automation choices.
- `START-HERE.ps1` now opens the browser wizard on first run and keeps `Setup-Wizard.ps1` as a fallback.
- Setup wizard defaults now prefill from the active server INI when present, including imported shared config values.
- Added `RUN-SETUP-WIZARD.ps1` as the obvious friend-facing launcher and package entrypoint.
- PowerShell setup wizard now pre-fills from the shared setup defaults used by the browser wizard.

## Next Gates

- Run `Prepare-PzStagedUpdate.ps1` during uptime and verify `C:\pz\staging\server-next` is created.
- Run `Invoke-PzStagedRefresh.ps1` during a maintenance window and verify rollback behavior with a disposable install.
- Run watchdog once with the server running and once after a simulated crash.
- Register scheduled tasks from an elevated PowerShell session.
- Exercise `Refresh-PzMods.ps1` with the imported pack during a maintenance window.
- Install firewall rules from an elevated PowerShell session.
- Exercise restore flow with a disposable backup/world before relying on it in production.
- Test the release zip on a clean Windows machine or VM with Node.js installed.
- Run `INSTALL-FIRST.ps1` or `RUN-SETUP-WIZARD.ps1` from an extracted release zip on a disposable Windows user profile.
- Confirm the Apache-2.0 `LICENSE` and `NOTICE` holder before publishing on GitHub.

## Live Operation Gates

- Confirm router forwarding for UDP `16261`.
- Confirm Windows Firewall allows inbound Project Zomboid traffic.
- Confirm logs are written to `C:\pz\logs`.
- Confirm `config\server.env` remains ignored by Git.
# Validation

Run the full local regression suite:

```powershell
.\tests\Run-Regression.ps1
```

This validates script parsing, admin panel syntax, packaging safety, live admin API health, setup checks, config parsing, and admin API persistence.

Run the focused admin persistence test:

```powershell
.\tests\admin-panel\Test-AdminPanelPersistence.ps1 -BaseUrl "http://127.0.0.1:18787" -StartPanel
```

This starts an isolated admin panel instance, writes temporary local config, then verifies:

- `POST /api/settings` persists `server.ini` values and syncs matching `server.env` values.
- `POST /api/config-files` persists targeted line edits.
- `POST /api/mods` persists `config\mods.json` and syncs `WorkshopItems` / `Mods`.
- The original local `config\server.env` and `config\mods.json` are restored afterward.

Validate a release zip:

```powershell
.\scripts\package\New-PzReleasePackage.ps1
.\tests\package\Test-PzPackage.ps1
```

Validate the package in Docker when available:

```powershell
.\tests\docker\Test-PzPackageInDocker.ps1
```
