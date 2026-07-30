# Support

Project Zomboid Server Manager is community tooling for local Windows server administration.

## Before Opening An Issue

1. Run the setup checklist in the admin panel.
2. Run the regression suite:

```powershell
.\tests\Run-Regression.ps1
```

3. Check `docs\STARTUP-GUIDE.md`, `docs\operations.md`, and `docs\recovery.md`.

## Where To Ask

- Use GitHub issues for reproducible bugs and focused feature requests.
- Do not post passwords, RCON secrets, public IP addresses, save archives, or private Workshop collections.
- Include sanitized logs, Windows version, Node.js version, and whether PowerShell was run as Administrator.

## Scope

This project can help manage the local server lifecycle, config, backups, mods, and staged refreshes. It cannot force player clients to update Workshop mods, bypass Project Zomboid server restart requirements, or manage router port forwarding automatically.
