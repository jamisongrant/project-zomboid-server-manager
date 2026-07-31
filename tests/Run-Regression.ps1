param(
    [switch]$SkipLiveApi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$failures = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    try {
        & $Script
        Write-Host "[PASS] $Name"
    } catch {
        $failures.Add("${Name}: $($_.Exception.Message)")
        Write-Host "[FAIL] $Name - $($_.Exception.Message)"
    }
}

function Invoke-CheckedNative {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "${FilePath} exited with code ${LASTEXITCODE}."
    }
}

function Get-EnvKeysFromText {
    param([string]$Text)

    $matches = [regex]::Matches($Text, '(?m)^\s*(PZ_[A-Z0-9_]+)\s*=')
    return @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Get-EnvValueFromText {
    param(
        [string]$Text,
        [string]$Key
    )

    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('#') -or -not $trimmed.Contains('=')) {
            continue
        }

        $parts = $trimmed -split '=', 2
        if ($parts[0].Trim() -eq $Key) {
            return $parts[1].Trim()
        }
    }

    return $null
}

Set-Location $projectRoot

Add-Check 'PowerShell scripts parse' {
    $errors = @()
    Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($err in $parseErrors) {
            $errors += "$($_.FullName):$($err.Extent.StartLineNumber) $($err.Message)"
        }
    }
    if ($errors.Count -gt 0) {
        throw ($errors -join "`n")
    }
}

Add-Check 'PowerShell scripts avoid newer crypto-only APIs' {
    $matches = @(Get-ChildItem -Recurse -Filter *.ps1 |
        Where-Object { $_.FullName -notmatch '\\dist\\' } |
        Select-String -Pattern 'RandomNumberGenerator\]::Fill')
    if ($matches.Count -gt 0) {
        throw 'Use RandomNumberGenerator.Create().GetBytes(...) for Windows PowerShell 5.1 compatibility.'
    }
}

Add-Check 'Node admin backend syntax' {
    Invoke-CheckedNative -FilePath 'node' -Arguments @('--check', './tools/admin-panel/server.js')
}

Add-Check 'Node admin frontend syntax' {
    Invoke-CheckedNative -FilePath 'node' -Arguments @('--check', './tools/admin-panel/public/app.js')
}

Add-Check 'Friend launcher scripts exist' {
    foreach ($script in @('INSTALL-GUI.cmd', 'INSTALL-GUI.ps1', 'RUN-SETUP-WIZARD.ps1', 'START-HERE.ps1', 'Setup-Wizard.ps1', 'Open-AdminPanel.ps1', 'Stop-AdminPanel.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $script))) {
            throw "Missing $script"
        }
    }
}

Add-Check 'Example config is complete and safe' {
    $examplePath = Join-Path $projectRoot 'config/server.env.example'
    $example = Get-Content -LiteralPath $examplePath -Raw
    $keys = Get-EnvKeysFromText -Text $example
    $required = @(
        'PZ_ROOT',
        'PZ_STEAMCMD_DIR',
        'PZ_SERVER_DIR',
        'PZ_PROFILE_DIR',
        'PZ_BACKUP_DIR',
        'PZ_LOG_DIR',
        'PZ_STATE_DIR',
        'PZ_STAGING_DIR',
        'PZ_APP_ID',
        'PZ_WORKSHOP_APP_ID',
        'PZ_SERVER_NAME',
        'PZ_PUBLIC_NAME',
        'PZ_PUBLIC_DESCRIPTION',
        'PZ_PASSWORD',
        'PZ_ADMIN_PASSWORD',
        'PZ_RCON_PASSWORD',
        'PZ_MAX_PLAYERS',
        'PZ_MEMORY_MIN',
        'PZ_MEMORY_MAX',
        'PZ_PORT',
        'PZ_UDP_PORT',
        'PZ_RCON_PORT',
        'PZ_BACKUP_RETENTION_DAYS',
        'PZ_LOG_RETENTION_DAYS',
        'PZ_WATCHDOG_MIN_RESTART_SECONDS',
        'PZ_MOD_WARNING_SECONDS',
        'PZ_AUTO_REFRESH_MODS',
        'PZ_MOD_REFRESH_WINDOW_START',
        'PZ_MOD_REFRESH_WINDOW_END'
    )

    foreach ($key in $required) {
        if ($keys -notcontains $key) {
            throw "Missing $key in config/server.env.example."
        }
    }

    if ((Get-EnvValueFromText -Text $example -Key 'PZ_ADMIN_PASSWORD') -ne 'change-this-before-start' -or
        (Get-EnvValueFromText -Text $example -Key 'PZ_RCON_PASSWORD') -ne 'change-this-before-start') {
        throw 'Example admin/RCON passwords must stay placeholder-only.'
    }
}

Add-Check 'Installer and admin panel agree on env keys' {
    $exampleKeys = Get-EnvKeysFromText -Text (Get-Content -LiteralPath (Join-Path $projectRoot 'config/server.env.example') -Raw)
    $installerKeys = Get-EnvKeysFromText -Text (Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/install/Install-PzManager.ps1') -Raw)
    $serverJs = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/server.js') -Raw
    $adminKeys = @([regex]::Matches($serverJs, "'(PZ_[A-Z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

    foreach ($key in $exampleKeys) {
        if ($installerKeys -notcontains $key) {
            throw "Installer does not write $key."
        }
        if ($adminKeys -notcontains $key) {
            throw "Admin panel env order does not include $key."
        }
    }
}

Add-Check 'Installer supports configurable runtime root' {
    $installer = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/install/Install-PzManager.ps1') -Raw
    $wizard = Get-Content -LiteralPath (Join-Path $projectRoot 'Setup-Wizard.ps1') -Raw
    $adminIndex = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/index.html') -Raw
    $adminServer = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/server.js') -Raw

    foreach ($text in @($installer, $wizard, $adminIndex, $adminServer)) {
        if ($text -notmatch 'RuntimeRoot|runtimeRoot|wizardRuntimeRoot') {
            throw 'Runtime root must be exposed through installer and setup wizard paths.'
        }
    }
    if ($installer -notmatch 'PZ_ROOT=\$runtime') {
        throw 'Installer must derive PZ_ROOT from the selected runtime root.'
    }
    if ($installer -notmatch 'server\\jre64\\bin\\java\.exe' -or $installer -notmatch 'Existing server files were requested') {
        throw 'Installer must verify server runtime files before honoring SkipServerInstall.'
    }
}

Add-Check 'Mod example JSON parses' {
    $mods = Get-Content -LiteralPath (Join-Path $projectRoot 'config/mods.example.json') -Raw | ConvertFrom-Json
    if (@($mods).Count -lt 1) {
        throw 'config/mods.example.json should contain at least one example entry.'
    }
    foreach ($field in @('name', 'workshopId', 'modId', 'enabled')) {
        if (-not ($mods[0].PSObject.Properties.Name -contains $field)) {
            throw "Example mod is missing $field."
        }
    }
}

Add-Check 'Admin panel action scripts exist' {
    $serverJs = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/server.js') -Raw
    $matches = [regex]::Matches($serverJs, "\['([^']+\.ps1)'")
    foreach ($match in $matches) {
        $relative = $match.Groups[1].Value.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative))) {
            throw "Admin panel references missing script $($match.Groups[1].Value)."
        }
    }
}

Add-Check 'Mod and staged workflows publish progress state' {
    $common = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/lib/PzServer.Common.ps1') -Raw
    $updateMods = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/ops/Update-PzMods.ps1') -Raw
    $prepareStaged = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/ops/Prepare-PzStagedUpdate.ps1') -Raw
    $stagedRefresh = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/ops/Invoke-PzStagedRefresh.ps1') -Raw
    $serverJs = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/server.js') -Raw

    foreach ($required in @('Write-PzStateJson', 'ConvertTo-Json', 'updatedAt')) {
        if ($common -notmatch [regex]::Escape($required)) {
            throw "Common helpers must include $required."
        }
    }
    foreach ($required in @('mod-update.json', 'phase', 'completed', 'currentWorkshopId', 'restartRecommended', 'restartReason')) {
        if ($updateMods -notmatch [regex]::Escape($required)) {
            throw "Mod update script must publish $required."
        }
    }
    foreach ($required in @('staged-update-progress.json', 'safeToApply', 'stageServerDir', 'preparing-mods', 'restartReason')) {
        if ($prepareStaged -notmatch [regex]::Escape($required)) {
            throw "Staged preparation must publish $required."
        }
    }
    foreach ($required in @('Write-StagedRefreshProgress', 'warning-players', 'stopping-server', 'swapping', 'health-check', 'rolling-back')) {
        if ($stagedRefresh -notmatch [regex]::Escape($required)) {
            throw "Staged refresh must publish $required."
        }
    }
    foreach ($required in @('modUpdate', 'restartRecommendation', 'automationTasksSummary', 'normalizeSetupCheck', 'Serving this page from PID', 'PZ Vanilla *', 'LastTaskResult', 'buildRestartRecommendation', 'staged-update-progress.json', 'backgroundActions', 'accepted')) {
        if ($serverJs -notmatch [regex]::Escape($required)) {
            throw "Admin health API must expose $required."
        }
    }
    if ($serverJs -notmatch "stagedRefresh: \['scripts\\\\ops\\\\Invoke-PzStagedRefresh.ps1', '-SkipPrepare'\]") {
        throw 'Apply staged refresh must use the already prepared staged build.'
    }
}

Add-Check 'Admin settings persist across apply config' {
    $serverJs = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/server.js') -Raw
    $appJs = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/app.js') -Raw
    $index = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/index.html') -Raw

    foreach ($mapping in @('PZ_PUBLIC_NAME', 'PZ_PUBLIC_DESCRIPTION', 'PZ_PASSWORD', 'PZ_MAX_PLAYERS', 'PZ_PORT', 'PZ_UDP_PORT')) {
        if ($serverJs -notmatch [regex]::Escape($mapping)) {
            throw "Settings saves must sync $mapping into server.env."
        }
    }
    if ($serverJs -notmatch 'applyConfigRestart') {
        throw 'Admin panel must expose an apply config then restart action.'
    }
    if ($index -notmatch 'applyConfigRestart') {
        throw 'Apply With Restart button must run applyConfigRestart.'
    }
    if ($appJs -notmatch 'settingsDirty' -or $appJs -notmatch 'modsDirty' -or $appJs -notmatch 'hasConfigChanges') {
        throw 'Admin frontend must not auto-refresh over in-progress edits.'
    }
    if ($serverJs -notmatch 'effectiveModState' -or $serverJs -notmatch 'modStateFromIni' -or $serverJs -notmatch 'modStateSource') {
        throw 'Admin backend must recover mod state from server.ini when mods.json is missing.'
    }
    foreach ($required in @('modRecoveryCandidates', 'normalizeModLoadOrder', 'bestRecoverySource', 'backupRecoveryCount', 'repairedFrom', 'No WorkshopItems or Mods were found in the active server.ini or config backups')) {
        if ($serverJs -notmatch [regex]::Escape($required)) {
            throw "Admin backend must support backup-based mod recovery: $required"
        }
    }
    foreach ($required in @('assertNoDangerousModWipe', 'Refusing to save an empty WorkshopItems list', 'Refusing to save an empty Mods load order')) {
        if ($serverJs -notmatch [regex]::Escape($required)) {
            throw "Admin backend must guard against accidental mod wipes: $required"
        }
    }
    if ($appJs -notmatch 'Recovered from server.ini') {
        throw 'Admin frontend must explain recovered mod state.'
    }
    foreach ($required in @('config backup', 'Best recovery source', 'bestRecoveryWorkshopCount', 'bestRecoverySource', 'No Repair Source Found', 'save backups do not include WorkshopItems')) {
        if ($appJs -notmatch [regex]::Escape($required)) {
            throw "Admin frontend must explain backup-based mod recovery: $required"
        }
    }
}

Add-Check 'Admin persistence test exists' {
    $testPath = Join-Path $projectRoot 'tests/admin-panel/Test-AdminPanelPersistence.ps1'
    if (-not (Test-Path -LiteralPath $testPath)) {
        throw 'Missing admin panel persistence test.'
    }

    $test = Get-Content -LiteralPath $testPath -Raw
    foreach ($required in @('/api/settings', '/api/config-files', '/api/mods', 'PZ_PUBLIC_NAME=After Name', 'WorkshopItems=123456')) {
        if ($test -notmatch [regex]::Escape($required)) {
            throw "Admin persistence test must cover $required."
        }
    }
    foreach ($required in @('modStateSource', 'modDiagnostics', '/api/mods/repair', 'RecoveredA', 'WorkshopItems=111;222', '127.0.0.1:18787')) {
        if ($test -notmatch [regex]::Escape($required)) {
            throw "Admin persistence test must cover recovered mod state: $required."
        }
    }
}

Add-Check 'Admin static assets are wired' {
    $index = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/index.html') -Raw
    foreach ($asset in @('styles.css', 'app.js')) {
        if ($index -notmatch [regex]::Escape($asset)) {
            throw "index.html does not reference $asset."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "tools/admin-panel/public/$asset"))) {
            throw "Missing admin asset $asset."
        }
    }
}

Add-Check 'Admin UI explains status and risky actions' {
    $index = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/index.html') -Raw
    $appJs = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/app.js') -Raw
    $styles = Get-Content -LiteralPath (Join-Path $projectRoot 'tools/admin-panel/public/styles.css') -Raw

    foreach ($required in @('nextStepPanel', 'statusMeaning', 'joinInfo', 'activeActionBanner', 'guidance-panel', 'Advanced Actions', 'modRecoveryPanel', 'Repair From server.ini', 'Restart Admin Panel', 'data-help-actions', 'actionHelpModal', 'Action Help', 'Recent Activity', 'Grooming Forecast', 'backupForecast', 'Prune Logs', 'Mod Update Progress', 'Blue/Green State', 'Restart Recommendation', 'Automation Status', 'automationState')) {
        if ($index -notmatch [regex]::Escape($required)) {
            throw "Admin UI must include $required."
        }
    }
    foreach ($required in @('renderNextStep', 'renderModRecoveryPanel', 'renderJobs', 'renderGrooming', 'renderModUpdateProgress', 'renderStagedHealth', 'stagedReadiness', 'Apply readiness', 'Review meaning', 'Re-stage fresh before applying', 'renderRestartJustification', 'renderAutomationStatus', 'taskResultText', 'renderActiveActionBanner', 'setActionBusy', 'refreshHealthOnly', 'pollActionJob', 'started in the background', 'openActionHelp', 'closeActionHelp', 'actionDescriptions', 'Smart mod refresh', 'The Project Zomboid server keeps running', 'Apply config + restart', 'Server is starting', '/api/mods/repair')) {
        if ($appJs -notmatch [regex]::Escape($required)) {
            throw "Admin frontend must include explanatory behavior for $required."
        }
    }
    foreach ($required in @('.guidance-panel', '.status-explainer', '.active-action-banner', '.help-link', '.action-help-modal', '.action-help-card', '.monitor-panel', '.job-row', '.automation-row', '.review-row', '.progress-bar', '.state-pill', '.status-table', 'button.busy')) {
        if ($styles -notmatch [regex]::Escape($required)) {
            throw "Admin styles must include $required."
        }
    }
}

Add-Check 'Package script excludes local secrets' {
    $packageScript = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/package/New-PzReleasePackage.ps1') -Raw
    foreach ($secret in @('config\server.env', 'config\mods.json', '.git')) {
        if ($packageScript -notmatch [regex]::Escape($secret)) {
            throw "Package script does not explicitly remove $secret."
        }
    }
    if ($packageScript -notmatch 'INSTALL-FIRST\.ps1') {
        throw 'Package script must create INSTALL-FIRST.ps1.'
    }
    if ($packageScript -notmatch 'INSTALL-FIRST\.cmd') {
        throw 'Package script must create INSTALL-FIRST.cmd.'
    }
    if ($packageScript -notmatch 'RUN-SETUP-WIZARD\.ps1') {
        throw 'Package script must include the guided setup launcher.'
    }
    if ($packageScript -notmatch 'INSTALL-GUI\.ps1') {
        throw 'Package script must include the GUI setup launcher.'
    }
    foreach ($publicFile in @('LICENSE', 'NOTICE', 'SUPPORT.md')) {
        if ($packageScript -notmatch [regex]::Escape("'$publicFile'")) {
            throw "Package script must include $publicFile."
        }
    }
}

Add-Check 'Windows installer builder is present' {
    $installerScriptPath = Join-Path $projectRoot 'scripts/package/New-PzReleaseInstaller.ps1'
    if (-not (Test-Path -LiteralPath $installerScriptPath)) {
        throw 'Missing scripts/package/New-PzReleaseInstaller.ps1.'
    }

    $installerScript = Get-Content -LiteralPath $installerScriptPath -Raw
    foreach ($required in @('iexpress.exe', 'PzManagerSetup', 'PzManager-Setup.cmd', 'PzManager-Setup.ps1', 'INSTALL-FIRST.cmd', 'ExecutionPolicy')) {
        if ($installerScript -notmatch [regex]::Escape($required)) {
            throw "Installer builder does not include $required."
        }
    }
}

Add-Check 'Windows installer update path preserves local state' {
    $installerScript = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/package/New-PzReleaseInstaller.ps1') -Raw
    foreach ($required in @(
        'config\server.env',
        'config\mods.json',
        'Open-AdminPanel.ps1',
        'INSTALL-FIRST.cmd',
        'runtime files, saves, logs, and backups were preserved',
        'Copy-Item -LiteralPath $source -Destination $target -Force'
    )) {
        if ($installerScript -notmatch [regex]::Escape($required)) {
            throw "Installer update path must include: $required"
        }
    }
}

Add-Check 'Friend docs are present' {
    foreach ($doc in @('README.md', 'docs/STARTUP-GUIDE.md', 'docs/friend-install.md', 'docs/release-checklist.md', 'SECURITY.md', 'SUPPORT.md', 'LICENSE', 'NOTICE')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $doc))) {
            throw "Missing $doc."
        }
    }
}

Add-Check 'Apache license metadata is present' {
    $license = Get-Content -LiteralPath (Join-Path $projectRoot 'LICENSE') -Raw
    $notice = Get-Content -LiteralPath (Join-Path $projectRoot 'NOTICE') -Raw
    $readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw

    if ($license -notmatch 'Apache License' -or $license -notmatch 'Version 2\.0') {
        throw 'LICENSE must contain Apache License 2.0 text.'
    }
    if ($notice -notmatch 'Batch Systems LLC and contributors') {
        throw 'NOTICE must name the copyright holder.'
    }
    if ($readme -notmatch 'Apache License, Version 2\.0') {
        throw 'README must declare the license.'
    }
}

Add-Check 'Config secrets are ignored' {
    if ((Test-Path -LiteralPath (Join-Path $projectRoot '.git')) -and $null -ne (Get-Command git -ErrorAction SilentlyContinue)) {
        $ignored = & git check-ignore config/server.env config/mods.json
        if ($ignored -notcontains 'config/server.env' -or $ignored -notcontains 'config/mods.json') {
            throw 'config/server.env and config/mods.json must be ignored.'
        }
        return
    }

    $gitignorePath = Join-Path $projectRoot '.gitignore'
    if (-not (Test-Path -LiteralPath $gitignorePath)) {
        throw 'Missing .gitignore.'
    }

    $gitignore = Get-Content -LiteralPath $gitignorePath -Raw
    foreach ($entry in @('config/server.env', 'config/mods.json')) {
        $pattern = "(?m)^\s*$([regex]::Escape($entry))\s*$"
        if ($gitignore -notmatch $pattern) {
            throw "$entry must be listed in .gitignore."
        }
    }
}

if (-not $SkipLiveApi) {
    Add-Check 'Admin static root responds when panel is running' {
        $html = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/' -TimeoutSec 5
        if ($html -notmatch 'Project Zomboid') {
            throw 'Admin panel root did not return the expected HTML.'
        }
    }

    Add-Check 'Admin API state responds when panel is running' {
        $state = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/state' -TimeoutSec 5
        if ($null -eq $state.status) {
            throw 'Missing status payload.'
        }
        foreach ($field in @('env', 'settings', 'mods', 'health', 'preflight', 'paths')) {
            if (-not ($state.PSObject.Properties.Name -contains $field)) {
                throw "State payload missing $field."
            }
        }
    }

    Add-Check 'Admin API backups responds when panel is running' {
        $result = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/backups' -TimeoutSec 5
        if (-not $result.ok) {
            throw 'Backups endpoint failed.'
        }
    }

    Add-Check 'Admin API logs responds when panel is running' {
        $result = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/logs' -TimeoutSec 5
        if (-not $result.ok) {
            throw 'Logs endpoint failed.'
        }
    }

    Add-Check 'Admin API health responds when panel is running' {
        $result = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/health' -TimeoutSec 5
        if (-not $result.ok -or $null -eq $result.health -or $null -eq $result.preflight) {
            throw 'Health endpoint returned an incomplete payload.'
        }
    }

    Add-Check 'Admin API setup check responds when panel is running' {
        $result = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/setup' -TimeoutSec 10
        if ($null -eq $result.setup -or @($result.setup.checks).Count -lt 8) {
            throw 'Setup endpoint returned an incomplete checklist.'
        }
    }

    Add-Check 'Admin API config files responds when panel is running' {
        $result = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/config-files' -TimeoutSec 5
        if (-not $result.ok -or $null -eq $result.files.ini -or $null -eq $result.files.sandbox) {
            throw 'Config files endpoint returned an incomplete payload.'
        }
        if ($result.files.ini.exists -and @($result.files.ini.entries).Count -lt 50) {
            throw 'Server INI parser returned too few entries.'
        }
        if ($result.files.sandbox.exists -and @($result.files.sandbox.entries).Count -lt 50) {
            throw 'Sandbox parser returned too few entries.'
        }
    }

    Add-Check 'Admin API persistence endpoints retain edits' {
        & (Join-Path $projectRoot 'tests/admin-panel/Test-AdminPanelPersistence.ps1') -BaseUrl 'http://127.0.0.1:18791' -StartPanel
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Regression failures:'
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host ''
Write-Host 'Regression suite passed.'
