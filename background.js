// --- AI Proxy ---

const PROXY_URL = 'https://vercel-nu-wheat.vercel.app/api/chat';

// --- Installation ID (unique per install, used for rate limiting) ---

async function getInstallationId() {
  const data = await chrome.storage.local.get({ installationId: '' });
  if (data.installationId) return data.installationId;
  const id = crypto.randomUUID();
  await chrome.storage.local.set({ installationId: id });
  return id;
}

// --- Analytics (serialized to prevent race conditions) ---

let statsQueue = Promise.resolve();

function withStats(fn) {
  statsQueue = statsQueue.then(async () => {
    const data = await chrome.storage.sync.get({ smileStats: { summaries: 0, chats: 0, installs: 0, repos: [] } });
    const stats = data.smileStats;
    const changed = fn(stats);
    if (changed) await chrome.storage.sync.set({ smileStats: stats });
  }).catch(() => {});
}

function incrementStat(key) {
  withStats((stats) => {
    stats[key] = (stats[key] || 0) + 1;
    return true;
  });
}

function trackEvent(action, extras = {}) {
  fetch('https://smile-ai-proxy.thegreatgatsby456.workers.dev/event', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...extras }),
  }).catch(() => {});
}

function trackRepo(owner, repo) {
  const slug = `${owner}/${repo}`;
  withStats((stats) => {
    if (!stats.repos.includes(slug)) {
      stats.repos.push(slug);
      if (stats.repos.length > 100) stats.repos = stats.repos.slice(-100);
      return true;
    }
    return false;
  });
}

const AI_MODELS = {
  haiku: { id: 'claude-haiku-4-5-20251001', label: 'Haiku (fast)', requiresKey: false },
  sonnet: { id: 'claude-sonnet-4-5-20241022', label: 'Sonnet (deep)', requiresKey: true },
  opus: { id: 'claude-opus-4-0-20250514', label: 'Opus (max)', requiresKey: true },
};

async function callAI({ messages, system, max_tokens = 512, model = 'haiku' }) {
  // API key stored locally only (not synced across devices for security)
  const { claudeApiKey } = await chrome.storage.local.get({ claudeApiKey: '' });
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

    const installId = await getInstallationId();
    const resp = await fetch(PROXY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-installation-id': installId,
      },
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

function fallbackRepoAnswer({ question, repoName, repoContext }) {
  const cleanContext = (repoContext || '')
    .replace(/â€”/g, '-')
    .replace(/â€“/g, '-')
    .replace(/â€™/g, "'")
    .replace(/â€œ|â€/g, '"')
    .replace(/Â/g, '')
    .replace(/�/g, '')
    .replace(/[^\S\r\n]+/g, ' ')
    .trim();
  const lower = `${question || ''}`.toLowerCase();
  const fieldNames = [
    'About', 'Topics', 'Stars', 'Forks', 'License', 'Primary language',
    'Detected stack', 'Root files', 'Files in root', 'Languages', 'README',
  ];

  function escapeRegex(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function getField(name) {
    const others = fieldNames.filter((field) => field !== name).map(escapeRegex).join('|');
    const pattern = new RegExp(`${escapeRegex(name)}:\\s*([\\s\\S]*?)(?=\\n(?:${others}):|$)`, 'i');
    return cleanContext.match(pattern)?.[1]?.trim() || '';
  }

  const about = getField('About');
  const topics = getField('Topics');
  const language = getField('Primary language') || getField('Detected stack');
  const languages = getField('Languages');
  const rootFiles = getField('Root files') || getField('Files in root');
  const readme = getField('README');

  function byWords(text, limit = 260) {
    if (!text) return '';
    const normalized = text.replace(/\s+/g, ' ').trim();
    if (normalized.length <= limit) return normalized;
    const clipped = normalized.slice(0, limit);
    return `${clipped.slice(0, Math.max(0, clipped.lastIndexOf(' '))).trim()}...`;
  }

  function friendlyTopics(text) {
    if (!text) return '';
    return text
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean)
      .slice(0, 5)
      .join(', ');
  }

  function cleanMarkdownLine(line) {
    return line
      .replace(/!\[[^\]]*]\([^)]+\)/g, '')
      .replace(/\[([^\]]+)]\([^)]+\)/g, '$1')
      .replace(/^#{1,6}\s*/, '')
      .replace(/^[-*]\s*/, '')
      .replace(/[`*_<>]/g, '')
      .trim();
  }

  function readmeTitle(text) {
    return text.match(/^#\s+(.+)$/m)?.[1]?.trim() || '';
  }

  function readmeLead(text) {
    if (!text) return '';
    const title = readmeTitle(text).toLowerCase();
    const lines = text
      .split(/\n+/)
      .map(cleanMarkdownLine)
      .filter((line) => {
        const normalized = line.toLowerCase();
        return line.length > 24
          && normalized !== title
          && !normalized.startsWith('http')
          && !normalized.includes('badge')
          && !line.startsWith('|');
      });
    return lines[0] || byWords(cleanMarkdownLine(text), 260);
  }

  function inferComponents(filesText) {
    const files = filesText.toLowerCase();
    const components = [];
    if (/(manifest\.json|content\.js|background\.js|popup\.html)/.test(files)) {
      components.push('Chrome extension: page detector, repo chat UI, popup settings, and background worker.');
    }
    if (files.includes('native-host')) {
      components.push('Native bridge: local helper that lets the extension send approved commands to the computer.');
    }
    if (files.includes('macos-companion')) {
      components.push('macOS companion: menu-bar app wrapper for installing and checking the local bridge.');
    }
    if (/(index\.html|privacy-policy\.html|assets|store)/.test(files)) {
      components.push('Download website: landing page, assets, screenshots, and packaged prototype.');
    }
    if (files.includes('scripts')) {
      components.push('Build scripts: packaging flow for the downloadable prototype zip.');
    }
    return components.slice(0, 5);
  }

  const isRussian = /[а-яё]/i.test(question || '');
  const repoPurpose = about || readmeLead(readme) || 'No GitHub description or README summary was found in the captured page context.';
  const components = inferComponents(rootFiles);
  const wantsInstall = lower.includes('install') || lower.includes('setup') || lower.includes('run') || lower.includes('download');
  const wantsStack = lower.includes('stack') || lower.includes('tech') || lower.includes('language');
  const wantsCompanion = lower.includes('companion') || lower.includes('desktop') || lower.includes('krisp') || lower.includes('superwhisper');
  const lines = [];

  if (isRussian) {
    lines.push(`🎯 **Описание репозитория**\n**${repoName}** - ${byWords(repoPurpose, 280)}`);
  } else {
    lines.push(`🎯 **Repository description**\n**${repoName}** - ${byWords(repoPurpose, 280)}`);
  }

  if (components.length) {
    lines.push(`${isRussian ? '📦 **Что внутри**' : '📦 **What is inside**'}\n${components.map((item) => `• ${item}`).join('\n')}`);
  }

  if (wantsInstall) {
    lines.push(`${isRussian ? '🚀 **Как запустить**' : '🚀 **How to use it**'}\n• Open a GitHub/GitLab/Bitbucket repo.\n• Click **Ask your GIT**.\n• Ask about the repo, then choose **Claude Code**, **Cursor**, or **Codex** from the install menu.`);
  } else if (wantsStack) {
    lines.push(`${isRussian ? '⚡ **Стек**' : '⚡ **Stack**'}\n• ${byWords(languages || language || 'No language breakdown was found in the captured context.', 220)}`);
  } else if (wantsCompanion) {
    lines.push(`${isRussian ? '🖥️ **Desktop companion**' : '🖥️ **Desktop companion**'}\nThe companion is the local helper layer: install it once, then the browser extension can talk to your computer for approved install commands.`);
  } else {
    lines.push(`${isRussian ? '🧭 **Коротко**' : '🧭 **In short**'}\nThis repo is meant to turn a repository page into an actionable developer brief: summary, follow-up chat, and handoff to local coding tools.`);
  }

  const evidence = [];
  if (friendlyTopics(topics)) evidence.push(`${isRussian ? 'Topics' : 'Repo tags'}: ${friendlyTopics(topics)}`);
  if (language || languages) evidence.push(`${isRussian ? 'Языки' : 'Languages'}: ${byWords(languages || language, 150)}`);
  if (rootFiles) evidence.push(`${isRussian ? 'Root files' : 'Root files'}: ${byWords(rootFiles, 180)}`);
  if (readme && readmeLead(readme) && readmeLead(readme) !== repoPurpose) {
    evidence.push(`README: ${byWords(readmeLead(readme), 170)}`);
  }
  if (evidence.length) {
    lines.push(`${isRussian ? '📌 **Сигналы со страницы**' : '📌 **Signals from the page**'}\n${evidence.slice(0, 4).map((item) => `• ${item}`).join('\n')}`);
  }

  lines.push(isRussian
    ? '⚙️ **Offline demo mode:** AI API недоступен или ключ не задан, поэтому ответ собран локально из контекста страницы.'
    : '⚙️ **Offline demo mode:** AI API is unavailable or no key is set, so this answer is generated locally from the repo page context.');
  return lines.join('\n\n');
}

// --- Command Execution Router ---

const NM_HOST = 'com.smile.ai_install';

async function executeCommand(msg) {
  const { toolId, command, url, mode } = msg;

  // All commands → Native Messaging Host (terminal execution)
  if (['cursor', 'vscode', 'terminal', 'claude', 'codex'].includes(toolId) || toolId.startsWith('tool_')) {
    try {
      const prefs = await chrome.storage.sync.get({ terminalApp: 'auto' });
      const nativeMsg = { command, terminal: prefs.terminalApp };
      if (mode) nativeMsg.mode = mode;
      const result = await new Promise((resolve, reject) => {
        chrome.runtime.sendNativeMessage(
          NM_HOST,
          nativeMsg,
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
        { type: 'ping', terminal: 'auto' },
        (response) => {
          if (chrome.runtime.lastError) {
            reject(new Error(chrome.runtime.lastError.message));
          } else {
            resolve(response);
          }
        }
      );
    });
    // Even older hosts may return an error response; a response means reachable.
    return {
      connected: true,
      app: result?.app || 'Ask your GIT Companion',
      version: result?.version || 'unknown',
    };
  } catch {
    return { connected: false };
  }
}

// --- GitHub API (runs in background where host_permissions apply) ---

async function fetchGitHubRepoContext(owner, repo) {
  const base = `https://api.github.com/repos/${owner}/${repo}`;
  const headers = { Accept: 'application/vnd.github.v3+json' };

  const [repoResp, contentsResp, readmeResp, langsResp] = await Promise.allSettled([
    fetch(base, { headers }),
    fetch(`${base}/contents/`, { headers }),
    fetch(`${base}/readme`, { headers }),
    fetch(`${base}/languages`, { headers }),
  ]);

  if (repoResp.status === 'fulfilled' && repoResp.value.status === 403) {
    return null; // rate limited
  }

  const parts = [];

  if (repoResp.status === 'fulfilled' && repoResp.value.ok) {
    const r = await repoResp.value.json();
    if (r.description) parts.push(`About: ${r.description}`);
    if (r.topics?.length) parts.push(`Topics: ${r.topics.join(', ')}`);
    parts.push(`Stars: ${r.stargazers_count}, Forks: ${r.forks_count}`);
    if (r.license?.spdx_id) parts.push(`License: ${r.license.spdx_id}`);
    if (r.language) parts.push(`Primary language: ${r.language}`);
  }

  if (contentsResp.status === 'fulfilled' && contentsResp.value.ok) {
    const files = await contentsResp.value.json();
    if (Array.isArray(files)) {
      const tree = files.map(f => `${f.type === 'dir' ? '/' : ''}${f.name}`).join(', ');
      parts.push(`Root files: ${tree}`);
    }
  }

  if (langsResp.status === 'fulfilled' && langsResp.value.ok) {
    const langs = await langsResp.value.json();
    const total = Object.values(langs).reduce((a, b) => a + b, 0);
    if (total > 0) {
      const breakdown = Object.entries(langs)
        .map(([lang, bytes]) => `${lang} ${Math.round(bytes / total * 100)}%`)
        .join(', ');
      parts.push(`Languages: ${breakdown}`);
    }
  }

  if (readmeResp.status === 'fulfilled' && readmeResp.value.ok) {
    const readme = await readmeResp.value.json();
    if (readme.content) {
      try {
        const text = atob(readme.content).slice(0, 4000);
        parts.push(`README:\n${text}`);
      } catch { /* base64 decode failed */ }
    }
  }

  return parts.length > 0 ? parts.join('\n') : null;
}

// --- Message Handler ---

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === 'fetch-repo-context') {
    fetchGitHubRepoContext(msg.owner, msg.repo).then((context) => {
      sendResponse({ context });
    }).catch(() => {
      sendResponse({ context: null });
    });
    return true;
  }

  if (msg.action === 'track-install') {
    incrementStat('installs');
    trackEvent('install', msg.tool ? { tool: msg.tool } : {});
    return;
  }

  if (msg.action === 'execute') {
    executeCommand(msg).then((result) => {
      if (result && result.success) incrementStat('installs');
      sendResponse(result);
    });
    return true; // async response
  }

  if (msg.action === 'summarize') {
    (async () => {
      if (msg.repoName) {
        const [owner, repo] = msg.repoName.split('/');
        if (owner && repo) trackRepo(owner, repo);
      }
      const lang = msg.userLang || 'en';
      const langHint = lang.startsWith('en') ? '' : `\n\nIMPORTANT: Reply in the language with code "${lang}". Do NOT reply in English.`;
      const result = await callAI({
        messages: [{
          role: 'user',
          content: `Summarize "${msg.repoName}" in exactly 3 short lines. Format:\n🎯 [What it does — one sentence]\n⚡ [Key feature or tech — one sentence]\n🚀 [How to start — one sentence]\n\nNo headers, no markdown, no extra text. Plain text only.${langHint}\n\nREADME:\n${msg.readmeText}`,
        }],
        max_tokens: 150,
      });
      if (result.text) {
        incrementStat('summaries');
        trackEvent('summary');
        sendResponse({ summary: result.text });
      } else {
        sendResponse({ error: result.error });
      }
    })();
    return true;
  }

  if (msg.action === 'chat') {
    (async () => {
      const systemPrompt = `You're a friendly dev assistant who knows the repo "${msg.repoName}". You've analyzed the repo page: file tree, README, about, topics, languages, stats. Answer in 2-5 sentences, be direct. You CAN share opinions, assessments, and recommendations when asked. Use the repo context as primary source but add your dev expertise. Reply in the same language the user writes in.\n\nFormatting rules:\n- Use emoji headers for sections (🎯, ⚡, 📦, 🔧, etc.)\n- Separate topics with blank lines\n- Use **bold** for key terms\n- Keep it scannable — short paragraphs, not walls of text\n\nRepo context:\n${msg.readmeText || 'No repo info available.'}`;

      const result = await callAI({
        messages: msg.messages,
        system: systemPrompt,
        max_tokens: 600,
        model: msg.model || 'haiku',
      });
      if (result.text) {
        incrementStat('chats');
        trackEvent('chat');
        sendResponse({ reply: result.text, model: result.model });
      } else {
        const lastUserMessage = [...(msg.messages || [])].reverse().find((m) => m.role === 'user');
        sendResponse({
          reply: fallbackRepoAnswer({
            question: lastUserMessage?.content || '',
            repoName: msg.repoName,
            repoContext: msg.readmeText,
          }),
          model: 'offline-prototype',
        });
      }
    })();
    return true;
  }

  if (msg.action === 'get-models') {
    (async () => {
      const { claudeApiKey } = await chrome.storage.local.get({ claudeApiKey: '' });
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
    checkNativeBridge().then((status) => sendResponse(status));
    return true;
  }

  if (msg.action === 'open-popup') {
    chrome.action.openPopup();
    return;
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


// On install/update: migrate API key from sync→local, generate installation ID
chrome.runtime.onInstalled.addListener(async () => {
  // Migrate API key from sync to local (one-time)
  const syncData = await chrome.storage.sync.get({ claudeApiKey: '' });
  if (syncData.claudeApiKey) {
    await chrome.storage.local.set({ claudeApiKey: syncData.claudeApiKey });
    await chrome.storage.sync.remove('claudeApiKey');
  }
  // Ensure installation ID exists
  await getInstallationId();
});
