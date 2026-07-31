const state = {
  env: {},
  settings: {},
  mods: [],
  modLoadOrder: [],
  modStateSource: '',
  modDiagnostics: {},
  health: {},
  preflight: {},
  backups: [],
  logs: [],
  paths: {},
  setup: null,
  configFiles: { ini: { entries: [], raw: '', path: '' }, sandbox: { entries: [], raw: '', path: '' } },
  activeConfigFile: 'ini',
  configChanges: {},
  wizardSeeded: false,
  settingsDirty: false,
  modsDirty: false,
  activeActions: new Set()
};

const boolKeys = new Set([
  'Public',
  'Open',
  'PVP',
  'PauseEmpty',
  'SteamVAC',
  'VoiceEnable',
  'BackupsOnStart',
  'BackupsOnVersionChange'
]);

const wizardPasswordChars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const actionLabels = {
  start: 'Start server',
  stop: 'Stop server',
  restart: 'Restart + backup',
  smartRefreshMods: 'Smart mod refresh',
  prepareStagedUpdate: 'Prepare staged update',
  stagedRefresh: 'Apply staged refresh',
  rollbackStagedUpdate: 'Rollback staged update',
  backup: 'Backup saves',
  update: 'Update server files',
  updateMods: 'Update mods',
  refreshMods: 'Refresh mods',
  watchdog: 'Run watchdog',
  enableAutomation: 'Enable automation',
  disableAutomation: 'Disable automation',
  shutdownPanel: 'Close admin panel',
  restartPanel: 'Restart admin panel',
  installFirewallRules: 'Install firewall rules',
  applyConfig: 'Apply config',
  applyConfigRestart: 'Apply config + restart',
  pruneBackups: 'Prune backups',
  pruneLogs: 'Prune logs'
};

const actionConfirmations = {
  stop: 'Stop the Project Zomboid server now? Current players will be disconnected.',
  restart: 'Back up saves and restart the Project Zomboid server now?',
  stagedRefresh: 'Apply the already staged refresh now? This warns players, stops the server, swaps staged files in, starts again, and rolls back if health fails.',
  rollbackStagedUpdate: 'Rollback to the previous staged server copy and restart?',
  refreshMods: 'Refresh mods now? This may restart the server.',
  update: 'Update Project Zomboid server files now? This may restart the server.',
  updateMods: 'Update Workshop mods now? This may require a server restart before players can join.',
  applyConfigRestart: 'Apply saved config and restart now? Current players will be disconnected.',
  installFirewallRules: 'Install Windows Firewall rules now? This requires Administrator permission.',
  enableAutomation: 'Enable scheduled background tasks for startup, watchdog, restart, and updates?',
  disableAutomation: 'Disable scheduled background tasks? This does not stop the running server.',
  shutdownPanel: 'Close only the admin panel? The Project Zomboid server will keep running.',
  restartPanel: 'Restart only the admin panel? The Project Zomboid server will keep running.',
  pruneLogs: 'Delete old log files according to retention settings? This does not delete backups or saves.'
};

const actionDescriptions = {
  start: 'Starts the Project Zomboid server with the current saved config. Wait for Ready before players join.',
  stop: 'Saves and stops the Project Zomboid server. Everyone connected will be disconnected.',
  restart: 'Creates a save backup, stops the server, then starts it again. Use after normal config changes.',
  smartRefreshMods: 'Checks the maintenance window and player activity before doing a staged mod/server refresh. Best hands-off option.',
  prepareStagedUpdate: 'Downloads server and Workshop updates into the staging folder while the active server can keep running.',
  stagedRefresh: 'Applies the already prepared staged update. Use Stage Pending Updates or Prepare Staged Update first.',
  rollbackStagedUpdate: 'Reverts to the previous staged server copy if a staged refresh broke startup or mod loading.',
  backup: 'Creates a save backup now. Use before mod changes, config edits, or updates.',
  update: 'Runs SteamCMD validation/update for the dedicated server files. May require restart before use.',
  updateMods: 'Downloads enabled Workshop items from config\\mods.json. It does not decide whether the server should restart.',
  refreshMods: 'Updates Workshop mods, backs up saves, and restarts so Project Zomboid loads the refreshed mod files.',
  watchdog: 'Checks whether the server appears unhealthy and restarts it when watchdog rules say recovery is needed.',
  enableAutomation: 'Registers Windows scheduled tasks for startup, watchdog, backups, and optional smart mod refresh.',
  disableAutomation: 'Turns off scheduled manager tasks. It does not stop the currently running server.',
  shutdownPanel: 'Closes only this local web admin panel. The Project Zomboid server keeps running.',
  restartPanel: 'Restarts only the local web admin panel. Use when the UI is stale or disconnected.',
  installFirewallRules: 'Adds Windows Firewall rules for Project Zomboid ports. Router port forwarding is still separate.',
  applyConfig: 'Writes saved manager settings into the active server files without restarting the server.',
  applyConfigRestart: 'Writes config, backs up saves, then restarts so Project Zomboid actually loads the changes.',
  pruneBackups: 'Deletes old backups according to retention settings. Does not delete the active world save.',
  pruneLogs: 'Deletes old manager and Project Zomboid log files according to log retention settings.'
};

function $(selector) {
  return document.querySelector(selector);
}

function all(selector) {
  return [...document.querySelectorAll(selector)];
}

function appendOutput(message) {
  const output = $('#output');
  const stamp = new Date().toLocaleTimeString();
  output.textContent = `[${stamp}] ${message}\n\n${output.textContent}`.slice(0, 18000);
}

function renderActiveActionBanner() {
  const banner = $('#activeActionBanner');
  if (!banner) return;
  const actions = [...state.activeActions];
  if (actions.length === 0) {
    banner.hidden = true;
    banner.textContent = '';
    return;
  }
  const labels = actions.map((action) => actionLabels[action] || action).join(', ');
  banner.hidden = false;
  banner.innerHTML = `<strong>Working:</strong> ${escapeHtml(labels)}. Health is refreshing with live progress.`;
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || payload.stderr || 'Request failed.');
  return payload;
}

function valueFor(key) {
  return state.settings[key] ?? '';
}

function renderStatus(payload) {
  const status = payload?.status?.status || payload?.status || {};
  const running = Boolean(status.Running);
  const ready = Boolean(status.Ready);
  $('#runBadge').textContent = ready ? 'Ready' : running ? 'Starting' : 'Stopped';
  $('#runBadge').className = `badge ${ready ? 'running' : running ? 'starting' : 'stopped'}`;
  $('#pidBadge').textContent = running ? `PID ${status.Pid}` : 'No PID';
  $('#statusMeaning').textContent = ready
    ? 'Players should be able to join if router/firewall settings are correct.'
    : running
      ? 'The server process is running but still warming up or not yet query-ready. Check Logs if this lasts several minutes.'
      : 'The server process is stopped. Use Start when setup is complete.';
}

function renderOverview() {
  $('#subtitle').textContent = state.settings.PublicName || state.env.PZ_PUBLIC_NAME || 'Project Zomboid';
  $('#serverName').textContent = state.env.PZ_SERVER_NAME || 'servertest';
  $('#maxPlayers').textContent = state.settings.MaxPlayers || state.env.PZ_MAX_PLAYERS || '-';
  $('#ports').textContent = `${state.settings.DefaultPort || state.env.PZ_PORT || '-'} / ${state.settings.UDPPort || state.env.PZ_UDP_PORT || '-'}`;
  $('#memory').textContent = `${state.env.PZ_MEMORY_MIN || '-'} / ${state.env.PZ_MEMORY_MAX || '-'}`;
  $('#envPath').textContent = state.paths.envPath || '';
  $('#iniPath').textContent = state.paths.iniPath || '';
  $('#modsPath').textContent = state.paths.modsPath || '';
  const publicName = state.settings.PublicName || state.env.PZ_PUBLIC_NAME || 'Project Zomboid';
  const port = state.settings.DefaultPort || state.env.PZ_PORT || '16261';
  $('#joinInfo').textContent = `${publicName} on port ${port}. Remote players need the host public IP and matching UDP port forwarding.`;
  renderNextStep();
}

function renderNextStep() {
  const setupReady = Boolean(state.setup?.ok);
  const statusPayload = state.statusPayload?.status?.status || state.statusPayload?.status || {};
  const running = Boolean(statusPayload.Running);
  const ready = Boolean(statusPayload.Ready);
  const pendingMods = state.mods.filter((mod) => mod.enabled && mod.needsUpdate).length;
  const staged = state.health?.stagedUpdate || {};
  const setupTodo = (state.setup?.checks || []).filter((check) => !check.ok && !['firewall', 'automation', 'stagedUpdate', 'rollback', 'adminPanel'].includes(check.id));

  let title = 'Server manager is ready.';
  let body = 'Use Settings for normal changes, Mods for Workshop lists, and Advanced only for maintenance or recovery.';

  if (!setupReady) {
    title = 'Finish setup before hosting.';
    body = setupTodo.length > 0
      ? `Next setup item: ${setupTodo[0].label}. ${setupTodo[0].next || 'Open Setup for details.'}`
      : 'Open Setup and refresh the checklist.';
  } else if (ready) {
    title = 'Server is ready for players.';
    body = 'Players can join with the host public IP, port, and join password. Use Restart + Backup before major config or mod changes.';
  } else if (running) {
    title = 'Server is starting.';
    body = 'Wait a few minutes on first launch. Open Logs if it stays in Starting for more than 8-10 minutes.';
  } else if (pendingMods > 0 && staged.stagedReady) {
    title = 'Staged mod updates are ready.';
    body = 'Apply the staged refresh during a quiet window. Players may still need Steam to update client mods.';
  } else if (pendingMods > 0) {
    title = 'Mod updates are available.';
    body = 'Stage pending updates before applying them so the actual server restart is shorter.';
  } else {
    title = 'Server is stopped.';
    body = 'Use Start after setup is complete. Use Settings first if you need to change the public name, password, ports, or player count.';
  }

  $('#nextStepTitle').textContent = title;
  $('#nextStepBody').textContent = body;
}

function renderHealth() {
  const health = state.health || {};
  const preflight = state.preflight || {};
  const watchdog = health.watchdog || {};
  const staged = health.stagedUpdate || {};
  $('#playerCount').textContent = health.players?.PlayerCount ?? '-';
  $('#watchdogState').textContent = watchdog.running === true ? 'Healthy' : watchdog.maintenance ? 'Maintenance' : 'Unknown';
  $('#backupCount').textContent = String(state.backups.length || health.backups?.length || 0);
  $('#logCount').textContent = String(health.logGrooming?.totalCount || health.logs?.length || state.logs.length || 0);
  $('#preflightState').textContent = preflight.ok ? 'Clean' : 'Review';
  $('#stagedUpdateState').textContent = staged.stagedReady ? 'Prepared' : staged.rollbackReady ? 'Rollback Ready' : 'None';
  $('#automationState').textContent = health.automationTasks?.totalCount ? `${health.automationTasks.enabledCount || 0}/${health.automationTasks.totalCount}` : 'None';
  $('#preflightSummary').textContent = `Workshop ${preflight.workshopCount || 0}, load order ${preflight.loadOrderCount || 0}, duplicate Workshop ${preflight.duplicateWorkshop?.length || 0}, duplicate Mod IDs ${preflight.duplicateMods?.length || 0}`;

  $('#healthDetails').innerHTML = [
    ['Server PID', health.serverPid || '-'],
    ['Admin panel PID', health.adminPanelPid || '-'],
    ['Staged server', staged.stagedReady ? staged.stagedServerDir : 'None'],
    ['Rollback server', staged.rollbackReady ? staged.rollbackServerDir : 'None'],
    ['Duplicate Workshop IDs', (preflight.duplicateWorkshop || []).join(', ') || 'None'],
    ['Duplicate Mod IDs', (preflight.duplicateMods || []).join(', ') || 'None']
  ].map(([label, value]) => `<div><span>${escapeHtml(label)}</span><code>${escapeHtml(value)}</code></div>`).join('');

  renderJobs();
  renderGrooming();
  renderModUpdateProgress();
  renderStagedHealth();
  renderRestartJustification();
  renderAutomationStatus();
}

function formatDate(value) {
  if (!value) return 'Not scheduled';
  return new Date(value).toLocaleString();
}

function progressPercent(item) {
  const total = Number(item?.total || 0);
  if (total <= 0) return 0;
  return Math.max(0, Math.min(100, Math.round((Number(item.completed || 0) / total) * 100)));
}

function renderProgressBar(item) {
  const pct = progressPercent(item);
  return `
    <div class="progress-bar" aria-label="Progress">
      <span style="width: ${pct}%"></span>
    </div>
    <code>${pct}% · ${escapeHtml(String(item?.completed ?? 0))}/${escapeHtml(String(item?.total ?? 0))}</code>
  `;
}

function statusPill(label, tone = 'info') {
  return `<span class="state-pill ${escapeHtml(tone)}">${escapeHtml(label || 'Unknown')}</span>`;
}

function phaseTone(phase) {
  if (['succeeded', 'prepared', 'skipped'].includes(phase)) return 'ok';
  if (['failed', 'rolling-back'].includes(phase)) return 'danger';
  if (phase) return 'warning';
  return 'info';
}

function renderModUpdateProgress() {
  const update = state.health?.modUpdate;
  if (!update) {
    $('#modUpdateProgress').innerHTML = '<div class="empty-row">No recorded mod update yet.</div>';
    return;
  }

  $('#modUpdateProgress').innerHTML = `
    <div class="progress-heading">
      ${statusPill(update.phase || 'unknown', phaseTone(update.phase))}
      <strong>${escapeHtml(update.status || 'No status message recorded.')}</strong>
    </div>
    ${renderProgressBar(update)}
    <div class="status-table">
      <div><span>Current Workshop ID</span><code>${escapeHtml(update.currentWorkshopId || '-')}</code></div>
      <div><span>Started</span><code>${escapeHtml(formatDate(update.startedAt))}</code></div>
      <div><span>Finished</span><code>${escapeHtml(formatDate(update.finishedAt))}</code></div>
      <div><span>Restart needed</span><code>${update.restartRecommended ? 'Yes' : 'No'}</code></div>
      ${update.lastError ? `<div><span>Last error</span><code>${escapeHtml(update.lastError)}</code></div>` : ''}
    </div>
  `;
}

function renderStagedHealth() {
  const staged = state.health?.stagedUpdate || {};
  const progress = staged.progress || {};
  const phase = progress.phase || (staged.stagedReady ? 'prepared' : staged.rollbackReady ? 'rollback-ready' : 'none');
  $('#stagedHealth').innerHTML = `
    <div class="progress-heading">
      ${statusPill(phase, phaseTone(phase))}
      <strong>${escapeHtml(progress.status || (staged.stagedReady ? 'Staged server files are waiting to be applied.' : 'No staged server version is waiting.'))}</strong>
    </div>
    ${progress.total !== undefined ? renderProgressBar(progress) : ''}
    <div class="status-table">
      <div><span>Staged build</span><code>${staged.stagedReady ? 'Ready' : 'Not present'}</code></div>
      <div><span>Rollback copy</span><code>${staged.rollbackReady ? 'Ready' : 'Not present'}</code></div>
      <div><span>Safe to apply</span><code>${progress.safeToApply ? 'Yes' : staged.stagedReady ? 'Review first' : 'No'}</code></div>
      <div><span>Current Workshop ID</span><code>${escapeHtml(progress.currentWorkshopId || '-')}</code></div>
      <div><span>Staged path</span><code>${escapeHtml(staged.stagedServerDir || progress.stageServerDir || '-')}</code></div>
      <div><span>Rollback path</span><code>${escapeHtml(staged.rollbackServerDir || progress.rollbackServerDir || '-')}</code></div>
      ${progress.lastError ? `<div><span>Last error</span><code>${escapeHtml(progress.lastError)}</code></div>` : ''}
    </div>
  `;
}

function renderRestartJustification() {
  const recommendation = state.health?.restartRecommendation || {};
  const tone = recommendation.severity || 'info';
  $('#restartJustification').innerHTML = `
    <div class="progress-heading">
      ${statusPill(recommendation.recommended ? 'Recommended' : 'Not needed', tone)}
      <strong>${escapeHtml(recommendation.action || 'No recommendation yet.')}</strong>
    </div>
    <p>${escapeHtml(recommendation.reason || 'No restart justification has been recorded.')}</p>
  `;
}

function taskTone(task) {
  if (Number(task.lastTaskResult || 0) !== 0) return 'danger';
  if (!task.enabled || task.state === 'Disabled') return 'info';
  if (task.state === 'Running') return 'warning';
  return 'ok';
}

function taskResultText(value) {
  if (value === null || value === undefined) return 'Never ran';
  const code = Number(value);
  return code === 0 ? 'Last result OK' : `Last result ${code}`;
}

function renderAutomationStatus() {
  const automation = state.health?.automationTasks || {};
  if (!automation.supported) {
    $('#automationStatus').innerHTML = `<div class="empty-row">${escapeHtml(automation.message || 'Automation status is not available here.')}</div>`;
    return;
  }

  const tasks = automation.tasks || [];
  if (tasks.length === 0) {
    $('#automationStatus').innerHTML = `
      <div class="progress-heading">
        ${statusPill('Not enabled', 'info')}
        <strong>${escapeHtml(automation.message || 'No scheduled automation tasks found.')}</strong>
      </div>
    `;
    return;
  }

  $('#automationStatus').innerHTML = `
    <div class="status-table">
      <div><span>Enabled tasks</span><code>${escapeHtml(String(automation.enabledCount || 0))}/${escapeHtml(String(automation.totalCount || 0))}</code></div>
      <div><span>Last-run failures</span><code>${escapeHtml(String(automation.failedCount || 0))}</code></div>
    </div>
    ${tasks.map((task) => `
      <div class="automation-row">
        <div>
          <strong>${escapeHtml(task.name || 'Scheduled task')}</strong>
          <span>${escapeHtml(task.state || 'Unknown')} · ${escapeHtml(taskResultText(task.lastTaskResult))}</span>
        </div>
        <div class="status-table compact-table">
          <div><span>Last</span><code>${escapeHtml(formatDate(task.lastRunTime))}</code></div>
          <div><span>Next</span><code>${escapeHtml(formatDate(task.nextRunTime))}</code></div>
        </div>
        ${statusPill(task.enabled ? 'Enabled' : 'Disabled', taskTone(task))}
      </div>
    `).join('')}
  `;
}

function renderJobs() {
  const jobs = state.health?.jobs || [];
  $('#jobList').innerHTML = jobs.length === 0
    ? '<div class="empty-row">No recorded actions yet.</div>'
    : jobs.map((job) => `
      <div class="job-row ${escapeHtml(job.status || '')}">
        <div>
          <strong>${escapeHtml(job.label || job.action || 'Action')}</strong>
          <span>${escapeHtml(job.summary || '')}</span>
        </div>
        <code>${escapeHtml(job.status || 'unknown')} · ${escapeHtml(formatDate(job.startedAt))}</code>
      </div>
    `).join('');
}

function renderGrooming() {
  const backup = state.health?.backupGrooming || {};
  const logs = state.health?.logGrooming || {};
  $('#groomingSummary').innerHTML = [
    ['Backup retention', `${backup.retentionDays ?? '-'} days; ${backup.eligibleCount || 0} eligible now; next delete ${formatDate(backup.nextDeleteAt)}`],
    ['Backup storage', `${backup.totalCount || 0} backups · ${formatBytes(backup.totalBytes || 0)}`],
    ['Log retention', `${logs.retentionDays ?? '-'} days; ${logs.eligibleCount || 0} eligible now; next delete ${formatDate(logs.nextDeleteAt)}`],
    ['Log storage', `${logs.totalCount || 0} files · ${formatBytes(logs.totalBytes || 0)}`]
  ].map(([label, value]) => `<div><span>${escapeHtml(label)}</span><code>${escapeHtml(value)}</code></div>`).join('');
}

function renderSettings() {
  if (state.settingsDirty || $('#settingsForm')?.contains(document.activeElement)) return;
  const form = $('#settingsForm');
  for (const input of [...form.elements]) {
    if (!input.name) continue;
    if (input.type === 'checkbox') input.checked = String(valueFor(input.name)).toLowerCase() === 'true';
    else input.value = valueFor(input.name);
  }
  $('#modWarningSeconds').value = state.env.PZ_MOD_WARNING_SECONDS || '60';
  $('#modWindowStart').value = state.env.PZ_MOD_REFRESH_WINDOW_START || '04:00';
  $('#modWindowEnd').value = state.env.PZ_MOD_REFRESH_WINDOW_END || '05:00';
  $('#autoRefreshMods').checked = String(state.env.PZ_AUTO_REFRESH_MODS || 'false').toLowerCase() === 'true';
}

function renderSetup() {
  const setup = state.setup;
  if (!setup) {
    $('#setupSummary').textContent = 'Setup check has not run yet.';
    $('#setupList').innerHTML = '';
    return;
  }

  const checks = setup.checks || [];
  const todo = checks.filter((check) => !check.ok);
  $('#setupSummary').textContent = setup.ok
    ? 'Core setup is ready. Optional items can still improve hands-off hosting.'
    : `${todo.length} setup item${todo.length === 1 ? '' : 's'} need attention.`;
  $('#setupList').innerHTML = checks.map((check) => `
    <div class="setup-row ${check.ok ? 'ok' : 'todo'}">
      <div>
        <strong>${escapeHtml(check.label)}</strong>
        <span>${escapeHtml(check.detail || '')}</span>
        ${check.ok || !check.next ? '' : `<em>${escapeHtml(check.next)}</em>`}
      </div>
      <b>${check.ok ? 'OK' : 'TODO'}</b>
    </div>
  `).join('');
  renderSetupWizardState();
}

function setupCheck(id) {
  return (state.setup?.checks || []).find((check) => check.id === id);
}

function shouldAutoShowSetupWizard() {
  if (location.hash === '#wizard') return true;
  if (!state.setup) return false;
  return ['localConfig', 'secrets', 'steamcmd', 'serverRuntime', 'serverIni', 'sandboxVars']
    .some((id) => setupCheck(id)?.ok === false);
}

function newWizardPassword() {
  let value = 'pz-';
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  for (const byte of bytes) value += wizardPasswordChars[byte % wizardPasswordChars.length];
  return value;
}

function memoryPresetFromConfig() {
  const max = String(state.env.PZ_MEMORY_MAX || '').toLowerCase();
  if (max.includes('8192') || max.includes('8g')) return 'large';
  if (max.includes('3072') || max.includes('3g')) return 'low';
  return 'normal';
}

function seedSetupWizard(force = false) {
  if (state.wizardSeeded && !force) return;
  const defaults = state.setup?.defaults || {};
  const publicName = state.settings.PublicName || state.env.PZ_PUBLIC_NAME || defaults.publicName || 'Project Zomboid Server';
  const password = state.settings.Password || state.env.PZ_PASSWORD || defaults.joinPassword || newWizardPassword();
  const maxPlayers = state.settings.MaxPlayers || state.env.PZ_MAX_PLAYERS || defaults.maxPlayers || '8';
  const runtimeRoot = state.env.PZ_ROOT || defaults.runtimeRoot || 'C:\\pz';

  $('#wizardRuntimeRoot').value = runtimeRoot;
  $('#wizardPublicName').value = publicName;
  $('#wizardJoinPassword').value = password;
  $('#wizardMaxPlayers').value = maxPlayers;
  $('#wizardMemoryPreset').value = memoryPresetFromConfig();
  state.wizardSeeded = true;
}

function openSetupWizard() {
  $('#setupModal').hidden = false;
  seedSetupWizard();
  renderSetupWizardState();
  $('#wizardPublicName').focus();
}

function closeSetupWizard() {
  $('#setupModal').hidden = true;
  if (location.hash === '#wizard') history.replaceState(null, '', '#setup');
}

function renderSetupWizardState() {
  const setup = state.setup;
  const isAdmin = Boolean(setup?.isAdministrator);
  const serverExists = setupCheck('serverRuntime')?.ok === true;
  $('#wizardReuseServer').checked = serverExists;
  $('#wizardReuseServer').disabled = !serverExists;
  $('#wizardFirewall').disabled = !isAdmin;
  $('#wizardAutomation').disabled = !isAdmin;
  if (!isAdmin) {
    $('#wizardFirewall').checked = false;
    $('#wizardAutomation').checked = false;
  }
  $('#setupWizardNote').textContent = isAdmin
    ? 'Administrator mode detected. Firewall and automation can be enabled now.'
    : 'Firewall rules and scheduled automation require Administrator permission. You can enable them later from Setup or Ops.';
}

function collectWizardOptions() {
  return {
    publicName: $('#wizardPublicName').value.trim() || 'Project Zomboid Server',
    runtimeRoot: $('#wizardRuntimeRoot').value.trim() || 'C:\\pz',
    joinPassword: $('#wizardJoinPassword').value.trim(),
    maxPlayers: Number($('#wizardMaxPlayers').value || 8),
    memoryPreset: $('#wizardMemoryPreset').value,
    startServer: $('#wizardStartServer').checked,
    reuseServerFiles: $('#wizardReuseServer').checked,
    internetHosting: $('#wizardInternetHosting').checked,
    installFirewallRules: $('#wizardInternetHosting').checked && $('#wizardFirewall').checked,
    registerAutomation: $('#wizardAutomation').checked
  };
}

async function runSetupWizardInstall() {
  const options = collectWizardOptions();
  if (!options.joinPassword) {
    $('#setupWizardOutput').textContent = 'Join password is required.';
    return;
  }

  $('#setupWizardInstallBtn').disabled = true;
  $('#setupWizardOutput').textContent = 'Installing. This can take a while on first run...';
  try {
    const result = await api('/api/setup/install', {
      method: 'POST',
      body: JSON.stringify(options)
    });
    $('#setupWizardOutput').textContent = [result.stdout, result.stderr].filter(Boolean).join('\n') || 'Install complete.';
    await refresh();
    activateTab('setup');
    history.replaceState(null, '', '#setup');
  } catch (error) {
    $('#setupWizardOutput').textContent = error.message;
  } finally {
    $('#setupWizardInstallBtn').disabled = false;
  }
}

function renderMods() {
  if (state.modsDirty || $('#modList')?.contains(document.activeElement) || document.activeElement === $('#modLoadOrder')) return;
  const list = $('#modList');
  list.innerHTML = '';
  const pendingMods = state.mods.filter((mod) => mod.enabled && mod.needsUpdate);
  const needsUpdate = pendingMods.length;
  const checked = state.mods.filter((mod) => mod.lastCheckedAt).length;
  $('#modHealth').textContent = needsUpdate > 0
    ? `${needsUpdate} enabled mod${needsUpdate === 1 ? '' : 's'} updated upstream`
    : checked > 0 ? 'Enabled mods are current from the last check' : 'No mod check yet';
  renderModRecoveryPanel();
  $('#modLoadOrder').value = state.modLoadOrder.join(';');
  renderPendingMods(pendingMods, checked);

  if (state.mods.length === 0) {
    state.mods.push({ name: '', workshopId: '', modId: '', enabled: true, notes: '' });
  }
  state.mods.forEach((mod, index) => {
    const row = document.createElement('div');
    row.className = `mod-row ${mod.needsUpdate ? 'needs-update' : ''}`;
    const updated = mod.currentSteamUpdated || mod.lastKnownUpdated;
    const updateLabel = updated ? new Date(updated * 1000).toLocaleString() : 'Not checked';
    row.innerHTML = `
      <label class="check"><input type="checkbox" data-field="enabled" ${mod.enabled ? 'checked' : ''}> On</label>
      <label>Name<input data-field="name" value="${escapeHtml(mod.name || '')}"></label>
      <label>Workshop ID<input data-field="workshopId" value="${escapeHtml(mod.workshopId || '')}"></label>
      <label>Mod ID<input data-field="modId" value="${escapeHtml(mod.modId || '')}"></label>
      <label>Notes<input data-field="notes" value="${escapeHtml(mod.notes || '')}"></label>
      <div class="mod-meta">
        <span>${mod.needsUpdate ? 'Update available' : 'Known version'}</span>
        <strong>${escapeHtml(updateLabel)}</strong>
      </div>
      <button title="Remove" data-remove="${index}">×</button>
    `;
    list.appendChild(row);
    row.querySelectorAll('[data-field]').forEach((input) => {
      input.addEventListener('input', () => {
        state.modsDirty = true;
        const field = input.dataset.field;
        state.mods[index][field] = input.type === 'checkbox' ? input.checked : input.value;
      });
      input.addEventListener('change', () => {
        state.modsDirty = true;
        const field = input.dataset.field;
        state.mods[index][field] = input.type === 'checkbox' ? input.checked : input.value;
      });
    });
    row.querySelector('[data-remove]').addEventListener('click', () => {
      state.mods.splice(index, 1);
      renderMods();
    });
  });
}

function renderModRecoveryPanel() {
  const diag = state.modDiagnostics || {};
  const panel = $('#modRecoveryPanel');
  const title = $('#modRecoveryTitle');
  const body = $('#modRecoveryBody');
  const repairButton = $('#repairModsBtn');
  const managerCount = Number(diag.storedEntryCount || 0);
  const iniCount = Number(diag.iniWorkshopCount || 0);
  const loadOrderCount = Number(diag.iniLoadOrderCount || state.modLoadOrder.length || 0);
  const bestWorkshopCount = Number(diag.bestRecoveryWorkshopCount || 0);
  const bestSource = diag.bestRecoverySource || 'server.ini';
  const needsRepair = Boolean(diag.needsEntryRepair || diag.needsLoadOrderRepair || (managerCount === 0 && (iniCount > 0 || bestWorkshopCount > 0)));

  panel.classList.toggle('warning', needsRepair || state.modStateSource === 'server.ini');
  repairButton.disabled = !diag.recoverableFromIni;
  repairButton.hidden = !needsRepair && managerCount > 0;

  if (needsRepair) {
    title.textContent = bestWorkshopCount > iniCount ? 'Mod view can be repaired from a config backup.' : 'Mod view can be repaired from server.ini.';
    body.textContent = `Manager file has ${managerCount} mod row${managerCount === 1 ? '' : 's'}; active server.ini has ${iniCount} Workshop item${iniCount === 1 ? '' : 's'} and ${loadOrderCount} load-order item${loadOrderCount === 1 ? '' : 's'}. Best recovery source: ${bestSource} with ${bestWorkshopCount || iniCount} Workshop item${(bestWorkshopCount || iniCount) === 1 ? '' : 's'}. Repair rebuilds config\\mods.json without touching saves or restarting the server.`;
    return;
  }

  if (state.modStateSource === 'server.ini') {
    title.textContent = 'Mod rows were recovered from server.ini.';
    body.textContent = `Recovered ${state.mods.length} mod row${state.mods.length === 1 ? '' : 's'} from the active server.ini. Save Mods after review to keep the manager state synchronized.`;
    return;
  }

  title.textContent = 'Mod state is loaded from manager config.';
  body.textContent = `config\\mods.json has ${managerCount || state.mods.length} mod row${(managerCount || state.mods.length) === 1 ? '' : 's'}; active server.ini has ${iniCount} Workshop item${iniCount === 1 ? '' : 's'}. Best backup recovery source: ${bestSource || 'none'}.`;
}

function renderPendingMods(pendingMods, checkedCount) {
  const staged = state.health?.stagedUpdate || {};
  $('#pendingModCount').textContent = `${pendingMods.length} pending enabled update${pendingMods.length === 1 ? '' : 's'}`;
  $('#pendingModHelp').textContent = pendingMods.length > 0
    ? staged.stagedReady
      ? 'A staged server update is ready. Players may still need Steam to finish Workshop client updates before joining.'
      : 'Stage these before the maintenance window, then apply a staged refresh when player traffic is low.'
    : checkedCount > 0
      ? 'No enabled Workshop updates were detected on the last check.'
      : 'Check Workshop metadata to detect pending updates before staging.';

  $('#pendingModList').innerHTML = pendingMods.length === 0
    ? ''
    : pendingMods.slice(0, 12).map((mod) => `
        <div class="pending-row">
          <strong>${escapeHtml(mod.steamTitle || mod.name || mod.workshopId)}</strong>
          <span>${escapeHtml(mod.workshopId)} · updated ${mod.currentSteamUpdated ? new Date(mod.currentSteamUpdated * 1000).toLocaleString() : 'upstream'}</span>
        </div>
      `).join('');

  if (pendingMods.length > 12) {
    $('#pendingModList').insertAdjacentHTML('beforeend', `<div class="pending-row"><strong>${pendingMods.length - 12} more</strong><span>Use search/check details in the mod rows below.</span></div>`);
  }
}

function renderBackups() {
  const list = $('#backupList');
  const grooming = state.health?.backupGrooming || {};
  $('#backupForecast').textContent = `Retention ${grooming.retentionDays ?? '-'} days. ${grooming.eligibleCount || 0} backup${grooming.eligibleCount === 1 ? '' : 's'} eligible now. Next scheduled deletion: ${formatDate(grooming.nextDeleteAt)}.`;
  if (!state.backups.length) {
    list.innerHTML = '<div class="empty-row">No save backups found.</div>';
    return;
  }
  list.innerHTML = state.backups.map((backup) => `
    <div class="backup-row">
      <div><strong>${escapeHtml(backup.name)}</strong><span>${new Date(backup.modified).toLocaleString()} · ${formatBytes(backup.size)}</span></div>
      <button data-restore="${escapeHtml(backup.name)}">Restore</button>
    </div>
  `).join('');
  list.querySelectorAll('[data-restore]').forEach((button) => {
    button.addEventListener('click', () => {
      const name = button.dataset.restore;
      if (!confirm(`Restore ${name}? This stops the server, makes a pre-restore backup, restores the selected save, and restarts.`)) return;
      runRestore(name).catch((error) => appendOutput(error.message));
    });
  });
}

function renderLogs() {
  const list = $('#logList');
  if (!state.logs.length) {
    list.innerHTML = '<div class="empty-row">No logs found.</div>';
    return;
  }
  list.innerHTML = state.logs.map((log) => `
    <button class="log-item" data-log-path="${escapeHtml(log.fullPath)}">
      <strong>${escapeHtml(log.name)}</strong>
      <span>${new Date(log.modified).toLocaleString()} · ${formatBytes(log.size)}</span>
    </button>
  `).join('');
  list.querySelectorAll('[data-log-path]').forEach((button) => {
    button.addEventListener('click', () => loadLog(button.dataset.logPath).catch((error) => appendOutput(error.message)));
  });
}

function activeConfig() {
  return state.configFiles[state.activeConfigFile] || { entries: [], raw: '', path: '', exists: false };
}

function configChangeKey(entry) {
  return `${state.activeConfigFile}:${entry.index}:${entry.key}`;
}

function changedConfigUpdates() {
  const file = state.activeConfigFile;
  const changes = state.configChanges[file] || {};
  return Object.values(changes);
}

function updateConfigChangeCount() {
  const changes = state.configChanges[state.activeConfigFile] || {};
  $('#configChangeCount').textContent = `${Object.keys(changes).length} change${Object.keys(changes).length === 1 ? '' : 's'}`;
}

function renderConfigFiles() {
  const file = activeConfig();
  const entries = file.entries || [];
  const query = ($('#configSearch').value || '').trim().toLowerCase();
  const changes = state.configChanges[state.activeConfigFile] || {};
  const filtered = entries.filter((entry) => {
    if (!query) return true;
    return [entry.path, entry.key, entry.value, entry.comment, entry.category]
      .some((value) => String(value || '').toLowerCase().includes(query));
  });

  $('#iniConfigBtn').classList.toggle('active', state.activeConfigFile === 'ini');
  $('#sandboxConfigBtn').classList.toggle('active', state.activeConfigFile === 'sandbox');
  $('#configFileLabel').textContent = `${state.activeConfigFile === 'ini' ? 'Server INI' : 'Sandbox Vars'} · ${entries.length} settings · ${file.path || 'not found'}`;
  $('#configChangeCount').textContent = `${Object.keys(changes).length} change${Object.keys(changes).length === 1 ? '' : 's'}`;
  $('#configRaw').textContent = file.raw || '';

  const visible = filtered.slice(0, 250);
  $('#configList').innerHTML = visible.length === 0
    ? '<div class="empty-row">No matching settings found.</div>'
    : visible.map((entry) => {
        const key = configChangeKey(entry);
        const current = changes[key]?.value ?? entry.value;
        const changed = Object.prototype.hasOwnProperty.call(changes, key);
        return `
          <div class="config-row ${changed ? 'changed' : ''}" data-config-row="${escapeHtml(key)}">
            <div class="config-key">
              <strong>${escapeHtml(entry.path || entry.key)}</strong>
              <span>Line ${entry.index + 1} · ${escapeHtml(entry.type || 'text')}</span>
            </div>
            <input data-config-key="${escapeHtml(key)}" value="${escapeHtml(current)}" spellcheck="false">
            <div class="config-comment">${escapeHtml(entry.comment || 'No description captured for this setting.')}</div>
          </div>
        `;
      }).join('');

  if (filtered.length > visible.length) {
    $('#configList').insertAdjacentHTML('beforeend', `<div class="empty-row">Showing first ${visible.length} of ${filtered.length} matches. Refine search to narrow this down.</div>`);
  }

  $('#configList').querySelectorAll('[data-config-key]').forEach((input) => {
    input.addEventListener('input', () => {
      const entry = entries.find((item) => configChangeKey(item) === input.dataset.configKey);
      if (!entry) return;
      const bucket = state.configChanges[state.activeConfigFile] || {};
      if (input.value === entry.value) delete bucket[input.dataset.configKey];
      else bucket[input.dataset.configKey] = {
        index: entry.index,
        key: entry.key,
        path: entry.path,
        value: input.value
      };
      state.configChanges[state.activeConfigFile] = bucket;
      input.closest('.config-row')?.classList.toggle('changed', input.value !== entry.value);
      updateConfigChangeCount();
    });
  });
}

async function loadConfigFiles(render = true) {
  if (hasConfigChanges()) {
    if (render) renderConfigFiles();
    return;
  }
  const result = await api('/api/config-files');
  state.configFiles = result.files || state.configFiles;
  state.configChanges = {};
  if (render) renderConfigFiles();
}

function helpActionsFrom(value) {
  return String(value || '').split(',').map((item) => item.trim()).filter(Boolean);
}

function openActionHelp(actions) {
  const items = helpActionsFrom(actions);
  $('#actionHelpList').innerHTML = items.map((action) => {
    const label = actionLabels[action] || action;
    const description = actionDescriptions[action] || 'No description available yet.';
    return `
      <div class="action-help-card">
        <strong>${escapeHtml(label)}</strong>
        <span>${escapeHtml(description)}</span>
      </div>
    `;
  }).join('');
  $('#actionHelpModal').hidden = false;
  $('#closeActionHelpBtn').focus();
}

function closeActionHelp() {
  $('#actionHelpModal').hidden = true;
}

function hasConfigChanges() {
  return Object.values(state.configChanges || {}).some((bucket) => Object.keys(bucket || {}).length > 0);
}

async function saveConfigChanges() {
  const updates = changedConfigUpdates();
  if (updates.length === 0) {
    appendOutput('No config changes to save.');
    return;
  }
  const result = await api('/api/config-files', {
    method: 'POST',
    body: JSON.stringify({ file: state.activeConfigFile, updates })
  });
  state.configFiles = result.files || state.configFiles;
  state.configChanges[state.activeConfigFile] = {};
  appendOutput(`Saved ${updates.length} ${state.activeConfigFile === 'ini' ? 'server INI' : 'sandbox'} setting${updates.length === 1 ? '' : 's'}.`);
  renderConfigFiles();
  await refresh();
}

async function importActiveConfigFile(file) {
  if (!file) return;
  const label = state.activeConfigFile === 'ini' ? 'server INI' : 'SandboxVars';
  if (!confirm(`Import ${file.name} as the active ${label}? The current file will be backed up first.`)) {
    $('#configImportInput').value = '';
    return;
  }

  const content = await file.text();
  const result = await api('/api/config-files/import', {
    method: 'POST',
    body: JSON.stringify({ file: state.activeConfigFile, content })
  });
  state.configFiles = result.files || state.configFiles;
  state.configChanges = {};
  appendOutput(`Imported ${file.name} to ${result.importedPath}.`);
  $('#configImportInput').value = '';
  renderConfigFiles();
  await refresh();
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return '-';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

async function refresh() {
  const payload = await api('/api/state');
  state.statusPayload = payload.status || {};
  state.env = payload.env || {};
  state.settings = payload.settings || {};
  state.mods = payload.mods || [];
  state.modLoadOrder = payload.modLoadOrder || [];
  state.modStateSource = payload.modStateSource || '';
  state.modDiagnostics = payload.modDiagnostics || {};
  state.health = payload.health || {};
  state.preflight = payload.preflight || {};
  state.paths = payload.paths || {};
  await loadSetup(false);
  await loadConfigFiles(false);
  await Promise.allSettled([refreshBackups(false), refreshLogs(false)]);
  renderStatus(payload.status);
  renderOverview();
  renderHealth();
  renderSetup();
  renderSettings();
  renderConfigFiles();
  renderMods();
  renderBackups();
  renderLogs();
  if (shouldAutoShowSetupWizard()) openSetupWizard();
}

async function loadSetup(render = true) {
  const result = await api('/api/setup');
  state.setup = result.setup || null;
  if (render) renderSetup();
}

function collectSettings() {
  const settings = {};
  const form = $('#settingsForm');
  for (const input of [...form.elements]) {
    if (!input.name) continue;
    settings[input.name] = boolKeys.has(input.name) ? String(input.checked) : input.value;
  }
  return settings;
}

async function runAction(action) {
  const confirmation = actionConfirmations[action];
  if (confirmation && !confirm(confirmation)) return;
  const label = actionLabels[action] || action;
  setActionBusy(action, true);
  appendOutput(`Running ${label}`);
  try {
    const result = await api('/api/action', {
      method: 'POST',
      body: JSON.stringify({ action })
    });
    if (result.accepted && result.job) {
      appendOutput(`${label} started in the background. Watch Health for live progress.`);
      await refreshHealthOnly();
      await pollActionJob(result.job.id, action, label);
      return;
    }
    const jobLine = result.job ? `Job ${result.job.status}: ${result.job.summary}` : '';
    appendOutput([jobLine, result.stdout, result.stderr].filter(Boolean).join('\n') || `${label} completed.`);
    if (action === 'shutdownPanel') {
      appendOutput('Admin panel closed. Run Open-AdminPanel.ps1 to reopen it.');
      return;
    }
    await refresh();
  } finally {
    setActionBusy(action, false);
  }
}

function setActionBusy(action, busy) {
  if (busy) state.activeActions.add(action);
  else state.activeActions.delete(action);
  renderActiveActionBanner();
  const buttons = [
    ...all(`[data-action="${action}"]`),
    ...(action === 'prepareStagedUpdate' ? [$('#stagePendingModsBtn')] : []),
    ...(action === 'stagedRefresh' ? [$('#applyStagedModsBtn')] : [])
  ].filter(Boolean);
  buttons.forEach((button) => {
    button.classList.toggle('busy', busy);
    button.disabled = busy;
    if (busy) {
      button.dataset.originalText = button.dataset.originalText || button.textContent;
      button.textContent = 'Working...';
    } else if (button.dataset.originalText) {
      button.textContent = button.dataset.originalText;
      delete button.dataset.originalText;
    }
  });
}

async function refreshHealthOnly() {
  const result = await api('/api/health');
  state.health = result.health || {};
  state.preflight = result.preflight || {};
  renderHealth();
}

async function pollActionJob(jobId, action, label) {
  const started = Date.now();
  while (Date.now() - started < 30 * 60 * 1000) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    await refreshHealthOnly();
    const job = (state.health.jobs || []).find((item) => item.id === jobId);
    if (!job || job.status === 'running') continue;
    appendOutput(`Job ${job.status}: ${job.summary || label}`);
    setActionBusy(action, false);
    await refresh();
    return;
  }
  appendOutput(`${label} is still running or the panel stopped receiving updates. Refresh Health to check current state.`);
}

async function runRestore(name) {
  appendOutput(`Restoring ${name}`);
  const result = await api('/api/action', {
    method: 'POST',
    body: JSON.stringify({ action: 'restoreBackup', name })
  });
  const jobLine = result.job ? `Job ${result.job.status}: ${result.job.summary}` : '';
  appendOutput([jobLine, result.stdout, result.stderr].filter(Boolean).join('\n') || 'Restore completed.');
  await refresh();
}

async function refreshBackups(render = true) {
  const result = await api('/api/backups');
  state.backups = result.backups || [];
  if (render) renderBackups();
}

async function refreshLogs(render = true) {
  const result = await api('/api/logs');
  state.logs = result.logs || [];
  if (render) renderLogs();
}

async function loadLog(fullPath) {
  const result = await api(`/api/logs/tail?path=${encodeURIComponent(fullPath)}`);
  $('#logContent').textContent = result.content || '';
}

function bindUi() {
  all('.nav').forEach((button) => {
    button.addEventListener('click', () => {
      activateTab(button.dataset.tab);
      history.replaceState(null, '', `#${button.dataset.tab}`);
    });
  });

  $('#refreshBtn').addEventListener('click', () => refresh().catch((error) => appendOutput(error.message)));
  $('#refreshSetupBtn').addEventListener('click', () => loadSetup().catch((error) => appendOutput(error.message)));
  $('#launchSetupWizardBtn').addEventListener('click', () => openSetupWizard());
  $('#closeSetupWizardBtn').addEventListener('click', () => closeSetupWizard());
  $('#setupWizardCancelBtn').addEventListener('click', () => closeSetupWizard());
  $('#setupWizardInstallBtn').addEventListener('click', () => runSetupWizardInstall());
  $('#closeActionHelpBtn').addEventListener('click', () => closeActionHelp());
  $('#actionHelpModal').addEventListener('click', (event) => {
    if (event.target === $('#actionHelpModal')) closeActionHelp();
  });
  all('.help-link[data-help-actions]').forEach((button) => {
    button.addEventListener('click', () => openActionHelp(button.dataset.helpActions));
  });
  $('#wizardInternetHosting').addEventListener('change', () => {
    if ($('#wizardInternetHosting').checked && !$('#wizardFirewall').disabled) $('#wizardFirewall').checked = true;
  });
  $('#toggleWizardPassword').addEventListener('click', () => {
    const input = $('#wizardJoinPassword');
    const button = $('#toggleWizardPassword');
    const isHidden = input.type === 'password';
    input.type = isHidden ? 'text' : 'password';
    button.title = isHidden ? 'Hide password' : 'Show password';
    button.setAttribute('aria-label', isHidden ? 'Hide password' : 'Show password');
    button.classList.toggle('revealed', isHidden);
  });

  $('#saveSettingsBtn').addEventListener('click', async () => {
    try {
      const result = await api('/api/settings', {
        method: 'POST',
        body: JSON.stringify({ settings: collectSettings() })
      });
      state.settings = result.settings;
      state.settingsDirty = false;
      await api('/api/env', {
        method: 'POST',
        body: JSON.stringify({
          env: {
            PZ_MOD_WARNING_SECONDS: $('#modWarningSeconds').value,
            PZ_MOD_REFRESH_WINDOW_START: $('#modWindowStart').value,
            PZ_MOD_REFRESH_WINDOW_END: $('#modWindowEnd').value,
            PZ_AUTO_REFRESH_MODS: String($('#autoRefreshMods').checked)
          }
        })
      });
      appendOutput('Settings saved.');
      await refresh();
    } catch (error) {
      appendOutput(error.message);
    }
  });

  $('#toggleJoinPassword').addEventListener('click', () => {
    const input = $('#joinPasswordInput');
    const button = $('#toggleJoinPassword');
    const isHidden = input.type === 'password';
    input.type = isHidden ? 'text' : 'password';
    button.title = isHidden ? 'Hide password' : 'Show password';
    button.setAttribute('aria-label', isHidden ? 'Hide password' : 'Show password');
    button.classList.toggle('revealed', isHidden);
  });

  $('#settingsForm').addEventListener('input', () => { state.settingsDirty = true; });
  $('#settingsForm').addEventListener('change', () => { state.settingsDirty = true; });
  $('#modLoadOrder').addEventListener('input', () => { state.modsDirty = true; });

  $('#iniConfigBtn').addEventListener('click', () => {
    state.activeConfigFile = 'ini';
    renderConfigFiles();
  });

  $('#sandboxConfigBtn').addEventListener('click', () => {
    state.activeConfigFile = 'sandbox';
    renderConfigFiles();
  });

  $('#configSearch').addEventListener('input', () => renderConfigFiles());
  $('#reloadConfigBtn').addEventListener('click', () => loadConfigFiles().catch((error) => appendOutput(error.message)));
  $('#saveConfigBtn').addEventListener('click', () => saveConfigChanges().catch((error) => appendOutput(error.message)));
  $('#configImportInput').addEventListener('change', (event) => {
    importActiveConfigFile(event.target.files?.[0]).catch((error) => appendOutput(error.message));
  });

  $('#addModBtn').addEventListener('click', () => {
    state.modsDirty = true;
    state.mods.push({ name: '', workshopId: '', modId: '', enabled: true, notes: '' });
    renderMods();
  });

  $('#saveModsBtn').addEventListener('click', async () => {
    try {
      const result = await api('/api/mods', {
        method: 'POST',
        body: JSON.stringify({
          mods: state.mods,
          modLoadOrder: $('#modLoadOrder').value.split(';').map((item) => item.trim()).filter(Boolean)
        })
      });
      state.mods = result.mods;
      state.modLoadOrder = result.modLoadOrder || [];
      state.modStateSource = result.modStateSource || 'mods.json';
      state.settings = result.settings;
      state.modsDirty = false;
      appendOutput('Mods saved to server.ini.');
      renderMods();
    } catch (error) {
      appendOutput(error.message);
    }
  });

  $('#checkModsBtn').addEventListener('click', async () => {
    try {
      appendOutput('Checking Steam Workshop metadata.');
      const result = await api('/api/mods/check', { method: 'POST', body: '{}' });
      state.mods = result.mods;
      renderMods();
      appendOutput('Mod update check complete.');
    } catch (error) {
      appendOutput(error.message);
    }
  });

  $('#repairModsBtn').addEventListener('click', async () => {
    if (!confirm('Repair the manager mod view from the best available server.ini or config backup? This rebuilds config\\mods.json and does not restart the server.')) return;
    try {
      appendOutput('Repairing mod view from the best available config source.');
      const result = await api('/api/mods/repair', { method: 'POST', body: '{}' });
      state.mods = result.mods || [];
      state.modLoadOrder = result.modLoadOrder || [];
      state.modStateSource = result.modStateSource || 'mods.json';
      state.modDiagnostics = result.modDiagnostics || {};
      state.settings = result.settings || state.settings;
      state.modsDirty = false;
      renderMods();
      appendOutput(`Mod view repaired from ${result.repairedFrom || 'config source'}: ${state.mods.length} rows.`);
    } catch (error) {
      appendOutput(error.message);
    }
  });

  $('#stagePendingModsBtn').addEventListener('click', () => runAction('prepareStagedUpdate').catch((error) => appendOutput(error.message)));
  $('#applyStagedModsBtn').addEventListener('click', () => {
    runAction('stagedRefresh').catch((error) => appendOutput(error.message));
  });

  $('#refreshBackupsBtn').addEventListener('click', () => refreshBackups().catch((error) => appendOutput(error.message)));

  all('[data-action]').forEach((button) => {
    button.addEventListener('click', () => runAction(button.dataset.action).catch((error) => appendOutput(error.message)));
  });
}

function activateTab(tab) {
  const button = $(`.nav[data-tab="${tab}"]`);
  const panel = $(`#${tab}`);
  if (!button || !panel) return;
  all('.nav').forEach((nav) => nav.classList.remove('active'));
  all('.panel').forEach((item) => item.classList.remove('active'));
  button.classList.add('active');
  panel.classList.add('active');
}

bindUi();
activateTab(location.hash.replace('#', '') || 'overview');
refresh().catch((error) => appendOutput(error.message));
setInterval(() => refresh().catch(() => {}), 10000);
