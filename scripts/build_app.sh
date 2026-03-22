#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="dist/SkillManagerApp.app"
ICONSET_DIR=".build/icon.iconset"
ICON_ICNS=".build/AppIcon.icns"
ICON_SWIFT=".build/gen_app_icon.swift"

rm -rf "$APP_DIR" "$ICONSET_DIR" "$ICON_ICNS"
mkdir -p "$ICONSET_DIR" "dist" ".build"

cat > "$ICON_SWIFT" <<'SWIFT'
import AppKit

let baseSizes = [16, 32, 128, 256, 512]
let outDir = URL(fileURLWithPath: ".build/icon.iconset", isDirectory: true)

func drawIcon(px: Int) -> NSImage {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let card = bounds.insetBy(dx: inset, dy: inset)
    let radius = size * 0.22

    let bgPath = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
    let c1 = NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.98, alpha: 1)
    let c2 = NSColor(calibratedRed: 0.53, green: 0.23, blue: 0.93, alpha: 1)
    NSGradient(starting: c1, ending: c2)?.draw(in: bgPath, angle: -38)

    let highlight = NSBezierPath(roundedRect: CGRect(x: card.minX + size*0.06, y: card.midY, width: card.width*0.72, height: card.height*0.36), xRadius: size*0.14, yRadius: size*0.14)
    NSColor.white.withAlphaComponent(0.10).setFill()
    highlight.fill()

    let glyphW = size * 0.46
    let glyphH = size * 0.22
    let gx = (size - glyphW) / 2
    let gy = (size - glyphH) / 2 - size*0.02
    let glyphR = size * 0.045

    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: CGRect(x: gx, y: gy, width: glyphW, height: glyphH), xRadius: glyphR, yRadius: glyphR).fill()

    NSColor.white.withAlphaComponent(0.80).setFill()
    NSBezierPath(roundedRect: CGRect(x: gx + size*0.035, y: gy + size*0.14, width: glyphW*0.70, height: glyphH*0.72), xRadius: glyphR*0.8, yRadius: glyphR*0.8).fill()

    let s = size * 0.085
    let cx = gx + glyphW - s*0.05
    let cy = gy + glyphH + s*0.70
    let star = NSBezierPath()
    star.move(to: CGPoint(x: cx, y: cy + s))
    star.line(to: CGPoint(x: cx + s*0.30, y: cy + s*0.30))
    star.line(to: CGPoint(x: cx + s, y: cy))
    star.line(to: CGPoint(x: cx + s*0.30, y: cy - s*0.30))
    star.line(to: CGPoint(x: cx, y: cy - s))
    star.line(to: CGPoint(x: cx - s*0.30, y: cy - s*0.30))
    star.line(to: CGPoint(x: cx - s, y: cy))
    star.line(to: CGPoint(x: cx - s*0.30, y: cy + s*0.30))
    star.close()
    NSColor.white.withAlphaComponent(0.92).setFill()
    star.fill()

    let strokePath = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    strokePath.lineWidth = max(1, size * 0.01)
    strokePath.stroke()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

for pt in baseSizes {
    savePNG(drawIcon(px: pt), to: outDir.appendingPathComponent("icon_\(pt)x\(pt).png"))
    savePNG(drawIcon(px: pt * 2), to: outDir.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
SWIFT

swift "$ICON_SWIFT"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"

swift build -c release --product SkillManagerApp

BIN_SRC=".build/arm64-apple-macosx/release/SkillManagerApp"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_SRC" "$APP_DIR/Contents/MacOS/SkillManagerApp"
cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy SwiftPM resource bundles so localization/assets work in packaged app.
for bundle in .build/arm64-apple-macosx/release/*.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$APP_DIR/Contents/Resources/"
    fi
done

chmod +x "$APP_DIR/Contents/MacOS/SkillManagerApp"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>SkillManagerApp</string>
  <key>CFBundleIdentifier</key>
  <string>ai.openclaw.skill-manager</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SkillKit</string>
  <key>CFBundleDisplayName</key>
  <string>SkillKit</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Built app: $APP_DIR"

# Finder icon cache verification
# If Finder shows a white/generic icon after build, run the following to flush the cache:
#   killall Finder
#   killall Dock
#   sudo find /private/var/folders -name com.apple.dock.iconcache -delete 2>/dev/null || true
#   sudo find /private/var/folders -name com.apple.iconservices -delete 2>/dev/null || true
#
# To verify the icon is embedded correctly:
echo ""
echo "Verifying icon embedding..."
if [ -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]; then
    echo "  AppIcon.icns present"
else
    echo "  ERROR: AppIcon.icns missing from Resources"
    exit 1
fi
PLIST_ICON=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo "")
if [ "$PLIST_ICON" = "AppIcon" ]; then
    echo "  CFBundleIconFile = AppIcon (OK)"
else
    echo "  WARNING: CFBundleIconFile not set correctly (got: '$PLIST_ICON')"
fi

echo ""
echo "If Finder still shows a white icon, refresh icon cache:"
echo "  killall Finder && killall Dock"
