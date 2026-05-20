#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_EXT_DIR="$(dirname "$SCRIPT_DIR")"
EXT_DIR="${ASKYOURGIT_EXTENSION_DIR:-$DEFAULT_EXT_DIR}"
HOST_NAME="com.smile.ai_install"
BRIDGE_SRC="$SCRIPT_DIR/smile-bridge.py"
BRIDGE_DST="$HOME/.local/bin/smile-bridge"
MANIFEST_SRC="$SCRIPT_DIR/$HOST_NAME.json"
CWS_EXTENSION_ID="pbfofhbacoeelkokidbdcljfmhakpngh"

EXT_IDS=()

add_ext_id() {
  local ext_id="$1"
  [[ "$ext_id" =~ ^[a-p]{32}$ ]] || return 0
  for existing in "${EXT_IDS[@]}"; do
    [ "$existing" = "$ext_id" ] && return 0
  done
  EXT_IDS+=("$ext_id")
}

# Accept extension ID as argument.
if [ -n "${1:-}" ]; then
  add_ext_id "$1"
fi

# Try auto-detect from installed Chrome/Brave/Edge extension stores.
for base in \
  "$HOME/Library/Application Support/Google/Chrome/Default/Extensions" \
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions" \
  "$HOME/Library/Application Support/Microsoft Edge/Default/Extensions"; do
  if [ -d "$base" ]; then
    for dir in "$base"/*/; do
      for ver in "$dir"*/; do
        if [ -f "$ver/manifest.json" ] && grep -Eiq '"Ask your GIT|"AI Install"|askyourgit' "$ver/manifest.json" 2>/dev/null; then
          add_ext_id "$(basename "$(dirname "$ver")")"
        fi
      done
    done
  fi
done

# Detect currently loaded unpacked extensions from browser Secure Preferences.
detect_loaded_extension_ids() {
  local prefs_path="$1"
  [ -f "$prefs_path" ] || return 0
  /usr/bin/python3 - "$prefs_path" <<'PY'
import json
import os
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)

settings = data.get("extensions", {}).get("settings", {})
for ext_id, meta in settings.items():
    path = str(meta.get("path", ""))
    manifest = meta.get("manifest") or {}
    name = str(manifest.get("name", ""))
    description = str(manifest.get("description", ""))
    version = str((meta.get("service_worker_registration_info") or {}).get("version", ""))

    haystack = " ".join([path, name, description, version]).lower()
    matched = any(needle in haystack for needle in (
        "ask your git",
        "askyourgit",
        "ai-install-extension",
    ))

    if not matched and path.startswith("/"):
        manifest_path = os.path.join(path, "manifest.json")
        try:
            with open(manifest_path, "r", encoding="utf-8") as fh:
                disk_manifest = json.load(fh)
            disk_haystack = " ".join([
                str(disk_manifest.get("name", "")),
                str(disk_manifest.get("description", "")),
            ]).lower()
            matched = any(needle in disk_haystack for needle in (
                "ask your git",
                "askyourgit",
                "ai install",
            ))
        except Exception:
            pass

    if matched:
        print(ext_id)
PY
}

for prefs_path in \
  "$HOME/Library/Application Support/Google/Chrome/"*/"Secure Preferences" \
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/"*/"Secure Preferences" \
  "$HOME/Library/Application Support/Microsoft Edge/"*/"Secure Preferences"; do
  while IFS= read -r detected_id; do
    add_ext_id "$detected_id"
  done < <(detect_loaded_extension_ids "$prefs_path")
done

# Compute from the prepared unpacked extension path (Chrome's algorithm:
# SHA256 of path, first 32 chars, a=0...p=15).
EXT_ID=$(printf '%s' "$EXT_DIR" | LC_ALL=C LANG=C shasum -a 256 | head -c 32 | tr '0-9a-f' 'a-p')
add_ext_id "$EXT_ID"
echo "Computed unpacked extension ID: $EXT_ID"

# Keep the future Chrome Web Store ID allowed too.
add_ext_id "$CWS_EXTENSION_ID"

echo "Extension IDs:"
for ext_id in "${EXT_IDS[@]}"; do
  echo "  - $ext_id"
done

# Install bridge script
echo "Installing bridge to $BRIDGE_DST..."
mkdir -p "$(dirname "$BRIDGE_DST")"
cp "$BRIDGE_SRC" "$BRIDGE_DST"
chmod +x "$BRIDGE_DST"

# Chrome & Chromium-based NM host dirs
NM_DIRS=(
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
  "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
  "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
)

# Register NM manifest in all browser dirs
ALLOWED_ORIGINS=""
for ext_id in "${EXT_IDS[@]}"; do
  origin="\"chrome-extension://$ext_id/\""
  if [ -z "$ALLOWED_ORIGINS" ]; then
    ALLOWED_ORIGINS="$origin"
  else
    ALLOWED_ORIGINS="$ALLOWED_ORIGINS, $origin"
  fi
done

for nm_dir in "${NM_DIRS[@]}"; do
  mkdir -p "$nm_dir"
  sed -e "s|\"chrome-extension://EXTENSION_ID_PLACEHOLDER/\"|$ALLOWED_ORIGINS|" -e "s|/usr/local/bin/smile-bridge|$BRIDGE_DST|" "$MANIFEST_SRC" > "$nm_dir/$HOST_NAME.json"
  echo "Registered in: $nm_dir"
done

echo ""
echo "Ask your GIT Companion installed."
echo "If you install from Chrome Web Store, you can also run:"
echo "  bash native-host/install.sh $CWS_EXTENSION_ID"
echo "Now reload the extension or restart the browser."
