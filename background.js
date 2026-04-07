// --- AI Proxy ---

const PROXY_URL = 'https://vercel-nu-wheat.vercel.app/api/chat';

const AI_MODELS = {
  haiku: { id: 'claude-haiku-4-5-20251001', label: 'Haiku (fast)', requiresKey: false },
  sonnet: { id: 'claude-sonnet-4-5-20241022', label: 'Sonnet (deep)', requiresKey: true },
  opus: { id: 'claude-opus-4-0-20250514', label: 'Opus (max)', requiresKey: true },
};

async function callAI({ messages, system, max_tokens = 512, model = 'haiku' }) {
  const { claudeApiKey } = await chrome.storage.sync.get({ claudeApiKey: '' });
  const modelConfig = AI_MODELS[model] || AI_MODELS.haiku;

  // Premium models require user's own key
  if (modelConfig.requiresKey) {
    if (!claudeApiKey) {
      return { error: `${modelConfig.label} requires your own Claude API key. Add it in extension settings.` };
    }
    return callDirectAPI({ messages, system, max_tokens, model: modelConfig.id, apiKey: claudeApiKey });
  }

  // Free tier (Haiku) → proxy first, then user key fallback
  try {
    const proxyBody = { messages, max_tokens };
    if (system) proxyBody.system = system;

    const resp = await fetch(PROXY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(proxyBody),
    });

    if (resp.ok) {
      const data = await resp.json();
      if (data.content) return { text: data.content, model: 'haiku' };
      if (data.error) throw new Error(data.error);
    }

    if (resp.status === 429) {
      if (!claudeApiKey) {
        return { error: 'Rate limit reached. Add your Claude API key in settings for unlimited use.' };
      }
    } else {
      throw new Error(`Proxy error: ${resp.status}`);
    }
  } catch {
    if (!claudeApiKey) {
      return { error: 'AI service unavailable. Add your Claude API key in settings as backup.' };
    }
  }

  return callDirectAPI({ messages, system, max_tokens, model: modelConfig.id, apiKey: claudeApiKey });
}

async function callDirectAPI({ messages, system, max_tokens, model, apiKey }) {
  try {
    const apiBody = { model, max_tokens, messages };
    if (system) apiBody.system = system;

    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify(apiBody),
    });

    const data = await resp.json();
    if (data.content && data.content[0]) {
      return { text: data.content[0].text, model };
    }
    return { error: data.error?.message || 'API error' };
  } catch (err) {
    return { error: err.message };
  }
}

// --- Command Execution Router ---

const NM_HOST = 'com.smile.ai_install';

async function executeCommand(msg) {
  const { toolId, command, url } = msg;

  // All commands → Native Messaging Host (terminal execution)
  if (['cursor', 'vscode', 'terminal', 'claude', 'codex', 'custom'].includes(toolId)) {
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

  if (msg.action === 'summarize') {
    (async () => {
      const result = await callAI({
        messages: [{
          role: 'user',
          content: `Summarize "${msg.repoName}" in exactly 3 short lines. Format:\n🎯 [What it does — one sentence]\n⚡ [Key feature or tech — one sentence]\n🚀 [How to start — one sentence]\n\nNo headers, no markdown, no extra text. Plain text only.\n\nREADME:\n${msg.readmeText}`,
        }],
        max_tokens: 150,
      });
      if (result.text) {
        sendResponse({ summary: result.text });
      } else {
        sendResponse({ error: result.error });
      }
    })();
    return true;
  }

  if (msg.action === 'chat') {
    (async () => {
      const systemPrompt = `You're a friendly dev assistant who knows the repo "${msg.repoName}" (stack: ${msg.stacks?.join(', ') || 'unknown'}). You've read the README below. Answer in 2-4 sentences, be direct. You CAN share opinions, assessments, and recommendations when asked. Use the README as primary context but feel free to add your dev expertise. Reply in the same language the user writes in.\n\nREADME:\n${msg.readmeText || 'No README available.'}`;

      const result = await callAI({
        messages: msg.messages,
        system: systemPrompt,
        max_tokens: 300,
        model: msg.model || 'haiku',
      });
      if (result.text) {
        sendResponse({ reply: result.text, model: result.model });
      } else {
        sendResponse({ error: result.error });
      }
    })();
    return true;
  }

  if (msg.action === 'get-models') {
    (async () => {
      const { claudeApiKey } = await chrome.storage.sync.get({ claudeApiKey: '' });
      const models = Object.entries(AI_MODELS).map(([key, cfg]) => ({
        id: key,
        label: cfg.label,
        available: !cfg.requiresKey || !!claudeApiKey,
        requiresKey: cfg.requiresKey,
      }));
      sendResponse({ models });
    })();
    return true;
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
