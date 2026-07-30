# Release Checklist

- Run `tests\Run-Regression.ps1`.
- Create a package with `scripts\package\New-PzReleasePackage.ps1`.
- Extract the zip into a clean folder.
- Run `INSTALL-FIRST.ps1`, `RUN-SETUP-WIZARD.ps1`, or `scripts\install\Install-PzManager.ps1`.
- Confirm `config\server.env` is generated and ignored by Git.
- Confirm the admin panel opens at `http://127.0.0.1:8787`.
- Confirm `START-HERE.ps1` opens the admin panel.
- Confirm `RUN-SETUP-WIZARD.ps1` launches the guided setup flow.
- Confirm `Open-AdminPanel.ps1` and `Stop-AdminPanel.ps1` work.
- Confirm `Health > Close Admin Panel` stops only the panel, not the game server.
- Confirm `Health` shows server status and player count.
- Confirm `Disable Automation` can be clicked without stopping the server.
- Confirm firewall and scheduled tasks are documented as Administrator-only steps.
- Confirm `Health > Disable Automation` succeeds and leaves the server running.
- Confirm `dist\*.zip` does not include `config\server.env` or `config\mods.json`.
- Run `tests\package\Test-PzPackage.ps1` to validate the extracted package on Windows.
- Run `tests\docker\Test-PzPackageInDocker.ps1` when Docker is available to validate the extracted package in a clean Linux container.
- Run one clean Windows install smoke from the release zip before handing it to someone else.
