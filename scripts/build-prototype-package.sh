#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE="$DIST_DIR/askyourgit-prototype"
ZIP="$DIST_DIR/askyourgit-prototype.zip"
DMG="$DIST_DIR/askyourgit-macos.dmg"
DMG_ROOT="$DIST_DIR/askyourgit-dmg-root"

rm -rf "$STAGE" "$ZIP" "$DMG" "$DMG_ROOT"
mkdir -p "$STAGE"

EXTENSION_ITEMS=(
  manifest.json
  background.js
  content.js
  content.css
  popup.html
  popup.js
  popup.css
  README.md
  privacy-policy.html
  index.html
  icons
  native-host
  assets
)

copy_extension_payload() {
  local target="$1"
  mkdir -p "$target"
  for item in "${EXTENSION_ITEMS[@]}"; do
    if [ -e "$ROOT_DIR/$item" ]; then
      cp -R "$ROOT_DIR/$item" "$target/$item"
    fi
  done
  if [ -f "$ROOT_DIR/store/listing.md" ]; then
    mkdir -p "$target/store"
    cp "$ROOT_DIR/store/listing.md" "$target/store/listing.md"
  fi
}

copy_extension_payload "$STAGE"

cat > "$STAGE/INSTALL-PROTOTYPE.md" <<'DOC'
# Ask your GIT Prototype Install

1. Double-click `Ask your GIT Companion.app`.
   - If macOS blocks it, right-click -> Open, or use `install-companion.command`.
2. Open `chrome://extensions`.
3. Enable Developer mode.
4. Click "Load unpacked" and select this folder.
5. Restart Chrome.
6. Open any GitHub, GitLab, or Bitbucket repo and click "Ask your GIT".

The native host is the desktop companion. It lets the extension send install
commands to Terminal.app, iTerm2, or Warp.
DOC

cat > "$STAGE/install-companion.command" <<'SH'
#!/bin/bash
set -e
cd "$(dirname "$0")"
bash native-host/install.sh
echo ""
echo "Ask your GIT Companion is installed."
echo "Next: chrome://extensions -> Load unpacked -> select this folder."
echo ""
read -r -p "Press Enter to close..."
SH
chmod +x "$STAGE/install-companion.command"

APP_DIR="$STAGE/Ask your GIT Companion.app"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RES="$APP_CONTENTS/Resources"
mkdir -p "$APP_MACOS" "$APP_RES"

cat > "$APP_CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Ask your GIT Companion</string>
  <key>CFBundleExecutable</key>
  <string>AskYourGITCompanion</string>
  <key>CFBundleIdentifier</key>
  <string>com.pirajoke.askyourgit.companion</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>Ask your GIT Companion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$APP_MACOS/AskYourGITCompanion" <<'SH'
#!/bin/bash
set -e
APP_MACOS_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_RES_DIR="$(cd "$APP_MACOS_DIR/../Resources" && pwd)"
EXT_DST="$HOME/Library/Application Support/Ask your GIT/extension"
rm -rf "$EXT_DST"
mkdir -p "$(dirname "$EXT_DST")"
cp -R "$APP_RES_DIR/extension" "$EXT_DST"
ASKYOURGIT_EXTENSION_DIR="$EXT_DST" bash "$APP_RES_DIR/native-host/install.sh"
if [ "${ASKYOURGIT_NO_DIALOG:-}" != "1" ]; then
  osascript -e 'display dialog "Ask your GIT Companion is installed.\n\nNext: open chrome://extensions, enable Developer mode, then Load unpacked and select:\n~/Library/Application Support/Ask your GIT/extension" buttons {"OK"} default button "OK" with title "Ask your GIT Companion"'
fi
SH
chmod +x "$APP_MACOS/AskYourGITCompanion"

cp -R "$ROOT_DIR/native-host" "$APP_RES/native-host"
copy_extension_payload "$APP_RES/extension"
find "$APP_RES/native-host" -type d -name "__pycache__" -prune -exec rm -rf {} +

if command -v swiftc >/dev/null 2>&1 && [ -f "$ROOT_DIR/macos-companion/AskYourGITCompanion.swift" ]; then
  if swiftc "$ROOT_DIR/macos-companion/AskYourGITCompanion.swift" -o "$APP_MACOS/AskYourGITCompanion" -framework Cocoa; then
    chmod +x "$APP_MACOS/AskYourGITCompanion"
  fi
fi

if command -v sips >/dev/null 2>&1 && [ -f "$ROOT_DIR/icons/icon128.png" ]; then
  sips -s format icns "$ROOT_DIR/icons/icon128.png" --out "$APP_RES/AppIcon.icns" >/dev/null
fi

if command -v hdiutil >/dev/null 2>&1; then
  mkdir -p "$DMG_ROOT"
  cp -R "$APP_DIR" "$DMG_ROOT/Ask your GIT Companion.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  cat > "$DMG_ROOT/README.txt" <<'DOC'
Ask your GIT

1. Drag Ask your GIT Companion.app to Applications.
2. Open it once.
3. In Chrome, open chrome://extensions and enable Developer mode.
4. Click Load unpacked and select:
   ~/Library/Application Support/Ask your GIT/extension

Chrome Web Store publishing will remove the Load unpacked step later.
DOC
  hdiutil create -volname "Ask your GIT" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$DMG_ROOT"
fi

find "$STAGE" -name ".DS_Store" -delete
find "$STAGE" -type d -name "__pycache__" -prune -exec rm -rf {} +
(
  cd "$DIST_DIR"
  zip -qr "$(basename "$ZIP")" "$(basename "$STAGE")"
)

echo "$ZIP"
if [ -f "$DMG" ]; then
  echo "$DMG"
fi
