# Recovery

## Crash Recovery

The watchdog script checks for a running server process. If the server is down and no maintenance lock exists, it restarts the server and writes health state to `C:\pz\state\watchdog-health.json`.

Manual check:

```powershell
.\scripts\ops\Watchdog-PzServer.ps1
```

## Restore From Backup

1. Stop the server.
2. Make a copy of the current `C:\pz\profile\Saves` folder if it exists.
3. Extract the desired `C:\pz\backups\pz-saves-*.zip`.
4. Restore the extracted `Saves` folder to `C:\pz\profile\Saves`.
5. Start the server.

```powershell
.\scripts\ops\Stop-PzServer.ps1 -Force
```

Do not delete old backups until the restored world has been verified in game.

## Graceful Shutdown

`Stop-PzServer.ps1` uses RCON to send `save` and then `quit`. If RCON is unavailable, it falls back to process shutdown and only forces termination when called with `-Force` after the timeout expires.
