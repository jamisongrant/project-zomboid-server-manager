Set-StrictMode -Version Latest

$script:CommonRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $script:CommonRoot 'config\paths.ps1')

function Read-PzEnvFile {
    param(
        [string]$Path = (Get-PzDefaultConfigPath)
    )

    $values = [ordered]@{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            $trimmed = $line.Trim()
            if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
                continue
            }

            $parts = $trimmed -split '=', 2
            if ($parts.Count -ne 2) {
                throw "Invalid config line in ${Path}: ${line}"
            }

            $values[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    return $values
}

function Get-PzConfig {
    param(
        [string]$ConfigPath = (Get-PzDefaultConfigPath)
    )

    $envValues = Read-PzEnvFile -Path $ConfigPath

    function ValueOrDefault([hashtable]$Values, [string]$Key, [string]$Default) {
        if ($Values.Contains($Key) -and $Values[$Key] -ne '') {
            return $Values[$Key]
        }
        return $Default
    }

    $root = ValueOrDefault $envValues 'PZ_ROOT' 'C:\pz'

    $config = [ordered]@{
        ProjectRoot = Get-PzProjectRoot
        ConfigPath = $ConfigPath
        Root = $root
        SteamCmdDir = ValueOrDefault $envValues 'PZ_STEAMCMD_DIR' (Join-Path $root 'steamcmd')
        ServerDir = ValueOrDefault $envValues 'PZ_SERVER_DIR' (Join-Path $root 'server')
        ProfileDir = ValueOrDefault $envValues 'PZ_PROFILE_DIR' (Join-Path $root 'profile')
        BackupDir = ValueOrDefault $envValues 'PZ_BACKUP_DIR' (Join-Path $root 'backups')
        LogDir = ValueOrDefault $envValues 'PZ_LOG_DIR' (Join-Path $root 'logs')
        StateDir = ValueOrDefault $envValues 'PZ_STATE_DIR' (Join-Path $root 'state')
        StagingDir = ValueOrDefault $envValues 'PZ_STAGING_DIR' (Join-Path $root 'staging')
        AppId = ValueOrDefault $envValues 'PZ_APP_ID' '380870'
        WorkshopAppId = ValueOrDefault $envValues 'PZ_WORKSHOP_APP_ID' '108600'
        ServerName = ValueOrDefault $envValues 'PZ_SERVER_NAME' 'servertest'
        PublicName = ValueOrDefault $envValues 'PZ_PUBLIC_NAME' 'Project Zomboid Vanilla'
        PublicDescription = ValueOrDefault $envValues 'PZ_PUBLIC_DESCRIPTION' 'Vanilla Project Zomboid dedicated server'
        Password = ValueOrDefault $envValues 'PZ_PASSWORD' ''
        AdminPassword = ValueOrDefault $envValues 'PZ_ADMIN_PASSWORD' ''
        RconPassword = ValueOrDefault $envValues 'PZ_RCON_PASSWORD' ''
        MaxPlayers = [int](ValueOrDefault $envValues 'PZ_MAX_PLAYERS' '8')
        MemoryMin = ValueOrDefault $envValues 'PZ_MEMORY_MIN' '2048m'
        MemoryMax = ValueOrDefault $envValues 'PZ_MEMORY_MAX' '4096m'
        Port = [int](ValueOrDefault $envValues 'PZ_PORT' '16261')
        UdpPort = [int](ValueOrDefault $envValues 'PZ_UDP_PORT' '16262')
        RconPort = [int](ValueOrDefault $envValues 'PZ_RCON_PORT' '27015')
        BackupRetentionDays = [int](ValueOrDefault $envValues 'PZ_BACKUP_RETENTION_DAYS' '14')
        WatchdogMinRestartSeconds = [int](ValueOrDefault $envValues 'PZ_WATCHDOG_MIN_RESTART_SECONDS' '300')
        ModWarningSeconds = [int](ValueOrDefault $envValues 'PZ_MOD_WARNING_SECONDS' '60')
        AutoRefreshMods = [bool]::Parse((ValueOrDefault $envValues 'PZ_AUTO_REFRESH_MODS' 'false'))
        ModRefreshWindowStart = ValueOrDefault $envValues 'PZ_MOD_REFRESH_WINDOW_START' '04:00'
        ModRefreshWindowEnd = ValueOrDefault $envValues 'PZ_MOD_REFRESH_WINDOW_END' '05:00'
    }

    return [pscustomobject]$config
}

function Initialize-PzDirectories {
    param(
        [pscustomobject]$Config
    )

    $paths = @(
        $Config.Root,
        $Config.SteamCmdDir,
        $Config.ServerDir,
        $Config.ProfileDir,
        $Config.BackupDir,
        $Config.LogDir,
        $Config.StateDir,
        $Config.StagingDir
    )

    foreach ($path in $paths) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Get-PzLogPath {
    param(
        [pscustomobject]$Config,
        [string]$Name = 'pz-ops'
    )

    Initialize-PzDirectories -Config $Config
    $date = Get-Date -Format 'yyyyMMdd'
    return Join-Path $Config.LogDir "${Name}-${date}.log"
}

function Write-PzLog {
    param(
        [pscustomobject]$Config,
        [string]$Message,
        [string]$Name = 'pz-ops',
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath (Get-PzLogPath -Config $Config -Name $Name) -Value $line
}

function Write-PzStateJson {
    param(
        [pscustomobject]$Config,
        [string]$Name,
        [hashtable]$Data
    )

    Initialize-PzDirectories -Config $Config
    $path = Join-Path $Config.StateDir $Name
    $payload = [ordered]@{}
    foreach ($key in $Data.Keys) {
        $payload[$key] = $Data[$key]
    }
    $payload['updatedAt'] = (Get-Date).ToString('o')
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding ASCII
}

function Get-PzServerExecutable {
    param(
        [pscustomobject]$Config
    )

    $candidates = @(
        (Join-Path $Config.ServerDir 'StartServer64.bat'),
        (Join-Path $Config.ServerDir 'ProjectZomboid64.bat'),
        (Join-Path $Config.ServerDir 'StartServer32.bat')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $candidates[0]
}

function Get-PzPidPath {
    param([pscustomobject]$Config)
    return Join-Path $Config.StateDir 'server.pid'
}

function Get-PzMaintenanceLockPath {
    param([pscustomobject]$Config)
    return Join-Path $Config.StateDir 'maintenance.lock'
}

function Enter-PzMaintenance {
    param(
        [pscustomobject]$Config,
        [string]$Reason
    )

    Initialize-PzDirectories -Config $Config
    $lock = Get-PzMaintenanceLockPath -Config $Config
    Set-Content -LiteralPath $lock -Value ("{0} {1}" -f (Get-Date -Format 's'), $Reason)
}

function Exit-PzMaintenance {
    param([pscustomobject]$Config)

    $lock = Get-PzMaintenanceLockPath -Config $Config
    if (Test-Path -LiteralPath $lock) {
        Remove-Item -LiteralPath $lock -Force
    }
}

function Test-PzMaintenance {
    param([pscustomobject]$Config)

    return Test-Path -LiteralPath (Get-PzMaintenanceLockPath -Config $Config)
}

function Get-PzServerProcess {
    param([pscustomobject]$Config)

    $pidPath = Get-PzPidPath -Config $Config
    if (Test-Path -LiteralPath $pidPath) {
        $pidText = (Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($pidText -match '^\d+$') {
            $process = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
            if ($null -ne $process -and -not $process.HasExited) {
                return $process
            }
        }
    }

    $serverPath = Get-PzServerExecutable -Config $Config
    $serverDir = [System.IO.Path]::GetFullPath($Config.ServerDir)
    $javaProcesses = Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $javaProcesses) {
        if ($null -ne $process.CommandLine -and $process.CommandLine.Contains($serverDir)) {
            return Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        }
        if ($null -ne $process.CommandLine -and $process.CommandLine.Contains('zombie.network.GameServer')) {
            return Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        }
    }

    $cmdProcesses = Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $cmdProcesses) {
        if ($null -ne $process.CommandLine -and $process.CommandLine.Contains($serverPath)) {
            return Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        }
    }

    return $null
}

function Assert-PzSteamCmd {
    param([pscustomobject]$Config)

    $steamCmd = Join-Path $Config.SteamCmdDir 'steamcmd.exe'
    if (-not (Test-Path -LiteralPath $steamCmd)) {
        throw "steamcmd.exe not found at ${steamCmd}. Run scripts\install\Install-SteamCmd.ps1 first."
    }
    return $steamCmd
}

function Invoke-PzRconCommand {
    param(
        [pscustomobject]$Config,
        [string]$Command,
        [int]$TimeoutMilliseconds = 5000
    )

    if ([string]::IsNullOrWhiteSpace($Config.RconPassword)) {
        throw 'PZ_RCON_PASSWORD is not configured.'
    }

    $client = [System.Net.Sockets.TcpClient]::new()
    $client.ReceiveTimeout = $TimeoutMilliseconds
    $client.SendTimeout = $TimeoutMilliseconds
    $client.Connect('127.0.0.1', $Config.RconPort)

    try {
        $stream = $client.GetStream()
        $encoding = [System.Text.Encoding]::ASCII

        function Send-RconPacket {
            param(
                [System.IO.Stream]$Stream,
                [int]$RequestId,
                [int]$Type,
                [string]$Body
            )

            $bodyBytes = $encoding.GetBytes($Body)
            $size = 4 + 4 + $bodyBytes.Length + 2
            $packet = New-Object byte[] (4 + $size)
            [System.BitConverter]::GetBytes($size).CopyTo($packet, 0)
            [System.BitConverter]::GetBytes($RequestId).CopyTo($packet, 4)
            [System.BitConverter]::GetBytes($Type).CopyTo($packet, 8)
            [Array]::Copy($bodyBytes, 0, $packet, 12, $bodyBytes.Length)
            $packet[$packet.Length - 2] = 0
            $packet[$packet.Length - 1] = 0
            $Stream.Write($packet, 0, $packet.Length)
            $Stream.Flush()
        }

        function Read-RconPacket {
            param([System.IO.Stream]$Stream)

            $sizeBytes = New-Object byte[] 4
            $read = $Stream.Read($sizeBytes, 0, 4)
            if ($read -ne 4) {
                throw 'Failed to read RCON packet size.'
            }

            $size = [System.BitConverter]::ToInt32($sizeBytes, 0)
            $payload = New-Object byte[] $size
            $offset = 0
            while ($offset -lt $size) {
                $read = $Stream.Read($payload, $offset, $size - $offset)
                if ($read -le 0) {
                    throw 'RCON connection closed while reading packet.'
                }
                $offset += $read
            }

            $requestId = [System.BitConverter]::ToInt32($payload, 0)
            $type = [System.BitConverter]::ToInt32($payload, 4)
            $bodyLength = [Math]::Max(0, $size - 10)
            $body = $encoding.GetString($payload, 8, $bodyLength).TrimEnd([char]0)

            return [pscustomobject]@{
                RequestId = $requestId
                Type = $type
                Body = $body
            }
        }

        Send-RconPacket -Stream $stream -RequestId 1 -Type 3 -Body $Config.RconPassword
        $authResponse = Read-RconPacket -Stream $stream
        if ($authResponse.RequestId -eq -1) {
            throw 'RCON authentication failed.'
        }

        Send-RconPacket -Stream $stream -RequestId 2 -Type 2 -Body $Command
        $commandResponse = Read-RconPacket -Stream $stream
        return $commandResponse.Body
    } finally {
        $client.Close()
    }
}

function Send-PzServerMessage {
    param(
        [pscustomobject]$Config,
        [string]$Message
    )

    try {
        Invoke-PzRconCommand -Config $Config -Command "servermsg `"$Message`"" | Out-Null
        Write-PzLog -Config $Config -Message "Sent server message: ${Message}" -Name 'ops'
    } catch {
        Write-PzLog -Config $Config -Message "Unable to send server message: $($_.Exception.Message)" -Name 'ops' -Level 'WARN'
    }
}

function Get-PzEnabledWorkshopIds {
    param([pscustomobject]$Config)

    $modsPath = Join-Path $Config.ProjectRoot 'config\mods.json'
    if (Test-Path -LiteralPath $modsPath) {
        $parsed = Get-Content -LiteralPath $modsPath -Raw | ConvertFrom-Json
        $mods = if ($null -ne $parsed.entries) { $parsed.entries } else { $parsed }
        $ids = @()
        foreach ($mod in $mods) {
            if ($mod.enabled -and -not [string]::IsNullOrWhiteSpace($mod.workshopId)) {
                $ids += [string]$mod.workshopId
            }
        }
        return $ids
    }

    $serverIni = Join-Path $Config.ProfileDir "Server\$($Config.ServerName).ini"
    if (-not (Test-Path -LiteralPath $serverIni)) {
        return @()
    }

    $line = Get-Content -LiteralPath $serverIni | Where-Object { $_ -match '^WorkshopItems=' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return @()
    }

    return (($line -split '=', 2)[1] -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Get-PzPlayerCount {
    param([pscustomobject]$Config)

    if ($null -eq (Get-PzServerProcess -Config $Config)) {
        return 0
    }

    try {
        $response = Invoke-PzRconCommand -Config $Config -Command 'players'
        if ($response -match '(?i)players?\s*[:=]\s*(\d+)') {
            return [int]$Matches[1]
        }
        if ($response -match '(?i)no players') {
            return 0
        }

        $lines = $response -split "`r?`n" | Where-Object {
            $trimmed = $_.Trim()
            $trimmed -and $trimmed -notmatch '(?i)^(players|online|username|steamid|--|==)'
        }
        return @($lines).Count
    } catch {
        Write-PzLog -Config $Config -Message "Unable to query player count: $($_.Exception.Message)" -Name 'ops' -Level 'WARN'
        return -1
    }
}

function Test-PzTimeWindow {
    param(
        [string]$Start,
        [string]$End,
        [datetime]$Now = (Get-Date)
    )

    $startTime = [TimeSpan]::Parse($Start)
    $endTime = [TimeSpan]::Parse($End)
    $current = $Now.TimeOfDay

    if ($startTime -le $endTime) {
        return $current -ge $startTime -and $current -le $endTime
    }

    return $current -ge $startTime -or $current -le $endTime
}

function Get-PzTimestamp {
    return Get-Date -Format 'yyyyMMdd-HHmmss'
}
