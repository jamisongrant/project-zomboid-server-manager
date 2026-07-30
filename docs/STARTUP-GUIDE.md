# Startup Guide

This guide is for the person running the server.

## First Time

1. Install Node.js 20 or newer from `https://nodejs.org/`.
2. Extract the release zip to:

```text
C:\src\project-zomboid-server
```

3. Double-click `INSTALL-GUI.cmd`.
4. Pick the runtime folder with the Browse button and answer the guided setup questions. Pick the defaults unless you already know you want something different.
5. The admin panel opens to the setup checklist when the wizard finishes.

```text
http://127.0.0.1:8787
```

The wizard asks for the runtime folder, server display name, join password, player count, memory, and whether to start the server. Runtime files default to `C:\pz`, but you can use another drive such as `D:\pz` if the C drive is small. When active server config files already exist, the wizard pre-fills from those values. If PowerShell is running as Administrator, it can also offer firewall rules and scheduled automation. You can change these later from the admin panel.

If SteamCMD reports `Failed to install app '380870' (Missing configuration)`, run the wizard again or run `scripts\install\Install-PzServer.ps1`. This is usually a temporary SteamCMD update response; the installer retries automatically in current releases.

To launch the PowerShell fallback wizard instead:

```powershell
.\RUN-SETUP-WIZARD.ps1
```

## Normal Use

Open the admin panel:

```powershell
.\Open-AdminPanel.ps1
```

Close the admin panel:

```powershell
.\Stop-AdminPanel.ps1
```

You can also close it inside the admin panel:

```text
Health > Close Admin Panel
```

Closing the admin panel does not stop the Project Zomboid server.

## First Mod Activation

If you add a large mod pack, the server may show `Starting` for several minutes while Project Zomboid downloads Workshop items. This is normal. The server is ready when the badge changes to `Ready`.

## Turn Off Background Automation

Use:

```text
Health > Disable Automation
```

This turns off scheduled background tasks. It does not delete saves or backups.

## Turn Automation Back On

Use:

```text
Health > Enable Automation
```

If Windows asks for Administrator permission, open PowerShell as Administrator and run:

```powershell
.\scripts\tasks\Register-PzScheduledTasks.ps1 -IncludeSmartModRefresh
```

## Internet Hosting

For friends outside your house, you still need router port forwarding for UDP `16261` and UDP `16262`.

Run PowerShell as Administrator to install Windows Firewall rules:

```powershell
.\scripts\ops\Install-PzFirewallRules.ps1
```
