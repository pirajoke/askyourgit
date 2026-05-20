# Ask your GIT Status

Last updated: 2026-05-20

## Current State

Ask your GIT is a hackathon prototype with:
- Chrome extension repo analysis UI on GitHub/GitLab/Bitbucket pages.
- macOS menu bar companion app installed via DMG.
- Download site deployed with direct macOS DMG link.
- Native app action `Analyze Current Repo` now opens a compact dark repo analysis window modeled after the extension dropdown/menu style.

Latest saved commit: `2f7463f` (`Match native analyzer to extension menu`)

Public site:
https://pirajoke.github.io/askyourgit/

Public DMG:
https://pirajoke.github.io/askyourgit/dist/askyourgit-macos.dmg

## Completed In Latest Session

- Added `CompactRepoAnalysisWindowController` for the native macOS companion.
- Switched the menu bar app from the old large dashboard window to the compact dropdown-style analyzer.
- Added repository badges, license/updated metadata, repo URL, and status.
- Added action rows:
  - Quick Summary
  - Ask AI
  - Claude Code
  - Cursor
  - Codex
  - Add custom tool
  - Settings
  - Share NFT
- Made `Quick Summary` and `Ask AI` expand a compact detail panel instead of showing a full dashboard by default.
- Added local repo answer logic for weak points, setup, stack, structure, and generic summary questions.
- Added GitHub API license parsing for the native metadata row.
- Rebuilt `dist/askyourgit-prototype.zip`.
- Rebuilt `dist/askyourgit-macos.dmg`.
- Installed the new app into `/Applications/Ask your GIT Companion.app`.
- Pushed to `main` and confirmed GitHub Pages rebuilt.

## Verified

- `swiftc macos-companion/AskYourGITCompanion.swift -o /private/tmp/AskYourGITCompanion -framework Cocoa`
- `PYTHONPATH=/private/tmp/askyourgit-pydeps ./scripts/build-prototype-package.sh`
- `/Applications/Ask your GIT Companion.app/Contents/MacOS/AskYourGITCompanion` is running.
- `hdiutil verify dist/askyourgit-macos.dmg` reports the image checksum is valid.
- GitHub Pages status is `built`.
- Public DMG `content-length` is `1772890`, matching local `dist/askyourgit-macos.dmg`.

## Remaining Work

- Remove the old unused `RepoAnalysisWindowController` fallback class after demo pressure is over.
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

Continue from the compact native app design. The main user complaint was that the macOS analyzer looked like a large gray dashboard instead of the extension dropdown. The active app path is now `CompactRepoAnalysisWindowController` in `macos-companion/AskYourGITCompanion.swift`. The download artifact and site are already updated, so the next useful work is either real AI integration in the native Ask AI flow or cleanup of the old unused controller.
