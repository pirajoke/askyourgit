// --- Header Actions ---

const aboutModal = document.getElementById('about-modal');
const settingsSection = document.getElementById('settings-section');

// Settings button — toggle settings visibility
document.getElementById('btn-settings').addEventListener('click', () => {
  const isHidden = settingsSection.style.display === 'none';
  settingsSection.style.display = isHidden ? '' : 'none';
});

// About button
document.getElementById('btn-about').addEventListener('click', () => {
  const manifest = chrome.runtime.getManifest();
  document.getElementById('about-version').textContent = `v${manifest.version}`;
  aboutModal.style.display = 'flex';
});

document.getElementById('about-close').addEventListener('click', () => {
  aboutModal.style.display = 'none';
});

aboutModal.addEventListener('click', (e) => {
  if (e.target === aboutModal) aboutModal.style.display = 'none';
});

// --- Settings ---

const clientSelect = document.getElementById('default-client');
const oneClickToggle = document.getElementById('one-click');
const customCommandInput = document.getElementById('custom-command');
const emojiPackSelect = document.getElementById('emoji-pack');
const shareTemplateInput = document.getElementById('share-template');
const terminalAppSelect = document.getElementById('terminal-app');
const bridgeStatus = document.getElementById('bridge-status');
const bridgeHint = document.getElementById('bridge-hint');
const claudeApiKeyInput = document.getElementById('claude-api-key');

// Load saved settings
chrome.storage.sync.get({
  defaultClient: '',
  oneClick: false,
  customCommand: '',
  emojiPack: 'animals',
  shareTemplate: '',
  terminalApp: 'auto',
  claudeApiKey: '',
  nftStats: { total: 0, tiers: {}, history: [] },
  smileStats: { summaries: 0, chats: 0, installs: 0, repos: [] },
}, (data) => {
  clientSelect.value = data.defaultClient;
  oneClickToggle.checked = data.oneClick;
  customCommandInput.value = data.customCommand;
  emojiPackSelect.value = data.emojiPack;
  shareTemplateInput.value = data.shareTemplate;
  terminalAppSelect.value = data.terminalApp;
  claudeApiKeyInput.value = data.claudeApiKey;
  updateOneClickState();
  renderStats(data.nftStats);
  renderHistory(data.nftStats.history);
  renderUsageStats(data.smileStats);
});

// Check bridge status
chrome.runtime.sendMessage({ action: 'check-bridge' }, (response) => {
  if (response && response.connected) {
    bridgeStatus.textContent = 'Connected';
    bridgeStatus.className = 'bridge-badge bridge-connected';
    bridgeHint.textContent = 'Commands will be sent directly to your terminal';
  } else {
    bridgeStatus.textContent = 'Not installed';
    bridgeStatus.className = 'bridge-badge bridge-disconnected';
    bridgeHint.textContent = 'Run: bash native-host/install.sh to enable';
  }
});

clientSelect.addEventListener('change', () => {
  chrome.storage.sync.set({ defaultClient: clientSelect.value });
  updateOneClickState();
});

oneClickToggle.addEventListener('change', () => {
  chrome.storage.sync.set({ oneClick: oneClickToggle.checked });
});

customCommandInput.addEventListener('input', () => {
  chrome.storage.sync.set({ customCommand: customCommandInput.value.trim() });
});

emojiPackSelect.addEventListener('change', () => {
  chrome.storage.sync.set({ emojiPack: emojiPackSelect.value });
});

shareTemplateInput.addEventListener('input', () => {
  chrome.storage.sync.set({ shareTemplate: shareTemplateInput.value.trim() });
});

terminalAppSelect.addEventListener('change', () => {
  chrome.storage.sync.set({ terminalApp: terminalAppSelect.value });
});

claudeApiKeyInput.addEventListener('input', () => {
  chrome.storage.sync.set({ claudeApiKey: claudeApiKeyInput.value.trim() });
});

function updateOneClickState() {
  oneClickToggle.disabled = !clientSelect.value;
  if (!clientSelect.value) {
    oneClickToggle.checked = false;
    chrome.storage.sync.set({ oneClick: false });
  }
}

// --- Stats ---

const TIER_COLORS = {
  common: '#8b949e',
  rare: '#3b82f6',
  epic: '#a855f7',
  legendary: '#eab308',
};

function renderStats(stats) {
  document.getElementById('stats-total').textContent = `${stats.total} roll${stats.total !== 1 ? 's' : ''}`;

  const tiersEl = document.getElementById('stats-tiers');
  if (stats.total === 0) {
    tiersEl.innerHTML = '';
    return;
  }

  const tiers = ['common', 'rare', 'epic', 'legendary'];
  tiersEl.textContent = '';
  tiers.forEach(t => {
    const count = stats.tiers[t] || 0;
    if (count === 0) return;
    const pct = Math.round((count / stats.total) * 100);
    const row = document.createElement('div');
    row.className = 'stats-tier-row';
    const dot = document.createElement('span');
    dot.className = 'stats-tier-dot';
    dot.style.background = TIER_COLORS[t];
    const name = document.createElement('span');
    name.className = 'stats-tier-name';
    name.textContent = t;
    const bar = document.createElement('span');
    bar.className = 'stats-tier-bar';
    const fill = document.createElement('span');
    fill.className = 'stats-tier-fill';
    fill.style.width = `${pct}%`;
    fill.style.background = TIER_COLORS[t];
    bar.appendChild(fill);
    const cnt = document.createElement('span');
    cnt.className = 'stats-tier-count';
    cnt.textContent = count;
    row.append(dot, name, bar, cnt);
    tiersEl.appendChild(row);
  });
}

function renderHistory(history) {
  const el = document.getElementById('share-history');
  el.textContent = '';
  if (!history || history.length === 0) {
    const hint = document.createElement('span');
    hint.className = 'hint';
    hint.style.marginLeft = '0';
    hint.textContent = 'No shares yet';
    el.appendChild(hint);
    return;
  }

  history.slice(0, 5).forEach(h => {
    const ago = timeAgo(h.time);
    const row = document.createElement('div');
    row.className = 'history-row';
    const emoji = document.createElement('span');
    emoji.className = 'history-emoji';
    emoji.textContent = h.emoji;
    const repo = document.createElement('span');
    repo.className = 'history-repo';
    repo.textContent = h.repo;
    const tier = document.createElement('span');
    tier.className = 'history-tier';
    tier.style.color = TIER_COLORS[h.tier];
    tier.textContent = h.tier;
    const time = document.createElement('span');
    time.className = 'history-time';
    time.textContent = ago;
    row.append(emoji, repo, tier, time);
    el.appendChild(row);
  });
}

function timeAgo(ts) {
  const diff = Date.now() - ts;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  const days = Math.floor(hrs / 24);
  return `${days}d`;
}

function renderUsageStats(stats) {
  document.getElementById('stat-summaries').textContent = stats.summaries || 0;
  document.getElementById('stat-chats').textContent = stats.chats || 0;
  document.getElementById('stat-installs').textContent = stats.installs || 0;
  document.getElementById('stat-repos').textContent = stats.repos?.length || 0;
}
