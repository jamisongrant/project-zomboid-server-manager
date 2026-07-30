# Contributing

Thanks for helping improve the Project Zomboid Server Manager.

## Development Setup

Use Windows with PowerShell and Node.js 20 or newer.

```powershell
cd C:\src\project-zomboid-server
.\tests\Run-Regression.ps1
```

## Guidelines

- Keep runtime state out of the repo.
- Keep `config\server.env` and `config\mods.json` ignored.
- Prefer idempotent PowerShell scripts.
- Do not add secrets, local IP addresses, private passwords, save files, or generated server installs.
- Test UI changes with the admin panel running at `http://127.0.0.1:8787`.
- Contributions are accepted under the Apache License 2.0 unless explicitly stated otherwise.

## Pull Requests

Include:

- What changed
- Why it helps server stability or usability
- Validation performed
- Any manual testing gaps
- Screenshots for admin panel UI changes
