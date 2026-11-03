# Chrome Web Store resubmission checklist

Paste these into the Developer Dashboard. They must match `privacy-policy.html` and the code.

## Privacy practices tab

**Single purpose**
> Ask your GIT helps developers understand and install code repositories: on a GitHub, GitLab or Bitbucket repository page it shows an AI summary and chat about that repository, and gives one-click install commands for local coding tools.

**Permission justifications**

| Permission | Justification |
|---|---|
| `storage` | Saves the user's preferences (default tool, custom commands, theme), an optional Claude API key, and local usage counters shown in the popup. |
| `clipboardWrite` | Copies the install command for the repository to the clipboard when the user clicks an install tool. |
| `nativeMessaging` | Optional: when the user has installed the separate Ask your GIT Companion app on macOS, sends the clicked install command to it so it opens in the user's terminal. Without the companion the extension falls back to copying the command. |
| Host `api.github.com/repos/*` | Reads public repository metadata, file list, languages and README for the repository the user is viewing, to give the AI context. |
| Host `api.anthropic.com/v1/messages` | Sends AI requests directly to Anthropic when the user has entered their own Claude API key. |
| Host `vercel-nu-wheat.vercel.app/api/chat` | Our AI proxy, used for the free AI tier when the user has no API key. |
| Content scripts on github.com / gitlab.com / bitbucket.org | Injects the Ask your GIT button and panel on repository pages. |

**Remote code:** No, I am not using remote code. (All JS is bundled; the proxy only returns text.)

**Data usage, tick:**
- Website content (repository README/metadata sent to AI when the user clicks Summary/Ask AI)
- User activity? No.
- Personal communications? No. *(If the reviewer pushes back, chat questions can be declared as "User-generated content" — not a listed category, so describe it in the policy, as done.)*

**Certify all three:** not sold to third parties; not used for unrelated purposes; not used for creditworthiness.

**Privacy policy URL:** `https://pirajoke.github.io/askyourgit/privacy-policy.html` — make sure GitHub Pages is serving the updated file before resubmitting.

## Before you press "Submit for review"

1. Build the zip from this branch (only extension files: manifest, *.js, *.css, popup.html, icons/). Do not include `dist/`, `proxy/`, `native-host/`, `macos-companion/`, `.DS_Store`.
2. Check that the AI proxy URL responds; a reviewer who sees "AI service unavailable" can reject for broken functionality.
3. Update the store description from `store/listing.md` (no "zero data collection" claims).
4. In the reviewer notes, explain: free AI tier works without a key; the Terminal Bridge is optional and needs the companion app; otherwise commands are copied to the clipboard.
