# Architecture

The project uses a two-part layout.

`C:\src\project-zomboid-server` is the maintained repo. It contains scripts, templates, docs, and local config examples.

`C:\pz` is runtime state. It contains SteamCMD, the installed dedicated server, generated server profile files, saves, backups, logs, and watchdog state.

This split keeps Git clean and keeps live server files away from OneDrive syncing.

## Main Flows

- Install: initialize directories, install SteamCMD, install Project Zomboid dedicated server.
- Configure: render templates into `C:\pz\profile\Server`.
- Operate: start, stop, restart, status.
- Protect: create backups before maintenance and prune old backups.
- Recover: watchdog restarts a down server unless a maintenance lock exists.
- Automate: scheduled tasks call the repo scripts by absolute path.

