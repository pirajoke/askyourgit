(() => {
  const BUTTON_ID = 'ai-install-btn';
  const DROPDOWN_ID = 'ai-install-dropdown';

  // --- Platform Detection ---

  function detectPlatform() {
    const host = window.location.hostname;
    if (host === 'github.com') return 'github';
    if (host === 'gitlab.com') return 'gitlab';
    if (host === 'bitbucket.org') return 'bitbucket';
    return null;
  }

  function getRepoInfo() {
    const platform = detectPlatform();
    if (!platform) return null;

    const match = window.location.pathname.match(/^\/([^/]+)\/([^/]+)/);
    if (!match) return null;
    const [, owner, repo] = match;

    const reserved = {
      github: [
        'settings', 'marketplace', 'explore', 'notifications', 'new',
        'login', 'signup', 'organizations', 'orgs', 'features', 'pricing',
        'sponsors', 'topics', 'trending', 'collections', 'events', 'about',
        'security', 'customer-stories',
      ],
      gitlab: ['explore', 'help', 'admin', 'dashboard', 'users', 'groups'],
      bitbucket: ['account', 'repo', 'dashboard', 'product'],
    };
    if ((reserved[platform] || []).includes(owner)) return null;

    const cleanRepo = repo.replace(/\.git$/, '');
    const url = `https://${window.location.hostname}/${owner}/${cleanRepo}`;

    return { owner, repo: cleanRepo, url, platform };
  }

  // --- GitHub API Context (via background script) ---

  async function fetchRepoContextAPI(owner, repo) {
    const cacheKey = `ghapi_${owner}_${repo}`;
    const cached = await new Promise(r => chrome.storage.local.get([cacheKey], r));
    if (cached[cacheKey] && (Date.now() - cached[cacheKey].ts < 3600000)) {
      return cached[cacheKey].data;
    }

    try {
      const response = await new Promise((resolve) => {
        chrome.runtime.sendMessage({ action: 'fetch-repo-context', owner, repo }, resolve);
      });
      if (response?.context) {
        chrome.storage.local.set({ [cacheKey]: { data: response.context, ts: Date.now() } });
        return response.context;
      }
      return null;
    } catch {
      return null;
    }
  }

  // --- Stack Detection ---

  function detectStack() {
    const stacks = [];
    const fileElements = document.querySelectorAll(
      '[role="rowheader"] a, .js-navigation-open, .react-directory-row a, ' +
      '.tree-item-file-name a, .file-name a, ' +
      'td.filename a, [data-qa="file-name"] a'
    );

    const fileNames = new Set();
    fileElements.forEach(el => {
      const name = el.textContent.trim();
      if (name) fileNames.add(name);
    });

    if (fileNames.has('package.json')) {
      stacks.push('Node.js');
      if (fileNames.has('tsconfig.json')) stacks.push('TypeScript');
      if (fileNames.has('next.config.js') || fileNames.has('next.config.mjs') || fileNames.has('next.config.ts')) stacks.push('Next.js');
    }
    if (fileNames.has('requirements.txt') || fileNames.has('pyproject.toml') || fileNames.has('setup.py') || fileNames.has('Pipfile')) {
      stacks.push('Python');
    }
    if (fileNames.has('Cargo.toml')) stacks.push('Rust');
    if (fileNames.has('go.mod')) stacks.push('Go');
    if (fileNames.has('Gemfile')) stacks.push('Ruby');
    if (fileNames.has('build.gradle') || fileNames.has('pom.xml')) stacks.push('Java');

    const hasDocker = fileNames.has('Dockerfile') || fileNames.has('docker-compose.yml') || fileNames.has('docker-compose.yaml');

    return { stacks, hasDocker };
  }

  // --- Trust Info (GitHub only) ---

  function parseTrustInfo(platform) {
    if (platform !== 'github') return null;

    const info = {};

    const starLink = document.querySelector('a[href$="/stargazers"]');
    if (starLink) {
      const text = starLink.textContent.replace(/[^\d.k]/gi, '').trim();
      if (text) info.stars = text;
    }

    const licenseLink = document.querySelector('a[data-analytics-event*="LICENSE"], a[href*="/blob/"][href*="LICENSE"]');
    if (licenseLink) {
      const text = licenseLink.textContent.trim();
      if (text && text !== 'View license') info.license = text;
    }
    if (!info.license) {
      const sidebarItems = document.querySelectorAll('.BorderGrid-cell');
      sidebarItems.forEach(cell => {
        const text = cell.textContent;
        if (text.includes('License') || text.includes('license')) {
          const match = text.match(/(MIT|Apache|GPL|BSD|ISC|MPL|LGPL|AGPL|Unlicense)[^\n]*/i);
          if (match) info.license = match[0].trim();
        }
      });
    }

    const timeEl = document.querySelector('relative-time');
    if (timeEl) {
      info.lastCommit = timeEl.getAttribute('datetime')
        ? timeEl.textContent.trim()
        : null;
    }

    return (info.stars || info.license || info.lastCommit) ? info : null;
  }

  // --- Commands ---

  function getCommands(repoInfo, stackInfo, customCommand) {
    const { url, repo, owner } = repoInfo;
    const { stacks, hasDocker } = stackInfo;

    const stackLabel = stacks.length > 0 ? ` (${stacks.join(' + ')} project)` : '';
    const dockerNote = hasDocker ? ' (Docker available)' : '';
    const setupHint = stacks.includes('Python') ? ', create venv if needed' : '';

    let terminalExtra = '';
    if (stacks.includes('Node.js')) terminalExtra = ' && npm install';
    else if (stacks.includes('Python')) terminalExtra = ' && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt 2>/dev/null; pip install -e . 2>/dev/null';
    else if (stacks.includes('Rust')) terminalExtra = ' && cargo build';
    else if (stacks.includes('Go')) terminalExtra = ' && go build ./...';

    const commands = [
      {
        id: 'claude',
        label: 'Claude Code',
        icon: '🤖',
        command: `claude "clone ${url}${stackLabel} and set it up following the README${setupHint}${dockerNote}"`,
      },
      {
        id: 'cursor',
        label: 'Cursor',
        icon: '▶️',
        command: `git clone ${url} && cd ${repo}${terminalExtra}`,
        openUrl: `cursor://vscode.git/clone?url=${encodeURIComponent(url + '.git')}`,
      },
      {
        id: 'terminal',
        label: 'Terminal + Claude',
        icon: '💻',
        command: `git clone ${url} && cd ${repo}${terminalExtra} && claude "set up this project"`,
      },
      {
        id: 'codex',
        label: 'Codex CLI',
        icon: '🧠',
        command: `codex "clone ${url} and set it up"`,
      },
    ];

    if (customCommand) {
      const rendered = customCommand
        .replace(/\{url\}/g, url)
        .replace(/\{owner\}/g, owner)
        .replace(/\{repo\}/g, repo)
        .replace(/\{stack\}/g, stacks.join(', ') || 'unknown');
      commands.push({
        id: 'custom',
        label: 'Custom',
        icon: '⚙️',
        command: rendered,
      });
    }

    return commands;
  }

  // --- NFT Emoji Share ---

  const EMOJI_PACKS = {
    animals: {
      label: 'Animals',
      tiers: {
        common:    ['🐱', '🐶', '🐸', '🐧', '🐝', '🦊', '🐻', '🐨', '🐼', '🐵'],
        rare:      ['🦄', '🐉', '🦩', '🦈', '🦅', '🐙', '🦜', '🐺'],
        epic:      ['🦖', '🐋', '🦁', '🦎', '🐲', '🦧'],
        legendary: ['🐺', '🦤', '🐚', '🪼'],
      },
    },
    space: {
      label: 'Space',
      tiers: {
        common:    ['⭐', '🌙', '☀️', '🌍', '🪨', '💫', '🌤️', '⚡', '🔥', '💧'],
        rare:      ['🪐', '☄️', '🌌', '🌑', '🛰️', '🔭', '🌠', '🌊'],
        epic:      ['🛸', '🌋', '🧊', '🌪️', '🕳️', '💥'],
        legendary: ['🪬', '⚛️', '🫧', '🌀'],
      },
    },
    food: {
      label: 'Food',
      tiers: {
        common:    ['🍕', '🍔', '🌮', '🍜', '🍩', '🧁', '🍪', '🍿', '🥐', '🍣'],
        rare:      ['🍱', '🥘', '🫕', '🍰', '🎂', '🍫', '🧇', '🥮'],
        epic:      ['🍾', '🫖', '🍝', '🦪', '🥩', '🫔'],
        legendary: ['🏺', '🫗', '🧉', '🪺'],
      },
    },
    objects: {
      label: 'Objects',
      tiers: {
        common:    ['🎸', '🎮', '📱', '💡', '🔑', '🎯', '🧲', '🔔', '📦', '🎁'],
        rare:      ['🔮', '🎭', '🏹', '⚔️', '🛡️', '🎪', '🧿', '🪄'],
        epic:      ['⚗️', '🗿', '🧬', '💎', '🪩', '🔱'],
        legendary: ['👑', '💀', '🏆', '🪦'],
      },
    },
  };

  const TIER_CONFIG = {
    common:    { odds: 0.60, label: 'Common' },
    rare:      { odds: 0.25, label: 'Rare' },
    epic:      { odds: 0.10, label: 'Epic' },
    legendary: { odds: 0.05, label: 'Legendary' },
  };

  function rollEmoji(packName) {
    const pack = EMOJI_PACKS[packName] || EMOJI_PACKS.animals;
    const roll = Math.random();
    let cumulative = 0;
    for (const [tier, config] of Object.entries(TIER_CONFIG)) {
      cumulative += config.odds;
      if (roll < cumulative) {
        const emojis = pack.tiers[tier];
        const emoji = emojis[Math.floor(Math.random() * emojis.length)];
        return { emoji, tier, label: config.label };
      }
    }
    const fb = pack.tiers.common;
    return { emoji: fb[0], tier: 'common', label: 'Common' };
  }

  // --- NFT Stats ---

  function recordRoll(nft, repoUrl) {
    chrome.storage.sync.get({ nftStats: { total: 0, tiers: {}, history: [] } }, (data) => {
      const stats = data.nftStats;
      stats.total++;
      stats.tiers[nft.tier] = (stats.tiers[nft.tier] || 0) + 1;

      // Keep last 10 shares
      stats.history.unshift({
        emoji: nft.emoji,
        tier: nft.tier,
        repo: repoUrl.replace(/^https?:\/\/[^/]+\//, ''),
        time: Date.now(),
      });
      if (stats.history.length > 10) stats.history.length = 10;

      chrome.storage.sync.set({ nftStats: stats });
    });
  }

  // --- Share ---

  async function copyEmojiShare(emoji, url, shareTemplate) {
    const shortUrl = url.replace(/^https?:\/\/[^/]+\//, '');
    let plain;
    if (shareTemplate) {
      plain = shareTemplate
        .replace(/\{emoji\}/g, emoji)
        .replace(/\{url\}/g, shortUrl)
        .replace(/\{fullurl\}/g, url)
        .replace(/\{repo\}/g, url.split('/').slice(-1)[0]);
    } else {
      plain = `${emoji} ${shortUrl}`;
    }
    const html = `<a href="${url}">${emoji}</a> <a href="${url}">${shortUrl}</a>`;
    try {
      await navigator.clipboard.write([
        new ClipboardItem({
          'text/html': new Blob([html], { type: 'text/html' }),
          'text/plain': new Blob([plain], { type: 'text/plain' }),
        }),
      ]);
      return true;
    } catch {
      return copyToClipboard(plain);
    }
  }

  // --- README Badge Detection ---

  function detectSmileBadge() {
    // Check if README contains an "Install with AI" badge
    const readme = document.querySelector('#readme, [data-testid="readme"], .readme-content');
    if (!readme) return false;
    const html = readme.innerHTML;
    return html.includes('Install_with-AI') || html.includes('Install with AI') || html.includes('ai-install');
  }

  // --- Clipboard ---

  async function copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      return ok;
    }
  }

  function showFeedback(btn, text) {
    const original = btn.innerHTML;
    btn.innerHTML = `<span class="ai-install-icon">✓</span> ${text || 'Copied!'}`;
    btn.classList.add('ai-install-copied');
    setTimeout(() => {
      btn.innerHTML = original;
      btn.classList.remove('ai-install-copied');
    }, 1500);
  }

  function showCopiedFeedback(btn) {
    showFeedback(btn, 'Copied!');
  }

  function showSharePicker(shareItem, nft, repoUrl, shareTemplate) {
    // Remove existing picker
    const oldPicker = shareItem.parentElement?.querySelector('.ai-install-share-picker');
    if (oldPicker) oldPicker.remove();

    const targets = [
      { icon: '✈️', label: 'Telegram', url: `https://t.me/share/url?url=${encodeURIComponent(repoUrl)}&text=${encodeURIComponent(nft.emoji)}` },
      { icon: '💬', label: 'WhatsApp', url: `https://wa.me/?text=${encodeURIComponent(nft.emoji + ' ' + repoUrl)}` },
      { icon: '𝕏', label: 'Twitter', url: `https://x.com/intent/tweet?text=${encodeURIComponent(nft.emoji + ' ' + repoUrl)}` },
      { icon: '📋', label: 'Copy', action: 'copy' },
    ];

    const picker = document.createElement('div');
    picker.className = 'ai-install-share-picker';

    for (const t of targets) {
      const btn = document.createElement('button');
      btn.className = 'ai-install-share-btn';
      btn.title = t.label;
      btn.innerHTML = `<span>${t.icon}</span>`;
      btn.addEventListener('click', async (e) => {
        e.stopPropagation();
        if (t.action === 'copy') {
          await copyEmojiShare(nft.emoji, repoUrl, shareTemplate);
          btn.innerHTML = '<span>✓</span>';
          setTimeout(() => closeDropdown(), 600);
        } else {
          window.open(t.url, '_blank');
          closeDropdown();
        }
      });
      picker.appendChild(btn);
    }

    // Insert right after the share button
    shareItem.insertAdjacentElement('afterend', picker);
  }

  // --- Execute via Background ---

  async function executeOrCopy(toolId, command, url, btn, openUrl) {
    // If tool has a direct URL scheme (e.g. Cursor), open it directly
    if (openUrl) {
      window.open(openUrl, '_self');
      showFeedback(btn, 'Opening...');
      chrome.runtime.sendMessage({ action: 'track-install' });
      return;
    }
    // Try to auto-execute via native host
    if (toolId) {
      try {
        const result = await chrome.runtime.sendMessage({
          action: 'execute',
          toolId,
          command,
          url,
        });
        if (result && result.success) {
          const label = result.app ? `Sent to ${result.app}` : 'Opened';
          showFeedback(btn, `${label} ✓`);
          return; // already tracked in background.js
        }
      } catch {
        // native host not available — fall through to copy
      }
    }
    // Fallback → copy to clipboard
    await copyToClipboard(command);
    showCopiedFeedback(btn);
    chrome.runtime.sendMessage({ action: 'track-install' });
  }

  // --- Confirm Modal ---

  function showInstallConfirm(repoName, toolLabel, toolIcon) {
    return new Promise((resolve) => {
      const overlay = document.createElement('div');
      overlay.className = 'ai-install-confirm-overlay';

      const modal = document.createElement('div');
      modal.className = 'ai-install-confirm-modal';

      const iconEl = document.createElement('div');
      iconEl.className = 'ai-install-confirm-icon';
      iconEl.textContent = toolIcon;

      const titleEl = document.createElement('div');
      titleEl.className = 'ai-install-confirm-title';
      titleEl.textContent = `Install with ${toolLabel}?`;

      const repoEl = document.createElement('div');
      repoEl.className = 'ai-install-confirm-repo';
      repoEl.textContent = repoName;

      const actions = document.createElement('div');
      actions.className = 'ai-install-confirm-actions';

      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'ai-install-confirm-btn ai-install-confirm-cancel';
      cancelBtn.textContent = 'Cancel';

      const okBtn = document.createElement('button');
      okBtn.className = 'ai-install-confirm-btn ai-install-confirm-ok';
      okBtn.textContent = '\u26A1 Install';

      actions.append(cancelBtn, okBtn);
      modal.append(iconEl, titleEl, repoEl, actions);

      overlay.appendChild(modal);
      document.body.appendChild(overlay);

      const cleanup = (result) => {
        overlay.classList.add('ai-install-confirm-closing');
        setTimeout(() => { overlay.remove(); resolve(result); }, 150);
      };

      cancelBtn.addEventListener('click', () => cleanup(false));
      okBtn.addEventListener('click', () => cleanup(true));
      overlay.addEventListener('click', (e) => { if (e.target === overlay) cleanup(false); });
    });
  }

  // --- README Extraction ---

  function getReadmeText() {
    const readme = document.querySelector(
      '#readme article, [data-testid="readme"] article, ' +
      '#readme .markdown-body, #readme .Box-body, ' +
      '#readme, [data-testid="readme"], .readme-content, ' +
      '.markdown-body.entry-content'
    );
    if (!readme) return null;
    const clone = readme.cloneNode(true);
    clone.querySelectorAll('nav, img, svg, .anchor, .octicon, .zeroclipboard-container, details').forEach(el => el.remove());
    const text = clone.textContent.replace(/\s+/g, ' ').trim();
    return text ? text.slice(0, 4000) : null;
  }

  // --- Full Repo Context ---

  function getRepoContextDOM(repoInfo, stackInfo) {
    const parts = [];

    // 1. About / description
    const aboutEl = document.querySelector('.f4.my-3, .BorderGrid-cell p, [itemprop="about"]');
    if (aboutEl) {
      const about = aboutEl.textContent.trim();
      if (about) parts.push(`About: ${about}`);
    }

    // 2. Topics / tags
    const topicEls = document.querySelectorAll('.topic-tag, a[data-octo-click="topic_click"], [data-testid="topic"]');
    const topics = [...topicEls].map(el => el.textContent.trim()).filter(Boolean);
    if (topics.length) parts.push(`Topics: ${topics.join(', ')}`);

    // 3. Stack info
    if (stackInfo.stacks.length) parts.push(`Detected stack: ${stackInfo.stacks.join(', ')}`);
    if (stackInfo.hasDocker) parts.push('Has Docker support');

    // 4. File tree from DOM
    const fileEls = document.querySelectorAll(
      '[role="rowheader"] a, .js-navigation-open, .react-directory-row a, ' +
      '.tree-item-file-name a, .file-name a, td.filename a, [data-qa="file-name"] a, ' +
      'a.Link--primary[title]'
    );
    const files = [];
    fileEls.forEach(el => {
      const name = el.textContent.trim();
      if (name && !name.includes(' ') && name.length < 80) files.push(name);
    });
    const uniqueFiles = [...new Set(files)];
    if (uniqueFiles.length) parts.push(`Files in root: ${uniqueFiles.join(', ')}`);

    // 5. Sidebar stats
    const statsItems = document.querySelectorAll('.BorderGrid-cell');
    statsItems.forEach(cell => {
      const text = cell.textContent.trim().replace(/\s+/g, ' ');
      if (text.includes('star')) {
        const m = text.match(/([\d,.kKmM]+)\s*stars?/i);
        if (m) parts.push(`Stars: ${m[1]}`);
      }
      if (text.includes('fork')) {
        const m = text.match(/([\d,.kKmM]+)\s*forks?/i);
        if (m) parts.push(`Forks: ${m[1]}`);
      }
      if (text.includes('License') || text.includes('license')) {
        const m = text.match(/(MIT|Apache|GPL|BSD|ISC|MPL|LGPL|AGPL|Unlicense)[^\n]*/i);
        if (m) parts.push(`License: ${m[0].trim()}`);
      }
    });

    // 6. Languages bar
    const langEls = document.querySelectorAll('[aria-label="Repository languages"] li, .repository-lang-stats-graph span, .Progress + ul li');
    const langs = [];
    langEls.forEach(el => {
      const text = el.textContent.trim().replace(/\s+/g, ' ');
      if (text) langs.push(text);
    });
    if (langs.length) parts.push(`Languages: ${langs.join(', ')}`);

    // 7. README text
    const readmeText = getReadmeText();
    if (readmeText) parts.push(`README:\n${readmeText}`);

    return parts.join('\n') || null;
  }

  async function getRepoContext(repoInfo, stackInfo) {
    // Try GitHub API first (richer data, no DOM fragility)
    if (repoInfo.platform === 'github') {
      const apiContext = await fetchRepoContextAPI(repoInfo.owner, repoInfo.repo);
      if (apiContext) return apiContext;
    }
    // Fallback to DOM scraping
    return getRepoContextDOM(repoInfo, stackInfo);
  }

  // --- Quick Summary ---

  function getBasicSummary(repoInfo, stackInfo) {
    const aboutEl = document.querySelector('.f4.my-3, .BorderGrid-cell p, [itemprop="about"]');
    const about = aboutEl ? aboutEl.textContent.trim() : '';

    const readme = document.querySelector('#readme, [data-testid="readme"], .readme-content');
    let firstPara = '';
    if (readme) {
      const p = readme.querySelector('p');
      if (p) firstPara = p.textContent.trim().slice(0, 200);
    }

    const stacks = stackInfo.stacks.length > 0 ? `Stack: ${stackInfo.stacks.join(', ')}` : '';

    let summary = '';
    if (about) summary += about + '\n\n';
    if (firstPara && firstPara !== about) summary += firstPara + '\n\n';
    if (stacks) summary += stacks;

    return summary.trim() || 'No description available for this repository.';
  }

  function showRepoSummary(dropdown, repoInfo, stackInfo) {
    // Toggle existing panel
    const existing = dropdown.querySelector('.ai-install-summary-panel');
    if (existing) { existing.remove(); return; }

    const panel = document.createElement('div');
    panel.className = 'ai-install-summary-panel';

    const cacheKey = `summary_${repoInfo.owner}_${repoInfo.repo}`;

    // Insert before chat panel if it exists, otherwise append
    const chatPanel = dropdown.querySelector('.ai-install-chat-panel');
    if (chatPanel) {
      dropdown.insertBefore(panel, chatPanel);
    } else {
      dropdown.appendChild(panel);
    }

    // Check cache first
    chrome.storage.local.get([cacheKey], async (data) => {
      const cached = data[cacheKey];
      if (cached && (Date.now() - cached.ts < 24 * 60 * 60 * 1000)) {
        panel.textContent = cached.text;
        return;
      }

      // Show loading
      panel.innerHTML = '';
      const spinner = document.createElement('div');
      spinner.className = 'ai-install-summary-loading';
      spinner.textContent = 'Generating summary...';
      panel.appendChild(spinner);

      const context = await getRepoContext(repoInfo, stackInfo);
      if (!context) {
        panel.textContent = 'No repo info found on this page.';
        return;
      }

      chrome.runtime.sendMessage({
        action: 'summarize',
        readmeText: context,
        repoName: `${repoInfo.owner}/${repoInfo.repo}`,
      }, (response) => {
        if (response && response.summary) {
          panel.textContent = response.summary;
          chrome.storage.local.set({ [cacheKey]: { text: response.summary, ts: Date.now() } });
        } else {
          const basic = getBasicSummary(repoInfo, stackInfo);
          panel.textContent = basic;
          if (response?.error) {
            const hint = document.createElement('div');
            hint.className = 'ai-install-summary-hint';
            hint.textContent = response.error;
            panel.appendChild(hint);
          }
        }
      });
    });
  }

  // --- Repo Chat ---

  function showRepoChat(dropdown, repoInfo, stackInfo) {
    const existing = dropdown.querySelector('.ai-install-chat-panel');
    if (existing) { existing.remove(); return; }

    const panel = document.createElement('div');
    panel.className = 'ai-install-chat-panel';

    // Model selector bar
    const modelBar = document.createElement('div');
    modelBar.className = 'ai-install-chat-model-bar';

    let selectedModel = 'haiku';

    chrome.runtime.sendMessage({ action: 'get-models' }, (resp) => {
      if (!resp?.models) return;
      resp.models.forEach((m) => {
        const btn = document.createElement('button');
        btn.className = 'ai-install-chat-model-btn';
        if (m.id === selectedModel) btn.classList.add('ai-install-chat-model-active');
        btn.textContent = m.label;
        if (!m.available) {
          btn.classList.add('ai-install-chat-model-locked');
          btn.title = 'Requires API key in settings';
        }
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          if (!m.available) {
            addMessage('assistant', `${m.label} requires your Claude API key. Add it in extension settings for deeper analysis.`);
            return;
          }
          selectedModel = m.id;
          modelBar.querySelectorAll('.ai-install-chat-model-btn').forEach(b => b.classList.remove('ai-install-chat-model-active'));
          btn.classList.add('ai-install-chat-model-active');
          addMessage('assistant', `Switched to ${m.label}`);
        });
        modelBar.appendChild(btn);
      });
    });

    const messages = document.createElement('div');
    messages.className = 'ai-install-chat-messages';

    const inputRow = document.createElement('div');
    inputRow.className = 'ai-install-chat-input-row';

    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'ai-install-chat-input';
    input.placeholder = 'Ask about this repo...';

    const sendBtn = document.createElement('button');
    sendBtn.className = 'ai-install-chat-send';
    sendBtn.textContent = '→';

    inputRow.append(input, sendBtn);
    panel.append(modelBar, messages, inputRow);
    dropdown.appendChild(panel);

    let repoContext = '';
    const repoContextReady = getRepoContext(repoInfo, stackInfo).then(ctx => { repoContext = ctx || ''; });
    const conversationHistory = [];

    function renderMarkdown(text) {
      return text
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
        .replace(/`(.+?)`/g, '<code>$1</code>')
        .replace(/\n\n/g, '<br><br>')
        .replace(/\n/g, '<br>');
    }

    function addMessage(role, text) {
      const msg = document.createElement('div');
      msg.className = `ai-install-chat-msg ai-install-chat-${role}`;
      if (role === 'assistant') {
        msg.innerHTML = renderMarkdown(text);
      } else {
        msg.textContent = text;
      }
      messages.appendChild(msg);
      messages.scrollTop = messages.scrollHeight;
    }

    function addTyping() {
      const msg = document.createElement('div');
      msg.className = 'ai-install-chat-msg ai-install-chat-assistant ai-install-chat-typing';
      msg.textContent = '...';
      messages.appendChild(msg);
      messages.scrollTop = messages.scrollHeight;
      return msg;
    }

    async function sendMessage() {
      const text = input.value.trim();
      if (!text) return;

      input.value = '';
      addMessage('user', text);
      conversationHistory.push({ role: 'user', content: text });

      const typingEl = addTyping();

      chrome.runtime.sendMessage({
        action: 'chat',
        messages: conversationHistory,
        readmeText: repoContext,
        repoName: `${repoInfo.owner}/${repoInfo.repo}`,
        stacks: stackInfo.stacks,
        model: selectedModel,
      }, (response) => {
        typingEl.remove();
        if (response && response.reply) {
          addMessage('assistant', response.reply);
          conversationHistory.push({ role: 'assistant', content: response.reply });
        } else {
          addMessage('assistant', response?.error || 'Failed to get response.');
        }
      });
    }

    sendBtn.addEventListener('click', (e) => { e.stopPropagation(); sendMessage(); });
    input.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') sendMessage();
    });
    input.addEventListener('click', (e) => e.stopPropagation());

    addMessage('assistant', 'Loading repo context...');
    repoContextReady.then(() => {
      // Replace loading message with actual status
      const lastMsg = messages.querySelector('.ai-install-chat-assistant:last-child');
      if (lastMsg) {
        const hasContext = !!repoContext;
        lastMsg.innerHTML = renderMarkdown(hasContext
          ? `Ready! I've analyzed ${repoInfo.owner}/${repoInfo.repo} — files, README, topics, languages. Ask me anything.`
          : `No repo info found on this page. I can only answer general questions about ${repoInfo.owner}/${repoInfo.repo}.`);
      }
    });

    setTimeout(() => input.focus(), 100);
  }

  // --- Dropdown ---

  function closeDropdown() {
    const existing = document.getElementById(DROPDOWN_ID);
    if (existing) existing.remove();
  }

  function createDropdown(repoInfo, anchorBtn) {
    closeDropdown();

    const dropdown = document.createElement('div');
    dropdown.id = DROPDOWN_ID;
    dropdown.className = 'ai-install-dropdown';

    const stackInfo = detectStack();
    const trustInfo = parseTrustInfo(repoInfo.platform);

    chrome.storage.sync.get({
      defaultClient: '',
      oneClick: false,
      customCommand: '',
      emojiPack: 'animals',
      shareTemplate: '',
    }, async (settings) => {
      const commands = getCommands(repoInfo, stackInfo, settings.customCommand);

      // One-click mode
      if (settings.oneClick && settings.defaultClient) {
        const cmd = commands.find((c) => c.id === settings.defaultClient);
        if (cmd) {
          const ok = await showInstallConfirm(`${repoInfo.owner}/${repoInfo.repo}`, cmd.label, cmd.icon);
          if (!ok) return;
          executeOrCopy(cmd.id, cmd.command, repoInfo.url, anchorBtn, cmd.openUrl);
          return;
        }
      }

      // Stack label header
      if (stackInfo.stacks.length > 0 || stackInfo.hasDocker) {
        const header = document.createElement('div');
        header.className = 'ai-install-stack-header';
        const badges = [...stackInfo.stacks];
        if (stackInfo.hasDocker) badges.push('Docker');
        badges.forEach(s => {
          const badge = document.createElement('span');
          badge.className = 'ai-install-stack-badge';
          badge.textContent = s;
          header.appendChild(badge);
        });
        dropdown.appendChild(header);
      }

      // Trust info bar
      if (trustInfo) {
        const trustBar = document.createElement('div');
        trustBar.className = 'ai-install-trust-bar';
        const items = [];
        if (trustInfo.stars) items.push(`★ ${trustInfo.stars}`);
        if (trustInfo.license) items.push(`⚖ ${trustInfo.license}`);
        if (trustInfo.lastCommit) items.push(`⏱ ${trustInfo.lastCommit}`);
        items.forEach((text, i) => {
          if (i > 0) {
            const sep = document.createElement('span');
            sep.className = 'ai-install-trust-sep';
            sep.textContent = '·';
            trustBar.appendChild(sep);
          }
          const span = document.createElement('span');
          span.className = 'ai-install-trust-item';
          span.textContent = text;
          trustBar.appendChild(span);
        });
        dropdown.appendChild(trustBar);
      }

      // SMILE-enabled badge
      const hasSmileBadge = detectSmileBadge();
      if (hasSmileBadge) {
        const enabled = document.createElement('div');
        enabled.className = 'ai-install-smile-enabled';
        enabled.textContent = '⚡ SMILE-enabled repo';
        dropdown.appendChild(enabled);
      }

      // Quick Summary button
      const summaryItem = document.createElement('button');
      summaryItem.className = 'ai-install-dropdown-item ai-install-summary-item';
      const summaryIcon = document.createElement('span');
      summaryIcon.className = 'ai-install-item-icon';
      summaryIcon.textContent = '\u2139\uFE0F';
      const summaryLabel = document.createElement('span');
      summaryLabel.className = 'ai-install-item-label';
      summaryLabel.textContent = 'Quick Summary';
      summaryItem.append(summaryIcon, summaryLabel);
      summaryItem.addEventListener('click', (e) => {
        e.stopPropagation();
        showRepoSummary(dropdown, repoInfo, stackInfo);
      });
      dropdown.appendChild(summaryItem);

      // Ask AI chat button
      const chatItem = document.createElement('button');
      chatItem.className = 'ai-install-dropdown-item ai-install-summary-item';
      const chatIcon = document.createElement('span');
      chatIcon.className = 'ai-install-item-icon';
      chatIcon.textContent = '\uD83D\uDCAC';
      const chatLabel = document.createElement('span');
      chatLabel.className = 'ai-install-item-label';
      chatLabel.textContent = 'Ask AI';
      chatItem.append(chatIcon, chatLabel);
      chatItem.addEventListener('click', (e) => {
        e.stopPropagation();
        showRepoChat(dropdown, repoInfo, stackInfo);
      });
      dropdown.appendChild(chatItem);

      if ((stackInfo.stacks.length > 0 || stackInfo.hasDocker) || trustInfo || hasSmileBadge) {
        const div = document.createElement('div');
        div.className = 'ai-install-divider';
        dropdown.appendChild(div);
      }

      // Command items
      commands.forEach((cmd) => {
        const item = document.createElement('button');
        item.className = 'ai-install-dropdown-item';
        if (cmd.id === settings.defaultClient) {
          item.classList.add('ai-install-default');
        }
        const cmdIcon = document.createElement('span');
        cmdIcon.className = 'ai-install-item-icon';
        cmdIcon.textContent = cmd.icon;
        const cmdLabel = document.createElement('span');
        cmdLabel.className = 'ai-install-item-label';
        cmdLabel.textContent = cmd.label;
        item.append(cmdIcon, cmdLabel);
        item.addEventListener('click', async (e) => {
          e.stopPropagation();
          closeDropdown();
          const ok = await showInstallConfirm(`${repoInfo.owner}/${repoInfo.repo}`, cmd.label, cmd.icon);
          if (!ok) return;
          await executeOrCopy(cmd.id, cmd.command, repoInfo.url, anchorBtn, cmd.openUrl);
        });
        dropdown.appendChild(item);
      });

      // Divider
      const divider = document.createElement('div');
      divider.className = 'ai-install-divider';
      dropdown.appendChild(divider);

      // Badge
      const badgeItem = document.createElement('button');
      badgeItem.className = 'ai-install-dropdown-item ai-install-badge-item';
      const badgeIcon = document.createElement('span');
      badgeIcon.className = 'ai-install-item-icon';
      badgeIcon.textContent = '🏷️';
      const badgeLabel = document.createElement('span');
      badgeLabel.className = 'ai-install-item-label';
      badgeLabel.textContent = 'Copy badge for README';
      badgeItem.append(badgeIcon, badgeLabel);
      badgeItem.addEventListener('click', async (e) => {
        e.stopPropagation();
        const badge = `[![Install with AI](https://img.shields.io/badge/Install_with-AI_%E2%9A%A1-blueviolet?style=for-the-badge)](${repoInfo.url})`;
        await copyToClipboard(badge);
        closeDropdown();
        showCopiedFeedback(anchorBtn);
      });
      dropdown.appendChild(badgeItem);

      // NFT Share
      const shareItem = document.createElement('button');
      shareItem.className = 'ai-install-dropdown-item ai-install-share-item';
      const packLabel = EMOJI_PACKS[settings.emojiPack]?.label || 'Animals';
      const shareIcon = document.createElement('span');
      shareIcon.className = 'ai-install-item-icon';
      shareIcon.textContent = '🎲';
      const shareLbl = document.createElement('span');
      shareLbl.className = 'ai-install-item-label';
      shareLbl.textContent = 'Share NFT ';
      const packTag = document.createElement('span');
      packTag.className = 'ai-install-pack-tag';
      packTag.textContent = packLabel;
      shareLbl.appendChild(packTag);
      shareItem.append(shareIcon, shareLbl);
      shareItem.addEventListener('click', async (e) => {
        e.stopPropagation();
        const nft = rollEmoji(settings.emojiPack);
        const pack = EMOJI_PACKS[settings.emojiPack] || EMOJI_PACKS.animals;
        const tierColors = { common: '#8b949e', rare: '#3b82f6', epic: '#a855f7', legendary: '#eab308' };
        const stars = nft.tier === 'legendary' ? '★★★' : nft.tier === 'epic' ? '★★' : nft.tier === 'rare' ? '★' : '';
        const glowClass = nft.tier === 'legendary' ? ' ai-install-glow-legendary' :
                          nft.tier === 'epic' ? ' ai-install-glow-epic' :
                          nft.tier === 'rare' ? ' ai-install-glow-rare' : '';

        // Lootbox spin: show random emojis rapidly, then land on result
        const allEmojis = Object.values(pack.tiers).flat();
        let spinCount = 0;
        const spinInterval = setInterval(() => {
          const rnd = allEmojis[Math.floor(Math.random() * allEmojis.length)];
          shareItem.textContent = '';
          const spinIcon = document.createElement('span');
          spinIcon.className = 'ai-install-item-icon ai-install-spin-emoji';
          spinIcon.textContent = rnd;
          const spinLabel = document.createElement('span');
          spinLabel.className = 'ai-install-item-label';
          spinLabel.style.color = '#8b949e';
          spinLabel.textContent = 'Rolling...';
          shareItem.append(spinIcon, spinLabel);
          spinCount++;
          if (spinCount >= 8) {
            clearInterval(spinInterval);
            // Reveal!
            shareItem.textContent = '';
            const revealEmoji = document.createElement('span');
            revealEmoji.className = 'ai-install-nft-emoji-inline' + glowClass;
            revealEmoji.textContent = nft.emoji;
            const revealLabel = document.createElement('span');
            revealLabel.className = 'ai-install-item-label';
            revealLabel.style.color = tierColors[nft.tier];
            revealLabel.style.fontWeight = '700';
            revealLabel.textContent = `${nft.label} ${stars}`;
            shareItem.append(revealEmoji, revealLabel);
            recordRoll(nft, repoInfo.url);
            showSharePicker(shareItem, nft, repoInfo.url, settings.shareTemplate);
          }
        }, 80);
      });
      dropdown.appendChild(shareItem);

      anchorBtn.parentElement.appendChild(dropdown);
    });
  }

  // --- Button Injection (multi-platform) ---

  function findCodeButton() {
    const platform = detectPlatform();

    if (platform === 'github') {
      const allButtons = document.querySelectorAll('button');
      for (const btn of allButtons) {
        const text = btn.textContent.trim();
        if (text === 'Code' && btn.classList.contains('btn-primary')) return btn;
      }
      const byTestId = document.querySelector('[data-testid="code-button"]');
      if (byTestId) return byTestId;
      for (const btn of allButtons) {
        if (btn.textContent.trim() === 'Code' && btn.querySelector('[data-component="buttonContent"]')) return btn;
      }
      const getRepo = document.querySelector('get-repo');
      if (getRepo) {
        const inner = getRepo.querySelector('.btn-primary') || getRepo.querySelector('button');
        if (inner) return inner;
      }
      const primary = document.querySelector('.btn-primary[aria-haspopup="menu"]');
      if (primary) return primary;
      const sidebar = document.querySelector('.Layout-sidebar .btn-primary')
        || document.querySelector('[class*="BtnGroup"] .btn-primary');
      if (sidebar) return sidebar;
    }

    if (platform === 'gitlab') {
      const cloneBtn = document.querySelector('[data-testid="clone-dropdown"]')
        || document.querySelector('.git-clone-holder button')
        || document.querySelector('button[data-qa="code-dropdown"]');
      if (cloneBtn) return cloneBtn;
      const allBtns = document.querySelectorAll('button');
      for (const btn of allBtns) {
        const t = btn.textContent.trim();
        if (t === 'Code' || t === 'Clone') return btn;
      }
    }

    if (platform === 'bitbucket') {
      const cloneBtn = document.querySelector('[data-testid="clone-button"]')
        || document.querySelector('button[aria-label="Clone"]');
      if (cloneBtn) return cloneBtn;
      const allBtns = document.querySelectorAll('button');
      for (const btn of allBtns) {
        if (btn.textContent.trim() === 'Clone') return btn;
      }
    }

    return null;
  }

  function injectButton() {
    if (document.getElementById(BUTTON_ID)) return;

    const info = getRepoInfo();
    if (!info) return;

    const anchor = findCodeButton();
    if (!anchor) return;

    const container = document.createElement('div');
    container.className = 'ai-install-container';
    container.style.position = 'relative';

    const btn = document.createElement('button');
    btn.id = BUTTON_ID;
    btn.className = 'ai-install-btn';
    btn.innerHTML = '<span class="ai-install-icon">⚡</span> Install with AI';

    btn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      const existing = document.getElementById(DROPDOWN_ID);
      if (existing) {
        closeDropdown();
      } else {
        createDropdown(info, btn);
      }
    });

    container.appendChild(btn);

    const insertTarget = anchor.closest('.BtnGroup')
      || anchor.closest('[class*="ButtonGroup"]')
      || anchor.closest('get-repo')
      || anchor.closest('.git-clone-holder')
      || anchor.parentElement;
    if (insertTarget && insertTarget.parentElement) {
      insertTarget.parentElement.insertBefore(container, insertTarget.nextSibling);
    }
  }

  // --- Event Listeners ---

  document.addEventListener('click', (e) => {
    if (!e.target.closest(`#${DROPDOWN_ID}`) && !e.target.closest(`#${BUTTON_ID}`)) {
      closeDropdown();
    }
  });

  injectButton();

  let debounceTimer;
  const observer = new MutationObserver(() => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      if (!document.getElementById(BUTTON_ID)) {
        injectButton();
      }
    }, 300);
  });

  observer.observe(document.body, { childList: true, subtree: true });

  document.addEventListener('turbo:load', () => {
    setTimeout(injectButton, 500);
  });

  // --- Keyboard Shortcut (Cmd+Shift+I) ---
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === 'quick-install') {
      const info = getRepoInfo();
      if (!info) return;
      const btn = document.getElementById(BUTTON_ID);
      const stackInfo = detectStack();
      chrome.storage.sync.get({ defaultClient: 'claude', customCommand: '' }, (settings) => {
        const commands = getCommands(info, stackInfo, settings.customCommand);
        const cmd = commands.find(c => c.id === settings.defaultClient) || commands[0];
        if (btn) {
          executeOrCopy(cmd.id, cmd.command, info.url, btn, cmd.openUrl);
        } else {
          copyToClipboard(cmd.command);
        }
      });
    }
  });
})();
