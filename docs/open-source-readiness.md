# Open Source Readiness

## Publishing Checklist

- Confirm the repository name and description are clear on GitHub.
- Keep `config\server.env`, `config\mods.json`, `dist\`, saves, backups, logs, SteamCMD, and server runtime files out of Git.
- Publish with `LICENSE`, `NOTICE`, `SECURITY.md`, `SUPPORT.md`, `CONTRIBUTING.md`, issue templates, pull request template, and CI.
- Run `tests\Run-Regression.ps1`.
- Build a release zip with `scripts\package\New-PzReleasePackage.ps1`.
- Run `tests\package\Test-PzPackage.ps1` against the release zip.
- Run `tests\docker\Test-PzPackageInDocker.ps1` when Docker is available.
- Add GitHub release notes that mention the supported Windows/PowerShell/Node.js versions and the `RUN-SETUP-WIZARD.ps1` entrypoint.
- Add screenshots or a short GIF of the admin panel after the first public release is tagged.

## License Choice

This project uses Apache License 2.0. That keeps the project easy to adopt while preserving copyright notices, including a patent grant, and making contribution terms predictable.

The `NOTICE` file identifies `Batch Systems LLC and contributors` as the notice holder. Update that before publishing if the public owner should be a different legal name.

## Recommended GitHub Settings

- Enable private vulnerability reporting.
- Enable Dependabot security updates if dependencies are added later.
- Protect the default branch after the first stable release.
- Use GitHub Releases for packaged zips.
