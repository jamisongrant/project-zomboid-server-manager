# Security Policy

## Supported Scope

This project is intended for local administration of a Project Zomboid server on Windows. The admin panel binds to `127.0.0.1` by default and should not be exposed directly to the internet.

## Reporting Issues

Please report security issues privately if the hosting platform supports private vulnerability reporting. Avoid posting live server passwords, public IP addresses, RCON passwords, or save archives in public issues.

If private reporting is not configured yet, open a minimal public issue that says a security report is available, but do not include exploit details or secrets.

## Hardening Notes

- Keep `config\server.env` private.
- Use a strong RCON password.
- Keep RCON bound to localhost.
- Do not port-forward the admin panel.
- Prefer a VPN or remote desktop for off-machine administration.
- Review firewall rules before opening ports.
- Keep the Project Zomboid server, SteamCMD content, Node.js, and Windows updated.
