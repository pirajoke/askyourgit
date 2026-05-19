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

build_app_icon() {
  local iconset="$DIST_DIR/AppIcon.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"

  if python3 - "$iconset" <<'PY'
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

iconset = sys.argv[1]
size = 1024

canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
shadow_mask = Image.new("L", (size, size), 0)
mask_draw = ImageDraw.Draw(shadow_mask)
mask_draw.rounded_rectangle((92, 92, 932, 932), radius=210, fill=210)
shadow = Image.new("RGBA", (size, size), (0, 0, 0, 110))
shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(34)))
canvas.alpha_composite(shadow, (0, 18))

gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
pixels = gradient.load()
start = (205, 112, 50)
end = (58, 22, 15)
for y in range(size):
    for x in range(size):
        t = (x * 0.38 + y * 0.62) / size
        t = max(0, min(1, t))
        pixels[x, y] = tuple(round(start[i] * (1 - t) + end[i] * t) for i in range(3)) + (255,)

mask = Image.new("L", (size, size), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.rounded_rectangle((92, 92, 932, 932), radius=210, fill=255)
canvas.alpha_composite(Image.composite(gradient, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask))

overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
overlay_draw = ImageDraw.Draw(overlay)
overlay_draw.rounded_rectangle((138, 126, 886, 904), radius=184, fill=(255, 255, 255, 20), outline=(255, 255, 255, 38), width=3)
overlay_draw.rounded_rectangle((172, 162, 852, 468), radius=150, fill=(255, 255, 255, 18))
canvas.alpha_composite(overlay)

draw = ImageDraw.Draw(canvas)

white = (255, 255, 255, 238)
draw.line([(354, 664), (512, 506), (674, 664)], fill=white, width=74)
for cx, cy in [(354, 664), (512, 506), (674, 664)]:
    draw.ellipse((cx - 72, cy - 72, cx + 72, cy + 72), fill=white)

bubble = (255, 255, 255, 246)
draw.rounded_rectangle((600, 230, 834, 394), radius=62, fill=bubble)
draw.polygon([(674, 384), (724, 384), (676, 450)], fill=bubble)

font_path = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
try:
    font = ImageFont.truetype(font_path, 154)
except Exception:
    font = ImageFont.load_default()
text = "?"
bounds = draw.textbbox((0, 0), text, font=font)
tw = bounds[2] - bounds[0]
th = bounds[3] - bounds[1]
draw.text((717 - tw / 2, 306 - th / 2 - 8), text, font=font, fill=(74, 31, 20, 255))

sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}
for name, target in sizes.items():
    canvas.resize((target, target), Image.Resampling.LANCZOS).save(os.path.join(iconset, name))
PY
  then
    iconutil -c icns "$iconset" -o "$APP_RES/AppIcon.icns"
  elif command -v sips >/dev/null 2>&1 && [ -f "$ROOT_DIR/icons/icon128.png" ]; then
    sips -s format icns "$ROOT_DIR/icons/icon128.png" --out "$APP_RES/AppIcon.icns" >/dev/null
  fi

  rm -rf "$iconset"
}

build_dmg_background() {
  local output="$1"
  python3 - "$output" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

output = sys.argv[1]
width, height = 900, 520
img = Image.new("RGB", (width, height), "#f8fafc")
draw = ImageDraw.Draw(img)

for y in range(height):
    t = y / max(1, height - 1)
    r = round(248 * (1 - t) + 236 * t)
    g = round(250 * (1 - t) + 242 * t)
    b = round(252 * (1 - t) + 247 * t)
    draw.line((0, y, width, y), fill=(r, g, b))

accent = Image.new("RGBA", (width, height), (0, 0, 0, 0))
ad = ImageDraw.Draw(accent)
ad.ellipse((540, -180, 1040, 320), fill=(56, 189, 248, 26))
ad.ellipse((-180, 250, 260, 690), fill=(124, 58, 237, 18))
accent = accent.filter(ImageFilter.GaussianBlur(18))
img = Image.alpha_composite(img.convert("RGBA"), accent)
draw = ImageDraw.Draw(img)

font_bold = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
font_regular = "/System/Library/Fonts/Supplemental/Arial.ttf"
try:
    title_font = ImageFont.truetype(font_bold, 30)
    note_font = ImageFont.truetype(font_regular, 17)
    small_font = ImageFont.truetype(font_regular, 13)
except Exception:
    title_font = note_font = small_font = ImageFont.load_default()

def centered(text, y, font, fill):
    box = draw.textbbox((0, 0), text, font=font)
    draw.text(((width - (box[2] - box[0])) / 2, y), text, font=font, fill=fill)

centered("Ask your GIT", 34, title_font, "#17202e")
centered("Drag the companion into Applications", 74, note_font, "#64748b")

draw.line((350, 252, 550, 252), fill="#a35a2b", width=5)
draw.line((550, 252, 528, 236), fill="#a35a2b", width=5)
draw.line((550, 252, 528, 268), fill="#a35a2b", width=5)
centered("Drag me in", 210, note_font, "#a35a2b")

footer = "Open once, then load: ~/Library/Application Support/Ask your GIT/extension"
box = draw.textbbox((0, 0), footer, font=small_font)
pad_x, pad_y = 18, 10
fw = box[2] - box[0] + pad_x * 2
fh = box[3] - box[1] + pad_y * 2
fx = (width - fw) / 2
fy = height - 72
draw.rounded_rectangle((fx, fy, fx + fw, fy + fh), radius=12, fill="#ffffff", outline="#d8e0ea")
draw.text((fx + pad_x, fy + pad_y - 1), footer, font=small_font, fill="#334155")

img.convert("RGB").save(output)
PY
}

write_dmg_ds_store() {
  local dmg_root="$1"
  python3 - "$dmg_root" <<'PY'
import os
import sys

try:
    from ds_store import DSStore
except Exception:
    sys.exit(1)

root = sys.argv[1]
store_path = os.path.join(root, ".DS_Store")

with DSStore.open(store_path, "w+") as store:
    store["."]["bwsp"] = {
        "ContainerShowSidebar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "WindowBounds": "{{120, 90}, {900, 520}}",
        "WindowViewStyle": "icnv",
    }
    store["."]["icvp"] = {
        "arrangeBy": "none",
        "backgroundColorBlue": 0.98,
        "backgroundColorGreen": 0.96,
        "backgroundColorRed": 0.94,
        "backgroundType": 1,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": 116.0,
        "labelOnBottom": True,
        "showIconPreview": True,
        "showItemInfo": False,
        "textSize": 13.0,
        "viewOptionsVersion": 1,
    }
    store["Ask your GIT Companion.app"]["Iloc"] = (245, 270)
    store["Applications"]["Iloc"] = (655, 270)
    store.flush()
PY
}

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

build_app_icon

if command -v hdiutil >/dev/null 2>&1; then
  mkdir -p "$DMG_ROOT"
  mkdir -p "$DMG_ROOT/.background"
  cp -R "$APP_DIR" "$DMG_ROOT/Ask your GIT Companion.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  build_dmg_background "$DMG_ROOT/.background/dmg-background.png" || true
  write_dmg_ds_store "$DMG_ROOT" || true
  if [ -f "$APP_RES/AppIcon.icns" ]; then
    cp "$APP_RES/AppIcon.icns" "$DMG_ROOT/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
      SetFile -a C "$DMG_ROOT" || true
    fi
  fi

  RW_DMG="$DIST_DIR/askyourgit-macos-rw.dmg"
  MOUNT_DIR="$(mktemp -d /tmp/askyourgit-dmg.XXXXXX)"
  if hdiutil create -volname "Ask your GIT" -srcfolder "$DMG_ROOT" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null &&
     hdiutil attach "$RW_DMG" -nobrowse -mountpoint "$MOUNT_DIR" >/dev/null; then
    if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
      SetFile -a C "$MOUNT_DIR" || true
    fi

    osascript >/dev/null 2>&1 <<OSA || true
tell application "Finder"
  tell disk "Ask your GIT"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 90, 1020, 610}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 116
    set background picture of viewOptions to (POSIX file "$MOUNT_DIR/.background/dmg-background.png" as alias)
    set position of item "Ask your GIT Companion.app" of container window to {245, 270}
    set position of item "Applications" of container window to {655, 270}
    update without registering applications
    delay 3
    close
    open
    delay 2
    close
    eject
  end tell
end tell
OSA

    sync
    hdiutil detach "$MOUNT_DIR" >/dev/null || hdiutil detach "$MOUNT_DIR" -force >/dev/null || true
    hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
  else
    hdiutil create -volname "Ask your GIT" -srcfolder "$DMG_ROOT" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
  fi
  rm -f "$RW_DMG"
  rm -rf "$MOUNT_DIR"
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
