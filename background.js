// --- Command Execution Router ---

const NM_HOST = 'com.smile.ai_install';

async function executeCommand(msg) {
  const { toolId, command, url } = msg;

  // Cursor → URL scheme
  if (toolId === 'cursor') {
    try {
      const cursorUrl = `cursor://file.url/${encodeURIComponent(url || command)}`;
      await chrome.tabs.create({ url: cursorUrl });
      return { success: true, method: 'cursor-url' };
    } catch (e) {
      return { success: false, error: e.message };
    }
  }

  // VS Code → URL scheme
  if (toolId === 'vscode') {
    try {
      const vscodeUrl = `vscode://vscode.git/clone?url=${encodeURIComponent(url || '')}`;
      await chrome.tabs.create({ url: vscodeUrl });
      return { success: true, method: 'vscode-url' };
    } catch (e) {
      return { success: false, error: e.message };
    }
  }

  // Terminal commands → Native Messaging Host
  if (['terminal', 'claude', 'codex', 'custom'].includes(toolId)) {
    try {
      const prefs = await chrome.storage.sync.get({ terminalApp: 'auto' });
      const result = await new Promise((resolve, reject) => {
        chrome.runtime.sendNativeMessage(
          NM_HOST,
          { command, terminal: prefs.terminalApp },
          (response) => {
            if (chrome.runtime.lastError) {
              reject(new Error(chrome.runtime.lastError.message));
            } else {
              resolve(response);
            }
          }
        );
      });
      if (result.success) {
        return { success: true, method: 'native', app: result.app };
      }
      return { success: false, error: result.error };
    } catch {
      // Native host not installed → fallback to clipboard
      return { success: false, fallback: true };
    }
  }

  return { success: false, fallback: true };
}

// Check if native host is available
async function checkNativeBridge() {
  try {
    const result = await new Promise((resolve, reject) => {
      chrome.runtime.sendNativeMessage(
        NM_HOST,
        { command: '', terminal: 'auto' },
        (response) => {
          if (chrome.runtime.lastError) {
            reject(new Error(chrome.runtime.lastError.message));
          } else {
            resolve(response);
          }
        }
      );
    });
    // Even an error response means the host is reachable
    return true;
  } catch {
    return false;
  }
}

// --- Message Handler ---

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === 'execute') {
    executeCommand(msg).then(sendResponse);
    return true; // async response
  }

  if (msg.action === 'check-bridge') {
    checkNativeBridge().then((connected) => sendResponse({ connected }));
    return true;
  }

  if (msg.action === 'quick-install') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0]?.id) {
        chrome.tabs.sendMessage(tabs[0].id, { action: 'quick-install' });
      }
    });
  }
});

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
