const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..', '..');
const publicDir = path.join(__dirname, 'public');
const configDir = path.join(root, 'config');
const envPath = path.join(configDir, 'server.env');
const modsPath = path.join(configDir, 'mods.json');
const defaultPort = Number(process.env.PZ_ADMIN_PANEL_PORT || 8787);
const jobLimit = 40;

const envOrder = [
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
];

const editableIniKeys = [
  'PublicName',
  'PublicDescription',
  'Password',
  'MaxPlayers',
  'Public',
  'Open',
  'PVP',
  'PauseEmpty',
  'DefaultPort',
  'UDPPort',
  'RCONPort',
  'RCONPassword',
  'Map',
  'Mods',
  'WorkshopItems',
  'DoLuaChecksum',
  'SteamVAC',
  'VoiceEnable',
  'SleepAllowed',
  'SleepNeeded',
  'BackupsOnStart',
  'BackupsOnVersionChange',
  'BackupsPeriod',
  'BackupsCount'
];

const actions = {
  start: ['scripts\\ops\\Start-PzServer.ps1'],
  stop: ['scripts\\ops\\Stop-PzServer.ps1', '-TimeoutSeconds', '90', '-Force'],
  restart: ['scripts\\ops\\Restart-PzServer.ps1', '-BackupFirst'],
  update: ['scripts\\ops\\Update-PzServer.ps1'],
  backup: ['scripts\\ops\\Backup-PzSaves.ps1'],
  watchdog: ['scripts\\ops\\Watchdog-PzServer.ps1'],
  applyConfig: ['scripts\\ops\\Apply-Config.ps1'],
  pruneBackups: ['scripts\\ops\\Prune-Backups.ps1'],
  pruneLogs: ['internal:pruneLogs'],
  updateMods: ['scripts\\ops\\Update-PzMods.ps1'],
  refreshMods: ['scripts\\ops\\Refresh-PzMods.ps1'],
  smartRefreshMods: ['scripts\\ops\\Invoke-PzAutomationMaintenance.ps1'],
  automationCheck: ['scripts\\ops\\Invoke-PzAutomationMaintenance.ps1', '-CheckOnly', '-IgnoreWindow'],
  prepareStagedUpdate: ['scripts\\ops\\Prepare-PzStagedUpdate.ps1'],
  stagedRefresh: ['scripts\\ops\\Invoke-PzStagedRefresh.ps1', '-SkipPrepare'],
  rollbackStagedUpdate: ['scripts\\ops\\Rollback-PzStagedUpdate.ps1', '-Restart'],
  installFirewallRules: ['scripts\\ops\\Install-PzFirewallRules.ps1'],
  enableAutomation: ['scripts\\tasks\\Register-PzScheduledTasks.ps1', '-IncludeSmartModRefresh'],
  disableAutomation: ['scripts\\tasks\\Disable-PzAutomation.ps1']
};

const backgroundActions = new Set([
  'updateMods',
  'refreshMods',
  'smartRefreshMods',
  'automationCheck',
  'prepareStagedUpdate',
  'stagedRefresh',
  'rollbackStagedUpdate',
  'update'
]);

const settingEnvKeys = {
  PublicName: 'PZ_PUBLIC_NAME',
  PublicDescription: 'PZ_PUBLIC_DESCRIPTION',
  Password: 'PZ_PASSWORD',
  MaxPlayers: 'PZ_MAX_PLAYERS',
  DefaultPort: 'PZ_PORT',
  UDPPort: 'PZ_UDP_PORT',
  RCONPort: 'PZ_RCON_PORT',
  RCONPassword: 'PZ_RCON_PASSWORD'
};

function readEnv() {
  if (!fs.existsSync(envPath)) return {};
  return Object.fromEntries(
    fs.readFileSync(envPath, 'utf8')
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('#') && line.includes('='))
      .map((line) => {
        const index = line.indexOf('=');
        return [line.slice(0, index).trim(), line.slice(index + 1).trim()];
      })
  );
}

function writeAdminPanelPid() {
  const env = readEnv();
  const stateDir = env.PZ_STATE_DIR || 'C:\\pz\\state';
  fs.mkdirSync(stateDir, { recursive: true });
  fs.writeFileSync(path.join(stateDir, 'admin-panel.pid'), `${process.pid}\n`, 'utf8');
}

function writeEnv(values) {
  const known = new Set(envOrder);
  const merged = { ...readEnv(), ...values };
  const lines = [];

  for (const key of envOrder) {
    if (Object.prototype.hasOwnProperty.call(merged, key)) {
      lines.push(`${key}=${merged[key] ?? ''}`);
      if (key === 'PZ_STAGING_DIR' || key === 'PZ_WATCHDOG_MIN_RESTART_SECONDS') {
        lines.push('');
      }
    }
  }

  for (const key of Object.keys(merged).sort()) {
    if (!known.has(key)) lines.push(`${key}=${merged[key] ?? ''}`);
  }

  fs.writeFileSync(envPath, `${lines.join('\n').replace(/\n{3,}/g, '\n\n').trim()}\n`, 'utf8');
}

function syncSettingsToEnv(settings) {
  const envUpdates = {};
  for (const [settingKey, envKey] of Object.entries(settingEnvKeys)) {
    if (Object.prototype.hasOwnProperty.call(settings, settingKey)) {
      envUpdates[envKey] = settings[settingKey] ?? '';
    }
  }
  if (Object.keys(envUpdates).length > 0) writeEnv(envUpdates);
}

function serverIniPath() {
  const env = readEnv();
  const profileDir = env.PZ_PROFILE_DIR || 'C:\\pz\\profile';
  const serverName = env.PZ_SERVER_NAME || 'servertest';
  return path.join(profileDir, 'Server', `${serverName}.ini`);
}

function sandboxVarsPath() {
  const env = readEnv();
  const profileDir = env.PZ_PROFILE_DIR || 'C:\\pz\\profile';
  const serverName = env.PZ_SERVER_NAME || 'servertest';
  return path.join(profileDir, 'Server', `${serverName}_SandboxVars.lua`);
}

function readIni(filePath) {
  if (!fs.existsSync(filePath)) return { values: {}, lines: [] };
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  return { values: parseIniValues(lines.join('\n')), lines };
}

function readConfigText(filePath) {
  if (!fs.existsSync(filePath)) return '';
  return fs.readFileSync(filePath, 'utf8');
}

function parseIniValues(text) {
  const values = {};
  for (const line of String(text || '').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim();
    values[key] = trimmed.slice(index + 1);
  }
  return values;
}

function inferValueType(value) {
  const trimmed = String(value || '').trim();
  if (/^(true|false)$/i.test(trimmed)) return 'boolean';
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return 'number';
  if (/^".*"$/.test(trimmed)) return 'string';
  return 'text';
}

function parseIniEntries(text) {
  const lines = text.split(/\r?\n/);
  const entries = [];
  let comments = [];

  lines.forEach((line, index) => {
    const trimmed = line.trim();
    if (!trimmed) {
      comments = [];
      return;
    }
    if (trimmed.startsWith('#')) {
      comments.push(trimmed.replace(/^#\s?/, ''));
      return;
    }

    const match = line.match(/^([^#=\s][^=]*)=(.*)$/);
    if (!match) {
      comments = [];
      return;
    }

    const key = match[1].trim();
    entries.push({
      id: `ini:${index}`,
      file: 'ini',
      index,
      key,
      path: key,
      value: match[2],
      comment: comments.join('\n'),
      type: inferValueType(match[2])
    });
    comments = [];
  });

  return entries;
}

function parseSandboxEntries(text) {
  const lines = text.split(/\r?\n/);
  const entries = [];
  const stack = [];
  let comments = [];

  lines.forEach((line, index) => {
    const trimmed = line.trim();
    if (!trimmed) {
      comments = [];
      return;
    }
    if (trimmed.startsWith('--')) {
      comments.push(trimmed.replace(/^--\s?/, ''));
      return;
    }
    if (/^},?\s*$/.test(trimmed)) {
      stack.pop();
      comments = [];
      return;
    }

    const section = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*\{\s*$/);
    if (section) {
      if (section[1] !== 'SandboxVars') stack.push(section[1]);
      comments = [];
      return;
    }

    const assignment = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)(,?)\s*$/);
    if (!assignment || assignment[2].trim().startsWith('{')) {
      comments = [];
      return;
    }

    const key = assignment[1];
    const category = stack.join('.');
    const pathName = category ? `${category}.${key}` : key;
    entries.push({
      id: `sandbox:${index}`,
      file: 'sandbox',
      index,
      key,
      path: pathName,
      category,
      value: assignment[2].trim(),
      comment: comments.join('\n'),
      type: inferValueType(assignment[2])
    });
    comments = [];
  });

  return entries;
}

function replaceIniValue(line, key, value) {
  const match = line.match(/^([^#=\s][^=]*)=(.*)$/);
  if (!match || match[1].trim() !== key) return null;
  return `${match[1]}=${value}`;
}

function replaceSandboxValue(line, key, value) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(`^(\\s*${escaped}\\s*=\\s*)(.*?)(,?\\s*)$`);
  const match = line.match(regex);
  if (!match) return null;
  return `${match[1]}${value}${match[3]}`;
}

function writeConfigUpdates(fileType, updates) {
  const filePath = fileType === 'sandbox' ? sandboxVarsPath() : serverIniPath();
  if (!fs.existsSync(filePath)) {
    throw new Error(`${fileType === 'sandbox' ? 'SandboxVars' : 'server.ini'} file does not exist yet. Apply config first.`);
  }

  const lines = readConfigText(filePath).split(/\r?\n/);
  for (const update of updates) {
    const index = Number(update.index);
    if (!Number.isInteger(index) || index < 0 || index >= lines.length) {
      throw new Error(`Invalid line index for ${update.key}.`);
    }

    const value = String(update.value ?? '');
    const key = String(update.key || '');
    const nextLine = fileType === 'sandbox'
      ? replaceSandboxValue(lines[index], key, value)
      : replaceIniValue(lines[index], key, value);
    if (nextLine === null) {
      throw new Error(`Line ${index + 1} no longer matches ${key}. Refresh before saving.`);
    }
    lines[index] = nextLine;
  }

  const env = readEnv();
  const backupDir = env.PZ_BACKUP_DIR || 'C:\\pz\\backups';
  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
  fs.copyFileSync(filePath, path.join(backupDir, `${path.basename(filePath)}-${stamp}.bak`));
  fs.writeFileSync(filePath, lines.join('\n'), 'utf8');
}

function assertConfigImportLooksSafe(fileType, content) {
  if (typeof content !== 'string') {
    throw new Error('Uploaded config content must be text.');
  }
  if (content.length > 2_500_000) {
    throw new Error('Uploaded config file is too large.');
  }
  if (content.includes('\0')) {
    throw new Error('Uploaded config file contains binary data.');
  }

  const normalized = content.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  if (fileType === 'sandbox') {
    if (!/SandboxVars\s*=\s*\{/.test(normalized) || parseSandboxEntries(normalized).length < 1) {
      throw new Error('SandboxVars import must look like a Project Zomboid SandboxVars Lua file.');
    }
    return normalized;
  }

  if (parseIniEntries(normalized).length < 1 || !/^[A-Za-z][A-Za-z0-9_]*=.*$/m.test(normalized)) {
    throw new Error('Server INI import must look like a Project Zomboid server INI file.');
  }
  return normalized;
}

function importConfigFile(fileType, content) {
  const filePath = fileType === 'sandbox' ? sandboxVarsPath() : serverIniPath();
  const nextContent = assertConfigImportLooksSafe(fileType, content);
  const env = readEnv();
  const backupDir = env.PZ_BACKUP_DIR || 'C:\\pz\\backups';
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.mkdirSync(backupDir, { recursive: true });

  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
  if (fs.existsSync(filePath)) {
    fs.copyFileSync(filePath, path.join(backupDir, `${path.basename(filePath)}-before-import-${stamp}.bak`));
  }

  fs.writeFileSync(filePath, `${nextContent.replace(/\n+$/, '')}\n`, 'utf8');
  return filePath;
}

function writeIni(filePath, updates) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const previous = readIni(filePath);
  const seen = new Set();
  const nextLines = previous.lines.map((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) return line;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index);
    if (!Object.prototype.hasOwnProperty.call(updates, key)) return line;
    seen.add(key);
    return `${key}=${updates[key] ?? ''}`;
  });

  for (const [key, value] of Object.entries(updates)) {
    if (!seen.has(key)) nextLines.push(`${key}=${value ?? ''}`);
  }

  if (fs.existsSync(filePath)) {
    const env = readEnv();
    const backupDir = env.PZ_BACKUP_DIR || 'C:\\pz\\backups';
    fs.mkdirSync(backupDir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
    fs.copyFileSync(filePath, path.join(backupDir, `server-config-${stamp}.ini.bak`));
  }

  fs.writeFileSync(filePath, `${nextLines.join('\n').replace(/\n+$/, '')}\n`, 'utf8');
}

function readMods() {
  if (!fs.existsSync(modsPath)) return [];
  try {
    const parsed = JSON.parse(fs.readFileSync(modsPath, 'utf8'));
    if (Array.isArray(parsed)) return parsed;
    if (Array.isArray(parsed.entries)) return parsed.entries;
    return [];
  } catch {
    return [];
  }
}

function readModState() {
  if (!fs.existsSync(modsPath)) return { entries: [], modLoadOrder: [] };
  try {
    const parsed = JSON.parse(fs.readFileSync(modsPath, 'utf8'));
    if (Array.isArray(parsed)) return { entries: parsed, modLoadOrder: [] };
    return {
      entries: Array.isArray(parsed.entries) ? parsed.entries : [],
      modLoadOrder: Array.isArray(parsed.modLoadOrder) ? parsed.modLoadOrder : []
    };
  } catch {
    return { entries: [], modLoadOrder: [] };
  }
}

function modStateFromIni(iniValues) {
  const workshopIds = splitModIds(iniValues.WorkshopItems || '');
  const modIds = normalizeModLoadOrder(iniValues.Mods || '', workshopIds);
  const hasWorkshopIds = workshopIds.length > 0;
  const pairedModIds = hasWorkshopIds && modIds.length === workshopIds.length ? modIds : [];
  const max = hasWorkshopIds ? workshopIds.length : modIds.length;
  const entries = [];

  for (let index = 0; index < max; index++) {
    const workshopId = workshopIds[index] || '';
    const modId = hasWorkshopIds ? (pairedModIds[index] || '') : (modIds[index] || '');
    entries.push({
      name: modId || workshopId || `Imported mod ${index + 1}`,
      workshopId,
      modId,
      enabled: true,
      lastKnownUpdated: 0,
      lastCheckedAt: '',
      needsUpdate: false,
      notes: workshopId && modId ? 'Recovered from server.ini' : 'Recovered from server.ini; verify Workshop ID and Mod ID pairing.',
      steamTitle: '',
      steamUrl: workshopId ? `https://steamcommunity.com/sharedfiles/filedetails/?id=${workshopId}` : '',
      currentSteamUpdated: 0,
      unavailable: false
    });
  }

  return { entries, modLoadOrder: modIds, recoveredFromIni: true };
}

function normalizeModLoadOrder(value, workshopIds = []) {
  const workshopSet = new Set(workshopIds.map((id) => String(id)));
  const result = [];
  const rawTokens = splitModIds(value).map((item) => item.replace(/^\\+/, '').trim()).filter(Boolean);
  for (const token of rawTokens) {
    if (/^\d+$/.test(token) && workshopSet.has(token)) continue;
    const glued = token.match(/^(\d{10})([A-Za-z_].+)$/);
    if (glued && workshopSet.has(glued[1])) {
      result.push(glued[2]);
      continue;
    }
    result.push(token);
  }
  return result;
}

function modStateFromIniFile(filePath) {
  if (!fs.existsSync(filePath)) return null;
  const ini = readIni(filePath).values;
  const state = modStateFromIni(ini);
  return {
    ...state,
    sourcePath: filePath,
    workshopCount: splitModIds(ini.WorkshopItems || '').length,
    loadOrderCount: normalizeModLoadOrder(ini.Mods || '', splitModIds(ini.WorkshopItems || '')).length
  };
}

function modRecoveryCandidates() {
  const env = readEnv();
  const backupDir = env.PZ_BACKUP_DIR || 'C:\\pz\\backups';
  const candidates = [];
  const active = modStateFromIniFile(serverIniPath());
  if (active) candidates.push({ ...active, sourceLabel: 'active server.ini', modified: fs.existsSync(serverIniPath()) ? fs.statSync(serverIniPath()).mtime.toISOString() : '' });

  if (fs.existsSync(backupDir)) {
    for (const name of fs.readdirSync(backupDir)) {
      if (!/(\.ini\.bak|server-config-.+\.bak|servertest\.ini-.+\.bak)$/i.test(name)) continue;
      const fullPath = path.join(backupDir, name);
      const recovered = modStateFromIniFile(fullPath);
      if (!recovered) continue;
      candidates.push({
        ...recovered,
        sourceLabel: `backup ${name}`,
        modified: fs.statSync(fullPath).mtime.toISOString()
      });
    }
  }

  return candidates
    .filter((candidate) => candidate.entries.length > 0 || candidate.modLoadOrder.length > 0)
    .sort((a, b) => {
      const workshopDelta = b.workshopCount - a.workshopCount;
      if (workshopDelta !== 0) return workshopDelta;
      const entryDelta = b.entries.length - a.entries.length;
      if (entryDelta !== 0) return entryDelta;
      const loadDelta = b.loadOrderCount - a.loadOrderCount;
      if (loadDelta !== 0) return loadDelta;
      return String(b.modified || '').localeCompare(String(a.modified || ''));
    });
}

function effectiveModState() {
  const stored = readModState();
  const ini = readIni(serverIniPath()).values;
  const iniState = modStateFromIni(ini);

  if (stored.entries.length === 0 && iniState.entries.length > 0) {
    writeMods(iniState.entries, iniState.modLoadOrder);
    return iniState;
  }

  if (stored.modLoadOrder.length === 0 && iniState.modLoadOrder.length > 0) {
    writeMods(stored.entries, iniState.modLoadOrder);
    return { ...stored, modLoadOrder: iniState.modLoadOrder, recoveredFromIni: true };
  }

  return { ...stored, recoveredFromIni: false };
}

function modDiagnostics() {
  const stored = readModState();
  const ini = readIni(serverIniPath()).values;
  const iniState = modStateFromIni(ini);
  const candidates = modRecoveryCandidates();
  const best = candidates[0] || null;
  return {
    storedEntryCount: stored.entries.length,
    storedLoadOrderCount: stored.modLoadOrder.length,
    iniWorkshopCount: splitModIds(ini.WorkshopItems || '').length,
    iniLoadOrderCount: normalizeModLoadOrder(ini.Mods || '', splitModIds(ini.WorkshopItems || '')).length,
    backupRecoveryCount: candidates.filter((candidate) => candidate.sourceLabel !== 'active server.ini').length,
    bestRecoverySource: best ? best.sourceLabel : '',
    bestRecoveryWorkshopCount: best ? best.workshopCount : 0,
    bestRecoveryLoadOrderCount: best ? best.loadOrderCount : 0,
    recoverableFromIni: iniState.entries.length > 0 || candidates.length > 0,
    needsEntryRepair: stored.entries.length === 0 && iniState.entries.length > 0,
    needsLoadOrderRepair: stored.modLoadOrder.length === 0 && iniState.modLoadOrder.length > 0,
    modsPath,
    iniPath: serverIniPath()
  };
}

function repairModsFromIni() {
  const candidates = modRecoveryCandidates();
  const best = candidates[0];
  if (!best || (best.entries.length === 0 && best.modLoadOrder.length === 0)) {
    throw new Error('No WorkshopItems or Mods were found in the active server.ini or config backups.');
  }
  if (best.workshopCount === 0) {
    throw new Error(`Only a Mods load order was found in ${best.sourceLabel}; no WorkshopItems were available to restore. Import a previous server.ini that still has WorkshopItems.`);
  }
  writeMods(best.entries, best.modLoadOrder);
  return { ...effectiveModState(), repairedFrom: best.sourceLabel, repairedFromPath: best.sourcePath };
}

function repairModsFromIniText(content) {
  const normalized = assertConfigImportLooksSafe('ini', content);
  const values = parseIniValues(normalized);
  const state = modStateFromIni(values);
  if (state.entries.length === 0 || splitModIds(values.WorkshopItems || '').length === 0) {
    throw new Error('The selected server.ini does not contain a usable WorkshopItems list. Choose the server.ini from the working modded server.');
  }

  writeMods(state.entries, state.modLoadOrder);
  syncModsToIni(state.entries, state.modLoadOrder);
  return { ...effectiveModState(), repairedFrom: 'imported server.ini' };
}

function writeMods(mods, modLoadOrder = []) {
  const clean = mods.map((mod) => ({
    name: String(mod.name || '').trim(),
    workshopId: String(mod.workshopId || '').trim(),
    modId: String(mod.modId || '').trim(),
    enabled: Boolean(mod.enabled),
    lastKnownUpdated: Number(mod.lastKnownUpdated || 0),
    lastCheckedAt: mod.lastCheckedAt || '',
    needsUpdate: Boolean(mod.needsUpdate),
    notes: String(mod.notes || '').trim(),
    steamTitle: String(mod.steamTitle || '').trim(),
    steamUrl: String(mod.steamUrl || '').trim(),
    currentSteamUpdated: Number(mod.currentSteamUpdated || 0),
    unavailable: Boolean(mod.unavailable)
  })).filter((mod) => mod.name || mod.workshopId || mod.modId);
  const cleanLoadOrder = modLoadOrder.map((modId) => String(modId || '').trim()).filter(Boolean);
  fs.writeFileSync(modsPath, `${JSON.stringify({ entries: clean, modLoadOrder: cleanLoadOrder }, null, 2)}\n`, 'utf8');
  return clean;
}

function assertNoDangerousModWipe(mods, modLoadOrder = []) {
  const currentIni = readIni(serverIniPath()).values;
  const existingWorkshop = splitModIds(currentIni.WorkshopItems || '');
  const nextWorkshop = mods.filter((mod) => mod.enabled && String(mod.workshopId || '').trim()).map((mod) => String(mod.workshopId).trim());
  const nextLoadOrder = modLoadOrder.length > 0
    ? modLoadOrder
    : mods.filter((mod) => mod.enabled).flatMap((mod) => splitModIds(mod.modId));

  if (existingWorkshop.length > 0 && nextWorkshop.length === 0) {
    throw new Error(`Refusing to save an empty WorkshopItems list over ${existingWorkshop.length} active Workshop item(s). Repair mods first or remove mods intentionally from the config editor.`);
  }
  if (splitModIds(currentIni.Mods || '').length > 0 && nextLoadOrder.length === 0) {
    throw new Error('Refusing to save an empty Mods load order over the active server.ini load order. Repair mods first or remove mods intentionally from the config editor.');
  }
}

function splitModIds(value) {
  return String(value || '')
    .split(';')
    .map((item) => item.trim())
    .filter(Boolean);
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    if (!seen.has(value)) {
      seen.add(value);
      result.push(value);
    }
  }
  return result;
}

function syncModsToIni(mods, modLoadOrder = []) {
  const currentIni = readIni(serverIniPath()).values;
  const enabled = mods.filter((mod) => mod.enabled);
  const workshopIds = unique(enabled.map((mod) => mod.workshopId).filter(Boolean));
  const loadOrder = modLoadOrder.length > 0
    ? modLoadOrder
    : enabled.flatMap((mod) => splitModIds(mod.modId));
  const modIds = unique(loadOrder).join(';');
  const updates = { Mods: modIds };

  if (workshopIds.length > 0 || !currentIni.WorkshopItems) {
    updates.WorkshopItems = workshopIds.join(';');
  }

  writeIni(serverIniPath(), updates);
}

function runPowerShell(args) {
  return new Promise((resolve) => {
    const scriptArgs = [
      path.join(root, args[0]).replace(/\//g, '\\'),
      ...args.slice(1)
    ];
    const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ...scriptArgs], {
      cwd: root,
      windowsHide: true
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

function runPowerShellDynamic(scriptPath, extraArgs = []) {
  return runPowerShell([scriptPath, ...extraArgs]);
}

async function runApplyConfigThenRestart() {
  const apply = await runPowerShell(actions.applyConfig);
  if (apply.code !== 0) {
    return { ...apply, stdout: `Apply Config failed.\n${apply.stdout}` };
  }

  const restart = await runPowerShell(actions.restart);
  return {
    code: restart.code,
    stdout: [apply.stdout, restart.stdout].filter(Boolean).join('\n'),
    stderr: [apply.stderr, restart.stderr].filter(Boolean).join('\n')
  };
}

function runStatus() {
  const statusScript = path.join(root, 'scripts\\ops\\Get-PzServerStatus.ps1');
  return new Promise((resolve) => {
    const command = `& '${statusScript.replace(/'/g, "''")}' | ConvertTo-Json -Compress; exit 0`;
    const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], {
      cwd: root,
      windowsHide: true
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('close', () => {
      try {
        resolve({ ok: true, status: JSON.parse(stdout.trim()), stderr });
      } catch {
        resolve({ ok: false, status: null, stdout, stderr });
      }
    });
  });
}

function runPlayers() {
  const playersScript = path.join(root, 'scripts\\ops\\Get-PzPlayers.ps1');
  return new Promise((resolve) => {
    const command = `& '${playersScript.replace(/'/g, "''")}' | ConvertTo-Json -Compress; exit 0`;
    const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], {
      cwd: root,
      windowsHide: true
    });
    let stdout = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.on('close', () => {
      try {
        resolve(JSON.parse(stdout.trim()));
      } catch {
        resolve({ PlayerCount: -1, QueryReliable: false });
      }
    });
  });
}

function runSetupCheck() {
  return new Promise((resolve) => {
    const scriptPath = path.join(root, 'scripts\\install\\Test-PzSetup.ps1');
    const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, '-Json'], {
      cwd: root,
      windowsHide: true
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('close', (code) => {
      try {
        const setup = normalizeSetupCheck(JSON.parse(stdout.trim()));
        resolve({ ok: code === 0 || setup.ok, setup, stderr });
      } catch {
        resolve({ ok: false, setup: null, stdout, stderr });
      }
    });
  });
}

function normalizeSetupCheck(setup) {
  if (!setup || !Array.isArray(setup.checks)) return setup;
  const checks = setup.checks.map((check) => {
    if (check.id !== 'adminPanel') return check;
    return {
      ...check,
      ok: true,
      detail: `Serving this page from PID ${process.pid}`,
      next: ''
    };
  });
  const blocking = checks.filter((check) => !check.ok && !['firewall', 'automation', 'stagedUpdate', 'rollback', 'adminPanel'].includes(check.id));
  return {
    ...setup,
    ok: blocking.length === 0,
    checks
  };
}

function runSetupInstall(options) {
  const memoryPreset = String(options.memoryPreset || 'normal');
  const memory = {
    low: ['1024m', '3072m'],
    normal: ['2048m', '4096m'],
    large: ['4096m', '8192m']
  }[memoryPreset] || ['2048m', '4096m'];
  const maxPlayers = Math.max(1, Math.min(100, Number(options.maxPlayers || 8)));
  const runtimeRoot = String(options.runtimeRoot || 'C:\\pz').trim() || 'C:\\pz';
  const args = [
    'scripts\\install\\Install-PzManager.ps1',
    '-RuntimeRoot', runtimeRoot.slice(0, 180),
    '-PublicName', String(options.publicName || 'Project Zomboid Server').slice(0, 80),
    '-JoinPassword', String(options.joinPassword || '').slice(0, 80),
    '-MaxPlayers', String(maxPlayers),
    '-MemoryMin', memory[0],
    '-MemoryMax', memory[1]
  ];

  if (options.startServer) args.push('-StartServer');
  if (options.reuseServerFiles) args.push('-SkipServerInstall');
  if (options.installFirewallRules) args.push('-InstallFirewallRules');
  if (options.registerAutomation) args.push('-RegisterAutomation');

  return runPowerShell(args);
}

async function fetchWorkshopDetails(workshopIds) {
  const uniqueIds = [...new Set(workshopIds.filter(Boolean).map(String))];
  if (uniqueIds.length === 0) return [];

  const allDetails = [];
  for (let offset = 0; offset < uniqueIds.length; offset += 100) {
    const chunk = uniqueIds.slice(offset, offset + 100);
    const params = new URLSearchParams();
    params.set('itemcount', String(chunk.length));
    chunk.forEach((id, index) => params.set(`publishedfileids[${index}]`, id));

    const response = await fetch('https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params
    });

    if (!response.ok) {
      throw new Error(`Steam Workshop metadata request failed with HTTP ${response.status}.`);
    }

    const payload = await response.json();
    allDetails.push(...(payload?.response?.publishedfiledetails || []));
  }

  return allDetails;
}

async function checkModsForUpdates() {
  const modState = readModState();
  const mods = modState.entries;
  const details = await fetchWorkshopDetails(mods.map((mod) => mod.workshopId));
  const byId = new Map(details.map((detail) => [String(detail.publishedfileid), detail]));
  const checkedAt = new Date().toISOString();

  const checked = mods.map((mod) => {
    const detail = byId.get(String(mod.workshopId));
    if (!detail) {
      return { ...mod, lastCheckedAt: checkedAt, unavailable: Boolean(mod.workshopId), needsUpdate: false };
    }

    const updated = Number(detail.time_updated || 0);
    const previous = Number(mod.lastKnownUpdated || 0);
    return {
      ...mod,
      name: mod.name || detail.title || '',
      steamTitle: detail.title || '',
      lastKnownUpdated: Math.max(previous, updated),
      previousKnownUpdated: previous,
      currentSteamUpdated: updated,
      lastCheckedAt: checkedAt,
      needsUpdate: previous > 0 && updated > previous,
      unavailable: Number(detail.result) !== 1,
      fileUrl: detail.file_url || '',
      steamUrl: `https://steamcommunity.com/sharedfiles/filedetails/?id=${mod.workshopId}`
    };
  });

  writeMods(checked, modState.modLoadOrder);
  return checked;
}

function envPaths() {
  const env = readEnv();
  return {
    backupDir: env.PZ_BACKUP_DIR || 'C:\\pz\\backups',
    logDir: env.PZ_LOG_DIR || 'C:\\pz\\logs',
    stateDir: env.PZ_STATE_DIR || 'C:\\pz\\state',
    profileDir: env.PZ_PROFILE_DIR || 'C:\\pz\\profile'
  };
}

function statePath(name) {
  const { stateDir } = envPaths();
  fs.mkdirSync(stateDir, { recursive: true });
  return path.join(stateDir, name);
}

function readJobs() {
  const filePath = statePath('admin-jobs.json');
  if (!fs.existsSync(filePath)) return [];
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeJobs(jobs) {
  fs.writeFileSync(statePath('admin-jobs.json'), `${JSON.stringify(jobs.slice(0, jobLimit), null, 2)}\n`, 'utf8');
}

function startJob(action, label) {
  const job = {
    id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
    action,
    label,
    status: 'running',
    startedAt: new Date().toISOString(),
    finishedAt: '',
    code: null,
    summary: 'Action started.',
    stdoutTail: '',
    stderrTail: ''
  };
  writeJobs([job, ...readJobs()]);
  return job;
}

function finishJob(job, result) {
  const jobs = readJobs();
  const existing = jobs.find((item) => item.id === job.id) || job;
  existing.status = result.code === 0 ? 'succeeded' : 'failed';
  existing.finishedAt = new Date().toISOString();
  existing.code = result.code;
  existing.summary = result.code === 0 ? 'Action completed.' : 'Action failed.';
  existing.stdoutTail = String(result.stdout || '').slice(-3000);
  existing.stderrTail = String(result.stderr || '').slice(-3000);
  writeJobs([existing, ...jobs.filter((item) => item.id !== job.id)]);
  return existing;
}

async function runTrackedAction(action, runner) {
  const label = action.replace(/([A-Z])/g, ' $1').replace(/^./, (value) => value.toUpperCase());
  const job = startJob(action, label);
  try {
    const result = await runner();
    const finished = finishJob(job, result);
    return { ...result, job: finished };
  } catch (error) {
    const finished = finishJob(job, { code: 1, stdout: '', stderr: error.message });
    throw Object.assign(error, { job: finished });
  }
}

function runTrackedActionInBackground(action, runner) {
  const label = action.replace(/([A-Z])/g, ' $1').replace(/^./, (value) => value.toUpperCase());
  const job = startJob(action, label);
  Promise.resolve()
    .then(() => runner())
    .then((result) => finishJob(job, result))
    .catch((error) => finishJob(job, { code: 1, stdout: '', stderr: error.message }));
  return job;
}

function listBackups() {
  const { backupDir } = envPaths();
  if (!fs.existsSync(backupDir)) return [];
  return fs.readdirSync(backupDir)
    .filter((name) => /^pz-saves-.+\.zip$/i.test(name))
    .map((name) => {
      const fullPath = path.join(backupDir, name);
      const stat = fs.statSync(fullPath);
      return { name, fullPath, size: stat.size, modified: stat.mtime.toISOString() };
    })
    .sort((a, b) => b.modified.localeCompare(a.modified));
}

function retentionDays(envKey, fallback) {
  const env = readEnv();
  const value = Number(env[envKey] || fallback);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function backupGroomingSummary() {
  const retention = retentionDays('PZ_BACKUP_RETENTION_DAYS', 14);
  const now = Date.now();
  const backups = listBackups();
  const items = backups.map((backup) => {
    const modified = new Date(backup.modified);
    const deleteAt = new Date(modified.getTime() + retention * 86400000);
    return {
      ...backup,
      deleteAt: deleteAt.toISOString(),
      deleteInDays: Math.ceil((deleteAt.getTime() - now) / 86400000),
      eligible: deleteAt.getTime() <= now
    };
  });
  return {
    retentionDays: retention,
    totalCount: backups.length,
    totalBytes: backups.reduce((sum, backup) => sum + Number(backup.size || 0), 0),
    eligibleCount: items.filter((item) => item.eligible).length,
    nextDeleteAt: items.filter((item) => !item.eligible).sort((a, b) => a.deleteAt.localeCompare(b.deleteAt))[0]?.deleteAt || '',
    upcoming: items.sort((a, b) => a.deleteAt.localeCompare(b.deleteAt)).slice(0, 8)
  };
}

function collectLogs() {
  const { logDir, profileDir } = envPaths();
  const dirs = [logDir, path.join(profileDir, 'Logs')];
  const logs = [];
  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    for (const name of fs.readdirSync(dir)) {
      const fullPath = path.join(dir, name);
      if (!fs.statSync(fullPath).isFile()) continue;
      const stat = fs.statSync(fullPath);
      logs.push({ name, fullPath, size: stat.size, modified: stat.mtime.toISOString() });
    }
  }
  return logs.sort((a, b) => b.modified.localeCompare(a.modified));
}

function listLogs() {
  return collectLogs().slice(0, 80);
}

function tailFile(fullPath, maxBytes = 12000) {
  const logs = collectLogs();
  const allowed = logs.some((log) => log.fullPath === fullPath);
  if (!allowed) throw new Error('Log file is not in an allowed log directory.');
  const stat = fs.statSync(fullPath);
  const start = Math.max(0, stat.size - maxBytes);
  const fd = fs.openSync(fullPath, 'r');
  try {
    const buffer = Buffer.alloc(stat.size - start);
    fs.readSync(fd, buffer, 0, buffer.length, start);
    return buffer.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
}

function readJsonIfExists(filePath) {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function buildRestartRecommendation(modUpdate, stagedProgress, stagedReady) {
  if (stagedProgress?.phase === 'failed') {
    return {
      recommended: false,
      severity: 'danger',
      action: 'Review staged update failure',
      reason: stagedProgress.lastError || 'The staged update workflow failed. Review logs before restarting or applying staged refresh again.'
    };
  }

  if (modUpdate?.phase === 'failed') {
    return {
      recommended: false,
      severity: 'danger',
      action: 'Review mod update failure',
      reason: modUpdate.lastError || 'The last Workshop update failed. Keep the current server stable until the failed item is understood.'
    };
  }

  if (stagedProgress?.phase === 'prepared' || stagedReady) {
    return {
      recommended: true,
      severity: 'warning',
      action: 'Apply staged refresh during a quiet window',
      reason: stagedProgress?.restartReason || 'A staged server build exists. Applying it will briefly stop the active server, back up saves, swap directories, and restart if needed.'
    };
  }

  if (modUpdate?.restartRecommended) {
    return {
      recommended: true,
      severity: 'warning',
      action: 'Restart when players are clear',
      reason: modUpdate.restartReason || 'Workshop files were refreshed. Project Zomboid loads them at startup, so a restart is needed for the running server to use them.'
    };
  }

  if (stagedProgress?.phase && !['succeeded', 'skipped'].includes(stagedProgress.phase)) {
    return {
      recommended: false,
      severity: 'info',
      action: 'Wait for staged workflow',
      reason: stagedProgress.status || 'A staged update workflow is in progress.'
    };
  }

  if (modUpdate?.phase === 'running') {
    return {
      recommended: false,
      severity: 'info',
      action: 'Wait for mod update',
      reason: modUpdate.status || 'Workshop updates are currently running.'
    };
  }

  return {
    recommended: false,
    severity: 'ok',
    action: 'No restart pressure',
    reason: 'No completed mod or staged update is currently asking for a restart.'
  };
}

function automationTasksSummary() {
  if (process.platform !== 'win32') {
    return {
      supported: false,
      ok: false,
      totalCount: 0,
      enabledCount: 0,
      failedCount: 0,
      tasks: [],
      message: 'Windows scheduled task status is only available on Windows.'
    };
  }

  const command = `
    $ErrorActionPreference = 'Stop'
    $tasks = @(Get-ScheduledTask -TaskName 'PZ Vanilla *' -ErrorAction SilentlyContinue)
    $items = foreach ($task in $tasks) {
      $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
      [pscustomobject]@{
        name = $task.TaskName
        path = $task.TaskPath
        state = [string]$task.State
        enabled = ([string]$task.State -ne 'Disabled')
        lastRunTime = if ($info -and $info.LastRunTime -gt [datetime]'1900-01-01') { $info.LastRunTime.ToString('o') } else { $null }
        nextRunTime = if ($info -and $info.NextRunTime -gt [datetime]'1900-01-01') { $info.NextRunTime.ToString('o') } else { $null }
        lastTaskResult = if ($info) { [int]$info.LastTaskResult } else { $null }
      }
    }
    $items | ConvertTo-Json -Depth 4
  `;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
    timeout: 8000
  });

  if (result.error) {
    return {
      supported: true,
      ok: false,
      totalCount: 0,
      enabledCount: 0,
      failedCount: 0,
      tasks: [],
      message: result.error.message
    };
  }

  if (result.status !== 0) {
    return {
      supported: true,
      ok: false,
      totalCount: 0,
      enabledCount: 0,
      failedCount: 0,
      tasks: [],
      message: String(result.stderr || result.stdout || 'Unable to read scheduled tasks.').trim()
    };
  }

  const text = String(result.stdout || '').trim();
  let parsed = [];
  try {
    parsed = text ? JSON.parse(text) : [];
  } catch {
    return {
      supported: true,
      ok: false,
      totalCount: 0,
      enabledCount: 0,
      failedCount: 0,
      tasks: [],
      message: 'Scheduled task status returned unreadable output.'
    };
  }
  const tasks = (Array.isArray(parsed) ? parsed : [parsed]).filter(Boolean);
  const failed = tasks.filter((task) => Number(task.lastTaskResult || 0) !== 0);
  return {
    supported: true,
    ok: tasks.length > 0 && failed.length === 0,
    totalCount: tasks.length,
    enabledCount: tasks.filter((task) => task.enabled).length,
    failedCount: failed.length,
    tasks,
    message: tasks.length > 0 ? 'Scheduled automation tasks found.' : 'No PZ Vanilla scheduled automation tasks found.'
  };
}

function systemHealth() {
  const { stateDir } = envPaths();
  const env = readEnv();
  const stagingDir = env.PZ_STAGING_DIR || 'C:\\pz\\staging';
  const stagedServerDir = path.join(stagingDir, 'server-next');
  const rollbackServerDir = path.join(stagingDir, 'server-rollback');
  const manifestPath = path.join(stagingDir, 'staged-update.json');
  const statusPath = path.join(stateDir, 'watchdog-health.json');
  const pidPath = path.join(stateDir, 'server.pid');
  const adminPidPath = path.join(stateDir, 'admin-panel.pid');
  const modUpdate = readJsonIfExists(path.join(stateDir, 'mod-update.json'));
  const stagedProgress = readJsonIfExists(path.join(stateDir, 'staged-update-progress.json'));
  const automationMaintenance = readJsonIfExists(path.join(stateDir, 'automation-maintenance.json'));
  const restoreProgress = readJsonIfExists(path.join(stateDir, 'restore-progress.json'));
  const stagedReady = fs.existsSync(stagedServerDir);
  return {
    watchdog: readJsonIfExists(statusPath),
    serverPid: fs.existsSync(pidPath) ? fs.readFileSync(pidPath, 'utf8').trim() : '',
    adminPanelPid: fs.existsSync(adminPidPath) ? fs.readFileSync(adminPidPath, 'utf8').trim() : '',
    backups: listBackups().slice(0, 5),
    logs: listLogs().slice(0, 8),
    jobs: readJobs().slice(0, 10),
    backupGrooming: backupGroomingSummary(),
    logGrooming: logGroomingSummary(),
    modUpdate,
    restoreProgress,
    automationMaintenance,
    restartRecommendation: buildRestartRecommendation(modUpdate, stagedProgress, stagedReady),
    stagedUpdate: {
      stagedReady,
      rollbackReady: fs.existsSync(rollbackServerDir),
      manifest: readJsonIfExists(manifestPath),
      progress: stagedProgress,
      stagedServerDir,
      rollbackServerDir
    },
    automationTasks: automationTasksSummary()
  };
}

function modPreflight() {
  const modState = effectiveModState();
  const workshopIds = modState.entries.map((mod) => mod.workshopId).filter(Boolean);
  const loadOrder = modState.modLoadOrder;
  const duplicateWorkshop = workshopIds.filter((id, index) => workshopIds.indexOf(id) !== index);
  const duplicateMods = loadOrder.filter((id, index) => loadOrder.indexOf(id) !== index);
  const unavailable = modState.entries.filter((mod) => mod.unavailable);
  const missingNames = modState.entries.filter((mod) => !mod.name);
  return {
    workshopCount: workshopIds.length,
    loadOrderCount: loadOrder.length,
    duplicateWorkshop: unique(duplicateWorkshop),
    duplicateMods: unique(duplicateMods),
    unavailable,
    missingNames,
    recoveredFromIni: Boolean(modState.recoveredFromIni),
    ok: duplicateWorkshop.length === 0 && unavailable.length === 0
  };
}

function logGroomingSummary() {
  const retention = retentionDays('PZ_LOG_RETENTION_DAYS', 14);
  const now = Date.now();
  const logs = collectLogs();
  const items = logs.map((log) => {
    const modified = new Date(log.modified);
    const deleteAt = new Date(modified.getTime() + retention * 86400000);
    return {
      ...log,
      deleteAt: deleteAt.toISOString(),
      deleteInDays: Math.ceil((deleteAt.getTime() - now) / 86400000),
      eligible: deleteAt.getTime() <= now
    };
  });
  return {
    retentionDays: retention,
    totalCount: logs.length,
    totalBytes: logs.reduce((sum, log) => sum + Number(log.size || 0), 0),
    eligibleCount: items.filter((item) => item.eligible).length,
    nextDeleteAt: items.filter((item) => !item.eligible).sort((a, b) => a.deleteAt.localeCompare(b.deleteAt))[0]?.deleteAt || '',
    upcoming: items.sort((a, b) => a.deleteAt.localeCompare(b.deleteAt)).slice(0, 8)
  };
}

function pruneLogs() {
  const retention = retentionDays('PZ_LOG_RETENTION_DAYS', 14);
  const cutoff = Date.now() - retention * 86400000;
  const logs = collectLogs();
  const removed = [];
  for (const log of logs) {
    if (new Date(log.modified).getTime() >= cutoff) continue;
    fs.unlinkSync(log.fullPath);
    removed.push(log.fullPath);
  }
  return {
    code: 0,
    stdout: `Log pruning complete. Retention: ${retention} days. Removed ${removed.length} file(s).\n${removed.join('\n')}`,
    stderr: ''
  };
}

function restartAdminPanel() {
  setTimeout(() => {
    server.close(() => {
      const child = spawn(process.execPath, [__filename, String(defaultPort)], {
        cwd: __dirname,
        detached: true,
        env: { ...process.env, PZ_ADMIN_PANEL_PORT: String(defaultPort) },
        stdio: 'ignore',
        windowsHide: true
      });
      child.unref();
      process.exit(0);
    });
  }, 250);
}

function configFilesPayload() {
  const iniPath = serverIniPath();
  const sandboxPath = sandboxVarsPath();
  const iniText = readConfigText(iniPath);
  const sandboxText = readConfigText(sandboxPath);
  return {
    ok: true,
    files: {
      ini: {
        path: iniPath,
        exists: fs.existsSync(iniPath),
        raw: iniText,
        entries: parseIniEntries(iniText)
      },
      sandbox: {
        path: sandboxPath,
        exists: fs.existsSync(sandboxPath),
        raw: sandboxText,
        entries: parseSandboxEntries(sandboxText)
      }
    }
  };
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk.toString();
      if (body.length > 3_000_000) reject(new Error('Request body too large.'));
    });
    req.on('end', () => {
      if (!body) resolve({});
      else {
        try { resolve(JSON.parse(body)); }
        catch { reject(new Error('Invalid JSON.')); }
      }
    });
  });
}

function serveStatic(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (url.pathname === '/favicon.ico') {
    res.writeHead(204, { 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  const requested = url.pathname === '/' ? '/index.html' : url.pathname;
  const filePath = path.normalize(path.join(publicDir, requested));
  if (!filePath.startsWith(publicDir)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404);
    res.end('Not found');
    return;
  }
  const ext = path.extname(filePath).toLowerCase();
  const type = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8'
  }[ext] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  fs.createReadStream(filePath).pipe(res);
}

async function route(req, res) {
  try {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (!url.pathname.startsWith('/api/')) {
      serveStatic(req, res);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/state') {
      const env = readEnv();
      const ini = readIni(serverIniPath()).values;
      const modState = effectiveModState();
      const [status, players] = await Promise.all([runStatus(), runPlayers()]);
      const health = systemHealth();
      health.players = players;
      sendJson(res, 200, {
        env,
        settings: Object.fromEntries(editableIniKeys.map((key) => [key, ini[key] ?? ''])),
        mods: modState.entries,
        modLoadOrder: modState.modLoadOrder.length > 0 ? modState.modLoadOrder : splitModIds(ini.Mods || ''),
        modStateSource: modState.recoveredFromIni ? 'server.ini' : 'mods.json',
        modDiagnostics: modDiagnostics(),
        health,
        preflight: modPreflight(),
        status,
        paths: { root, envPath, modsPath, iniPath: serverIniPath(), sandboxPath: sandboxVarsPath() }
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/env') {
      const body = await readJsonBody(req);
      writeEnv(body.env || {});
      sendJson(res, 200, { ok: true, env: readEnv() });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/backups') {
      sendJson(res, 200, { ok: true, backups: listBackups() });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/logs') {
      sendJson(res, 200, { ok: true, logs: listLogs() });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/logs/tail') {
      const fullPath = url.searchParams.get('path') || '';
      sendJson(res, 200, { ok: true, content: tailFile(fullPath) });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/health') {
      sendJson(res, 200, { ok: true, health: systemHealth(), preflight: modPreflight() });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/setup') {
      const result = await runSetupCheck();
      sendJson(res, result.ok ? 200 : 500, result);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/setup/install') {
      const body = await readJsonBody(req);
      const result = await runSetupInstall(body || {});
      sendJson(res, result.code === 0 ? 200 : 500, { ok: result.code === 0, ...result });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/config-files') {
      sendJson(res, 200, configFilesPayload());
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/settings') {
      const body = await readJsonBody(req);
      const settings = body.settings || {};
      syncSettingsToEnv(settings);
      writeIni(serverIniPath(), settings);
      sendJson(res, 200, { ok: true, settings: readIni(serverIniPath()).values });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/config-files') {
      const body = await readJsonBody(req);
      const file = body.file === 'sandbox' ? 'sandbox' : 'ini';
      const updates = Array.isArray(body.updates) ? body.updates : [];
      if (updates.length > 0) writeConfigUpdates(file, updates);
      sendJson(res, 200, configFilesPayload());
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/config-files/import') {
      const body = await readJsonBody(req);
      const file = body.file === 'sandbox' ? 'sandbox' : 'ini';
      const importedPath = importConfigFile(file, String(body.content || ''));
      sendJson(res, 200, { ok: true, importedPath, ...configFilesPayload() });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/mods') {
      const body = await readJsonBody(req);
      assertNoDangerousModWipe(body.mods || [], body.modLoadOrder || []);
      const mods = writeMods(body.mods || [], body.modLoadOrder || []);
      const modState = readModState();
      syncModsToIni(mods, modState.modLoadOrder);
      const nextState = effectiveModState();
      sendJson(res, 200, { ok: true, mods: nextState.entries, modLoadOrder: nextState.modLoadOrder, modStateSource: nextState.recoveredFromIni ? 'server.ini' : 'mods.json', settings: readIni(serverIniPath()).values });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/mods/repair') {
      const modState = repairModsFromIni();
      sendJson(res, 200, {
        ok: true,
        mods: modState.entries,
        modLoadOrder: modState.modLoadOrder,
        modStateSource: modState.recoveredFromIni ? 'server.ini' : 'mods.json',
        modDiagnostics: modDiagnostics(),
        repairedFrom: modState.repairedFrom || '',
        repairedFromPath: modState.repairedFromPath || '',
        settings: readIni(serverIniPath()).values
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/mods/repair-file') {
      const body = await readJsonBody(req);
      const modState = repairModsFromIniText(body.content || '');
      sendJson(res, 200, {
        ok: true,
        mods: modState.entries,
        modLoadOrder: modState.modLoadOrder,
        modStateSource: 'imported server.ini',
        repairedFrom: modState.repairedFrom,
        settings: readIni(serverIniPath()).values,
        modDiagnostics: modDiagnostics()
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/mods/check') {
      const mods = await checkModsForUpdates();
      sendJson(res, 200, { ok: true, mods });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/action') {
      const body = await readJsonBody(req);
      if (body.action === 'shutdownPanel') {
        sendJson(res, 200, { ok: true, message: 'Admin panel shutting down.' });
        setTimeout(() => {
          server.close(() => process.exit(0));
        }, 250);
        return;
      }
      if (body.action === 'restartPanel') {
        sendJson(res, 200, { ok: true, message: 'Admin panel restarting. Refresh this page in a few seconds.' });
        restartAdminPanel();
        return;
      }
      if (body.action === 'restoreBackup') {
        const backups = listBackups();
        const backup = backups.find((item) => item.name === body.name);
        if (!backup) {
          sendJson(res, 404, { ok: false, error: 'Backup not found.' });
          return;
        }
        if (Number(backup.size || 0) <= 0) {
          sendJson(res, 400, { ok: false, error: 'Refusing to restore a 0 byte backup. Choose a non-empty save backup.' });
          return;
        }
        const job = runTrackedActionInBackground('restoreBackup', () => runPowerShellDynamic('scripts\\ops\\Restore-PzBackup.ps1', ['-BackupPath', backup.fullPath, '-Restart']));
        sendJson(res, 202, { ok: true, accepted: true, job, health: systemHealth(), preflight: modPreflight() });
        return;
      }
      if (body.action === 'applyConfigRestart') {
        const result = await runTrackedAction('applyConfigRestart', () => runApplyConfigThenRestart());
        sendJson(res, result.code === 0 ? 200 : 500, { ok: result.code === 0, ...result });
        return;
      }
      if (!actions[body.action]) {
        sendJson(res, 400, { ok: false, error: 'Unknown action.' });
        return;
      }
      if (backgroundActions.has(body.action)) {
        const job = runTrackedActionInBackground(body.action, () => runPowerShell(actions[body.action]));
        sendJson(res, 202, { ok: true, accepted: true, job, health: systemHealth(), preflight: modPreflight() });
        return;
      }
      const result = await runTrackedAction(body.action, () => {
        if (body.action === 'pruneLogs') return Promise.resolve(pruneLogs());
        return runPowerShell(actions[body.action]);
      });
      sendJson(res, result.code === 0 ? 200 : 500, { ok: result.code === 0, ...result });
      return;
    }

    sendJson(res, 404, { ok: false, error: 'Not found.' });
  } catch (error) {
    sendJson(res, 500, { ok: false, error: error.message });
  }
}

const server = http.createServer(route);
server.listen(defaultPort, '127.0.0.1', () => {
  writeAdminPanelPid();
  console.log(`Project Zomboid Admin Panel: http://127.0.0.1:${defaultPort}`);
});
