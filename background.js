// --- Keyboard Shortcut Handler ---
chrome.commands.onCommand.addListener((command) => {
  if (command === 'quick-install') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0]?.id) {
        chrome.tabs.sendMessage(tabs[0].id, { action: 'quick-install' });
      }
    });
  }
});

// --- Badge: show last rolled emoji on extension icon ---
chrome.storage.onChanged.addListener((changes) => {
  if (changes.nftStats?.newValue) {
    const history = changes.nftStats.newValue.history;
    if (history && history.length > 0) {
      const lastEmoji = history[0].emoji;
      chrome.action.setBadgeText({ text: lastEmoji });
      chrome.action.setBadgeBackgroundColor({ color: '#6d28d9' });
    }
  }
});

// Set badge on startup from saved stats
chrome.runtime.onStartup.addListener(() => {
  chrome.storage.sync.get({ nftStats: { history: [] } }, (data) => {
    if (data.nftStats.history.length > 0) {
      chrome.action.setBadgeText({ text: data.nftStats.history[0].emoji });
      chrome.action.setBadgeBackgroundColor({ color: '#6d28d9' });
    }
  });
});

// Also set on install/update
chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get({ nftStats: { history: [] } }, (data) => {
    if (data.nftStats.history.length > 0) {
      chrome.action.setBadgeText({ text: data.nftStats.history[0].emoji });
      chrome.action.setBadgeBackgroundColor({ color: '#6d28d9' });
    }
  });
});
