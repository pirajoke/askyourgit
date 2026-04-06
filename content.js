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
        command: `cursor ${url}`,
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
    const shortUrl = url.replace(/^https?:\/\//, '');
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

  function showCopiedFeedback(btn) {
    const original = btn.innerHTML;
    btn.innerHTML = '<span class="ai-install-icon">✓</span> Copied!';
    btn.classList.add('ai-install-copied');
    setTimeout(() => {
      btn.innerHTML = original;
      btn.classList.remove('ai-install-copied');
    }, 1500);
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
    }, (settings) => {
      const commands = getCommands(repoInfo, stackInfo, settings.customCommand);

      // One-click mode
      if (settings.oneClick && settings.defaultClient) {
        const cmd = commands.find((c) => c.id === settings.defaultClient);
        if (cmd) {
          copyToClipboard(cmd.command).then(() => showCopiedFeedback(anchorBtn));
          return;
        }
      }

      // Stack label header
      if (stackInfo.stacks.length > 0 || stackInfo.hasDocker) {
        const header = document.createElement('div');
        header.className = 'ai-install-stack-header';
        const badges = [...stackInfo.stacks];
        if (stackInfo.hasDocker) badges.push('Docker');
        header.innerHTML = badges.map(s => `<span class="ai-install-stack-badge">${s}</span>`).join('');
        dropdown.appendChild(header);
      }

      // Trust info bar
      if (trustInfo) {
        const trustBar = document.createElement('div');
        trustBar.className = 'ai-install-trust-bar';
        const parts = [];
        if (trustInfo.stars) parts.push(`<span class="ai-install-trust-item">★ ${trustInfo.stars}</span>`);
        if (trustInfo.license) parts.push(`<span class="ai-install-trust-item">⚖ ${trustInfo.license}</span>`);
        if (trustInfo.lastCommit) parts.push(`<span class="ai-install-trust-item">⏱ ${trustInfo.lastCommit}</span>`);
        trustBar.innerHTML = parts.join('<span class="ai-install-trust-sep">·</span>');
        dropdown.appendChild(trustBar);
      }

      // SMILE-enabled badge
      const hasSmileBadge = detectSmileBadge();
      if (hasSmileBadge) {
        const enabled = document.createElement('div');
        enabled.className = 'ai-install-smile-enabled';
        enabled.innerHTML = '⚡ SMILE-enabled repo';
        dropdown.appendChild(enabled);
      }

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
        item.innerHTML = `<span class="ai-install-item-icon">${cmd.icon}</span><span class="ai-install-item-label">${cmd.label}</span>`;
        item.addEventListener('click', async (e) => {
          e.stopPropagation();
          await copyToClipboard(cmd.command);
          closeDropdown();
          showCopiedFeedback(anchorBtn);
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
      badgeItem.innerHTML = '<span class="ai-install-item-icon">🏷️</span><span class="ai-install-item-label">Copy badge for README</span>';
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
      shareItem.innerHTML = `<span class="ai-install-item-icon">🎲</span><span class="ai-install-item-label">Share NFT <span class="ai-install-pack-tag">${packLabel}</span></span>`;
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
          shareItem.innerHTML = `<span class="ai-install-item-icon ai-install-spin-emoji">${rnd}</span><span class="ai-install-item-label" style="color:#8b949e">Rolling...</span>`;
          spinCount++;
          if (spinCount >= 8) {
            clearInterval(spinInterval);
            // Reveal!
            shareItem.innerHTML = `<span class="ai-install-nft-emoji-inline${glowClass}">${nft.emoji}</span><span class="ai-install-item-label" style="color:${tierColors[nft.tier]};font-weight:700">${nft.label} ${stars}</span><span style="margin-left:auto;font-size:11px;color:#8b949e">Copied!</span>`;
            copyEmojiShare(nft.emoji, repoInfo.url, settings.shareTemplate);
            recordRoll(nft, repoInfo.url);
            setTimeout(() => {
              closeDropdown();
              showCopiedFeedback(anchorBtn);
            }, 1400);
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
        copyToClipboard(cmd.command).then(() => {
          if (btn) showCopiedFeedback(btn);
        });
      });
    }
  });
})();
