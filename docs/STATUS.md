# Ask your GIT Status

Last updated: 2026-05-23

## Current State

Ask your GIT is a hackathon prototype with:
- Chrome extension repo analysis UI on GitHub/GitLab/Bitbucket pages.
- macOS menu bar companion app installed via DMG.
- Download site deployed with direct macOS DMG link.
- Native app action `Analyze Current Repo` now opens a compact WebView repo analysis window with a 21st/CodexBar-style shell.

Latest saved state: 21st-style native WebView analyzer shell.

Public site:
https://pirajoke.github.io/askyourgit/

Public DMG:
https://pirajoke.github.io/askyourgit/dist/askyourgit-macos.dmg

## Completed In Latest Session

- Added `WebRepoAnalysisWindowController` and switched `AppDelegate.analyzeCurrentRepo()` to open it.
- Moved the native analyzer UI into `WKWebView` so layout behaves like a web component instead of drifting in AppKit stacks.
- Reworked the app shell around 21st/CodexBar references:
  - fixed 432x688 companion window
  - top pill tabs: Overview, Codex, Claude, Cursor, Tools
  - compact repo hero with badges, metadata, URL, status, stars/forks/primary language
  - grouped action rows for Quick Summary, Ask AI, Claude Code, Cursor, Codex, custom tool, settings, and share
  - scrollable signal card with stack, README signal, topics, and description
  - embedded chat/detail sheets that expand inside the same panel
- Updated the package builder to link the Swift app with `WebKit`.
- Rebuilt `dist/askyourgit-prototype.zip`.
- Rebuilt `dist/askyourgit-macos.dmg`.
- Installed the new app into `/Applications/Ask your GIT Companion.app`.

## Verified

- `swiftc macos-companion/AskYourGITCompanion.swift -o /private/tmp/AskYourGITCompanion -framework Cocoa -framework WebKit`
- `PYTHONPATH=/private/tmp/askyourgit-pydeps ./scripts/build-prototype-package.sh`
- `/Applications/Ask your GIT Companion.app/Contents/MacOS/AskYourGITCompanion` is running.
- `hdiutil verify dist/askyourgit-macos.dmg` reports the image checksum is valid.

## Remaining Work

- Remove old unused AppKit analyzer fallback classes after the WebView design is visually accepted.
- Add real native AI API calls instead of local heuristic answers.
- Add proper settings persistence for native app custom tools.
- Improve native visual QA with screenshots after every UI iteration.
- Add code signing/notarization for smoother macOS install.
- Clean local untracked artifacts before the next release pass:
  - `.DS_Store`
  - `store/screenshot-1.png`
  - `store/screenshot-2.png`
  - `store/screenshot-3.png`

## Resume Context

Continue from the native WebView app design. The user complaint was that the macOS analyzer kept drifting into an ugly centered/right-shifted layout. The active app path is now `WebRepoAnalysisWindowController` in `macos-companion/AskYourGITCompanion.swift`, opened from `AppDelegate.analyzeCurrentRepo()`. The next useful work is visual QA against a fresh screenshot, then either real native AI integration or cleanup of the old unused controllers.
