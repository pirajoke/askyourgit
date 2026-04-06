const clientSelect = document.getElementById('default-client');
const oneClickToggle = document.getElementById('one-click');
const customCommandInput = document.getElementById('custom-command');
const emojiPackSelect = document.getElementById('emoji-pack');
const shareTemplateInput = document.getElementById('share-template');

// Load saved settings
chrome.storage.sync.get({
  defaultClient: '',
  oneClick: false,
  customCommand: '',
  emojiPack: 'animals',
  shareTemplate: '',
  nftStats: { total: 0, tiers: {}, history: [] },
}, (data) => {
  clientSelect.value = data.defaultClient;
  oneClickToggle.checked = data.oneClick;
  customCommandInput.value = data.customCommand;
  emojiPackSelect.value = data.emojiPack;
  shareTemplateInput.value = data.shareTemplate;
  updateOneClickState();
  renderStats(data.nftStats);
  renderHistory(data.nftStats.history);
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
  tiersEl.innerHTML = tiers.map(t => {
    const count = stats.tiers[t] || 0;
    if (count === 0) return '';
    const pct = Math.round((count / stats.total) * 100);
    return `<div class="stats-tier-row">
      <span class="stats-tier-dot" style="background:${TIER_COLORS[t]}"></span>
      <span class="stats-tier-name">${t}</span>
      <span class="stats-tier-bar"><span class="stats-tier-fill" style="width:${pct}%;background:${TIER_COLORS[t]}"></span></span>
      <span class="stats-tier-count">${count}</span>
    </div>`;
  }).join('');
}

function renderHistory(history) {
  const el = document.getElementById('share-history');
  if (!history || history.length === 0) {
    el.innerHTML = '<span class="hint" style="margin-left:0">No shares yet</span>';
    return;
  }

  el.innerHTML = history.slice(0, 5).map(h => {
    const ago = timeAgo(h.time);
    return `<div class="history-row">
      <span class="history-emoji">${h.emoji}</span>
      <span class="history-repo">${h.repo}</span>
      <span class="history-tier" style="color:${TIER_COLORS[h.tier]}">${h.tier}</span>
      <span class="history-time">${ago}</span>
    </div>`;
  }).join('');
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
