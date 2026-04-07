# S.M.I.L.E. — Smart Method for Installing & Learning Effortlessly

> One-click AI-powered installation for any GitHub, GitLab, or Bitbucket repo. Clone, set up, and explore projects instantly with Claude Code, Cursor, Codex, or Terminal.

![Install with AI](https://img.shields.io/badge/Install_with-AI_%E2%9A%A1-blueviolet?style=for-the-badge)
![Version](https://img.shields.io/badge/version-2.3.0-blue?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Chrome-green?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)

---

## What is SMILE?

SMILE is a Chrome extension that adds an **"Install with AI"** button to every repository on GitHub, GitLab, and Bitbucket. Instead of manually reading installation docs, copying commands, and setting up environments — you click one button and AI handles everything.

**The problem:** You find a cool repo, but setting it up takes 10-30 minutes: read README, install dependencies, configure environment, fix issues.

**The solution:** Click "Install with AI" → AI reads the README, detects the stack, and sets up the project automatically.

---

## Features

### Core: One-Click Install

| Feature | Description |
|---------|-------------|
| **Claude Code** | Generates a Claude command that clones the repo and sets it up following the README |
| **Cursor** | Opens the repo directly in Cursor IDE via URL scheme |
| **Terminal + Claude** | Clones repo, installs dependencies, then launches Claude for setup |
| **Codex CLI** | Sends a Codex command to clone and configure the project |
| **Custom Command** | Define your own install template with `{url}`, `{owner}`, `{repo}`, `{stack}` placeholders |

### Smart Stack Detection

Automatically detects the project's tech stack by scanning the file tree:

- **Node.js** — `package.json` detected → runs `npm install`
- **TypeScript** — `tsconfig.json` detected
- **Next.js** — `next.config.js/mjs/ts` detected
- **Python** — `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile` → creates venv & installs
- **Rust** — `Cargo.toml` → runs `cargo build`
- **Go** — `go.mod` → runs `go build`
- **Ruby** — `Gemfile` detected
- **Java** — `build.gradle` or `pom.xml` detected
- **Docker** — `Dockerfile` or `docker-compose.yml` detected, noted in install command

Stack badges are displayed at the top of the dropdown so you instantly see what you're working with.

### Trust & Safety Info

Before installing, SMILE shows key trust indicators (GitHub only):

- **Stars** — repository popularity
- **License** — MIT, Apache, GPL, etc.
- **Last commit** — how recently the project was updated

### AI Quick Summary

Click **"Quick Summary"** to get an AI-generated overview of any repo:

- What the project does
- Key features
- How to get started

Summaries are **cached for 24 hours** per repo — second click is instant. Works via a free proxy (Haiku model) with no API key required.

### AI Chat — Ask About Any Repo

Click **"Ask AI"** to open an interactive chat right inside the dropdown:

- Ask questions about the repo without reading the code
- AI uses the README as context to answer
- Multi-turn conversation — ask follow-up questions
- **3 model tiers:**
  - **Haiku (fast)** — free, instant answers via proxy
  - **Sonnet (deep)** — requires your API key, more detailed analysis
  - **Opus (max)** — requires your API key, most capable model

Example questions:
- "How do I configure authentication?"
- "What database does this use?"
- "What's the deployment process?"
- "Is this production-ready?"

### NFT Emoji Share

Share repos with style using randomized emoji lootboxes:

- **4 emoji packs:** Animals, Space, Food, Objects
- **4 rarity tiers:** Common (60%), Rare (25%), Epic (10%), Legendary (5%)
- **Lootbox animation** — spin effect before reveal
- **Glow effects** — Rare/Epic/Legendary emojis have special visual effects
- **Share to:** Telegram, WhatsApp, X (Twitter), or clipboard
- **Custom share format** — use `{emoji}`, `{url}`, `{repo}` placeholders
- **Roll stats** — track your total rolls, tier distribution, and recent history

### Terminal Bridge (Optional)

Enable direct command execution in your terminal without copy-pasting:

1. Run `bash native-host/install.sh`
2. Commands are sent directly to Terminal.app, iTerm2, or Warp
3. Status shown in extension popup: Connected / Not installed

### SMILE Badge for Repos

Copy a ready-made badge for your repo's README:

```markdown
[![Install with AI](https://img.shields.io/badge/Install_with-AI_%E2%9A%A1-blueviolet?style=for-the-badge)](https://github.com/your/repo)
```

SMILE auto-detects repos that have this badge and shows a "SMILE-enabled repo" indicator.

### Additional Features

- **Dark mode** — full support for system dark mode and GitHub's dark theme
- **Keyboard shortcut** — `Cmd+Shift+I` (Mac) / `Ctrl+Shift+I` (Windows) to copy the default install command
- **One-click mode** — skip the dropdown, instantly copy/execute the default command
- **Confirm modal** — safety confirmation before any install action
- **Multi-platform** — works on GitHub, GitLab, and Bitbucket
- **Extension badge** — shows your last rolled emoji on the extension icon

---

## Install in 3 Steps

### 1. Download

[**Download ZIP**](https://github.com/pirajoke/smile/releases/latest/download/smile-extension.zip) from the latest release.

### 2. Unzip

Double-click `smile-extension.zip` — a folder will appear.

### 3. Load into Chrome

1. Go to `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **"Load unpacked"**
4. Select the unzipped folder
5. Visit any GitHub repo — the **"Install with AI"** button appears next to the Code button

---

## Settings (Extension Popup)

| Setting | Description |
|---------|-------------|
| **Default AI Client** | Choose which tool to use by default (Claude, Cursor, Terminal, Codex) |
| **One-click mode** | Skip dropdown — instantly runs the default command |
| **Claude API Key** | Optional. Enables AI summaries and chat with Sonnet/Opus models |
| **Terminal App** | Choose terminal: Auto-detect, Terminal.app, iTerm2, or Warp |
| **Custom Command** | Your own install command template |
| **Emoji Pack** | Choose lootbox theme: Animals, Space, Food, or Objects |
| **Share Format** | Custom format for emoji shares |
| **Roll Stats** | View your roll history and tier distribution |

---

## Architecture

```
content.js     — Main content script: button injection, dropdown UI, stack detection,
                  trust info, README extraction, AI summary/chat panels, NFT system
background.js  — Service worker: command execution, Claude API proxy, model routing
content.css    — All styles including dark mode support
popup.html/js  — Extension settings UI
manifest.json  — Chrome Extension Manifest V3
native-host/   — Optional terminal bridge for direct command execution
proxy/         — Cloudflare Worker / Vercel proxy for free AI tier
```

---

## For Developers

```bash
git clone https://github.com/pirajoke/smile.git
```

Load the repo folder directly into `chrome://extensions` with Developer mode on.

### AI Proxy (for free tier)

The free Haiku tier requires a backend proxy to keep the API key secure:

```bash
cd proxy
# Option 1: Cloudflare Workers
npx wrangler login && npx wrangler deploy
npx wrangler secret put ANTHROPIC_API_KEY

# Option 2: Vercel
cd vercel && vercel deploy
vercel env add ANTHROPIC_API_KEY
```

Update `PROXY_URL` in `background.js` with your deployed URL.

---

## Privacy

- No data collection, no analytics, no tracking
- API key stored locally in `chrome.storage.sync`
- AI chat sends only README text to the API — no personal data
- Summary cache stored locally in `chrome.storage.local`
- Open source — inspect every line of code

---

## License

MIT
