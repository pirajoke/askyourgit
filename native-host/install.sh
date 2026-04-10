#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$(dirname "$SCRIPT_DIR")"
HOST_NAME="com.smile.ai_install"
BRIDGE_SRC="$SCRIPT_DIR/smile-bridge.py"
BRIDGE_DST="$HOME/.local/bin/smile-bridge"
MANIFEST_SRC="$SCRIPT_DIR/$HOST_NAME.json"

# Accept extension ID as argument, or compute from unpacked path
EXT_ID="${1:-}"

if [ -z "$EXT_ID" ]; then
  # Try auto-detect from installed Chrome/Brave extensions
  for base in \
    "$HOME/Library/Application Support/Google/Chrome/Default/Extensions" \
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions"; do
    if [ -d "$base" ]; then
      for dir in "$base"/*/; do
        for ver in "$dir"*/; do
          if [ -f "$ver/manifest.json" ] && grep -q '"AI Install"' "$ver/manifest.json" 2>/dev/null; then
            EXT_ID="$(basename "$(dirname "$ver")")"
            break 3
          fi
        done
      done
    fi
  done
fi

if [ -z "$EXT_ID" ]; then
  # Compute from unpacked extension path (Chrome's algorithm: SHA256 of path, first 32 chars, a=0...p=15)
  EXT_ID=$(printf '%s' "$EXT_DIR" | shasum -a 256 | head -c 32 | tr '0-9a-f' 'a-p')
  echo "Computed unpacked extension ID: $EXT_ID"
  echo "(If this doesn't match, pass your ID: bash install.sh <id>)"
fi

echo "Extension ID: $EXT_ID"

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
for nm_dir in "${NM_DIRS[@]}"; do
  mkdir -p "$nm_dir"
  sed -e "s/EXTENSION_ID_PLACEHOLDER/$EXT_ID/" -e "s|/usr/local/bin/smile-bridge|$BRIDGE_DST|" "$MANIFEST_SRC" > "$nm_dir/$HOST_NAME.json"
  echo "Registered in: $nm_dir"
done

echo ""
echo "Ask your GIT — Terminal Bridge installed!"
echo "Now load the extension (chrome://extensions → Load unpacked → $EXT_DIR)"
echo "Then restart the browser."
