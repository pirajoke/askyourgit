# Ask your GIT — AI for any repo

> Ask AI about any GitHub, GitLab, or Bitbucket repo. Get instant summaries, chat with AI about the code, then install with one click using Claude Code, Cursor, Codex, or your own tools.

![Ask your GIT](https://img.shields.io/badge/Ask_your-GIT_%E2%9A%A1-blueviolet?style=for-the-badge)
![Version](https://img.shields.io/badge/version-3.0.0-blue?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Chrome-green?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)

---

## What is Ask your GIT?

A Chrome extension that adds an **"Ask your GIT"** button to every repository page. Instead of reading through long READMEs — ask AI what the project does, how to use it, and install it with one click.

**The problem:** You find a cool repo, but understanding it takes 10-30 minutes: read README, figure out the stack, install dependencies, configure environment.

**The solution:** Click "Ask your GIT" → AI explains the project → one click to install with your favorite AI coding tool.

---

## Features

### Ask AI About Any Repo

Click **"Quick Summary"** for an instant AI overview:
- What the project does
- Key features and tech stack
- How to get started

Click **"Ask AI"** to chat interactively:
- Ask questions about the repo without reading the code
- Multi-turn conversation with follow-up questions
- **3 model tiers:** Haiku (fast, free) / Sonnet (deep) / Opus (max)

### One-Click Install

| Tool | Description |
|------|-------------|
| **Claude Code** | Generates a Claude command that clones and sets up the project |
| **Cursor** | Opens the repo directly in Cursor IDE |
| **Codex CLI** | Sends a Codex command to clone and configure |
| **Custom Tools** | Add your own IDE/tools with `{url}`, `{owner}`, `{repo}`, `{stack}` placeholders |

### Smart Stack Detection

Automatically detects the project's tech stack:
- **Node.js** / **TypeScript** / **Next.js**
- **Python** (requirements.txt, pyproject.toml, Pipfile)
- **Rust** (Cargo.toml) / **Go** (go.mod)
- **Ruby** / **Java** / **Docker**

### Trust & Safety Info

Before installing, see key trust indicators (GitHub only):
- Stars, License, Last commit date

### Additional Features

- **25 tool presets** — Windsurf, Zed, JetBrains, VS Code, and more
- **Terminal Bridge** — execute commands directly in Terminal.app, iTerm2, or Warp
- **Dark mode** — full support for system and GitHub dark themes
- **Keyboard shortcut** — `Cmd+Shift+I` / `Ctrl+Shift+I`
- **One-click mode** — skip dropdown, instantly copy default command
- **Zero tracking** — no data collection, no analytics, fully open source

---

## Install

### From Chrome Web Store

Coming soon — or install manually:

### Manual Install

1. [**Download ZIP**](https://github.com/pirajoke/askyourgit/releases/latest/download/askyourgit-v3.0.0.zip) from the latest release
2. Unzip the folder
3. Go to `chrome://extensions` → Enable **Developer mode**
4. Click **"Load unpacked"** → select the unzipped folder
5. Visit any GitHub repo — the button appears next to the Code button

---

## Architecture

```
content.js     — Button injection, dropdown UI, stack detection,
                  trust info, AI summary/chat panels
background.js  — Service worker: AI proxy, model routing, command execution
content.css    — Styles + dark mode
popup.html/js  — Extension settings
manifest.json  — Chrome Extension Manifest V3
native-host/   — Optional terminal bridge
proxy/         — Cloudflare Worker / Vercel proxy for free AI tier
```

---

## For Developers

```bash
git clone https://github.com/pirajoke/askyourgit.git
```

Load the folder into `chrome://extensions` with Developer mode on.

### AI Proxy (for free tier)

```bash
cd proxy
# Cloudflare Workers
npx wrangler login && npx wrangler deploy
npx wrangler secret put ANTHROPIC_API_KEY

# Or Vercel
cd vercel && vercel deploy
vercel env add ANTHROPIC_API_KEY
```

---

## Privacy

- No data collection, no analytics, no tracking
- API key stored locally in Chrome storage
- AI chat sends only README text to the API
- Open source — inspect every line of code

---

## License

MIT
