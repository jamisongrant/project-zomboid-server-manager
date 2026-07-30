const state = {
  env: {},
  settings: {},
  mods: [],
  modLoadOrder: [],
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
  modsDirty: false
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
}

function renderHealth() {
  const health = state.health || {};
  const preflight = state.preflight || {};
  const watchdog = health.watchdog || {};
  const staged = health.stagedUpdate || {};
  $('#playerCount').textContent = health.players?.PlayerCount ?? '-';
  $('#watchdogState').textContent = watchdog.running === true ? 'Healthy' : watchdog.maintenance ? 'Maintenance' : 'Unknown';
  $('#backupCount').textContent = String(state.backups.length || health.backups?.length || 0);
  $('#preflightState').textContent = preflight.ok ? 'Clean' : 'Review';
  $('#stagedUpdateState').textContent = staged.stagedReady ? 'Prepared' : staged.rollbackReady ? 'Rollback Ready' : 'None';
  $('#preflightSummary').textContent = `Workshop ${preflight.workshopCount || 0}, load order ${preflight.loadOrderCount || 0}, duplicate Workshop ${preflight.duplicateWorkshop?.length || 0}, duplicate Mod IDs ${preflight.duplicateMods?.length || 0}`;

  $('#healthDetails').innerHTML = [
    ['Server PID', health.serverPid || '-'],
    ['Admin panel PID', health.adminPanelPid || '-'],
    ['Staged server', staged.stagedReady ? staged.stagedServerDir : 'None'],
    ['Rollback server', staged.rollbackReady ? staged.rollbackServerDir : 'None'],
    ['Duplicate Workshop IDs', (preflight.duplicateWorkshop || []).join(', ') || 'None'],
    ['Duplicate Mod IDs', (preflight.duplicateMods || []).join(', ') || 'None']
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
  state.env = payload.env || {};
  state.settings = payload.settings || {};
  state.mods = payload.mods || [];
  state.modLoadOrder = payload.modLoadOrder || [];
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
  appendOutput(`Running ${action}`);
  const result = await api('/api/action', {
    method: 'POST',
    body: JSON.stringify({ action })
  });
  appendOutput([result.stdout, result.stderr].filter(Boolean).join('\n') || `${action} completed.`);
  if (action === 'shutdownPanel') {
    appendOutput('Admin panel closed. Run Open-AdminPanel.ps1 to reopen it.');
    return;
  }
  await refresh();
}

async function runRestore(name) {
  appendOutput(`Restoring ${name}`);
  const result = await api('/api/action', {
    method: 'POST',
    body: JSON.stringify({ action: 'restoreBackup', name })
  });
  appendOutput([result.stdout, result.stderr].filter(Boolean).join('\n') || 'Restore completed.');
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

  $('#stagePendingModsBtn').addEventListener('click', () => runAction('prepareStagedUpdate').catch((error) => appendOutput(error.message)));
  $('#applyStagedModsBtn').addEventListener('click', () => {
    if (!confirm('Apply staged refresh now? This warns players, stops the server, swaps staged files in, starts again, and rolls back if health fails.')) return;
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
