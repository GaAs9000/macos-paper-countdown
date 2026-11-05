#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/StatusbarCountdown.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building StatusbarCountdown.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Create VFS overlay to resolve CLT SwiftBridging modulemap duplication on macOS
TMP_VFS_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_VFS_DIR"' EXIT
touch "$TMP_VFS_DIR/empty.modulemap"
cat << EOF > "$TMP_VFS_DIR/vfs.yaml"
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift",
      "type": "directory",
      "contents": [
        {
          "name": "module.modulemap",
          "type": "file",
          "external-contents": "$TMP_VFS_DIR/empty.modulemap"
        }
      ]
    }
  ]
}
EOF

# Generate modern macOS Squircle AppIcon.icns
ICONSET_DIR="$TMP_VFS_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

cat << 'EOF' > "$TMP_VFS_DIR/gen_icon.swift"
import Cocoa

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
    let inset = CGFloat(px) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = cardRect.width * 0.225

    let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.36, green: 0.24, blue: 0.92, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    // Draw timer symbol in white
    if let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.46, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let configured = symbol.withSymbolConfiguration(config) {
            let symSize = configured.size
            let symRect = NSRect(
                x: ( CGFloat(px) - symSize.width ) / 2.0,
                y: ( CGFloat(px) - symSize.height ) / 2.0,
                width: symSize.width,
                height: symSize.height
            )
            configured.draw(in: symRect)
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    }
}
EOF

swiftc -target arm64-apple-macosx14.0 -vfsoverlay "$TMP_VFS_DIR/vfs.yaml" "$TMP_VFS_DIR/gen_icon.swift" -o "$TMP_VFS_DIR/gen_icon"
"$TMP_VFS_DIR/gen_icon" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

# Compile main application binary with optimizations
swiftc -O -target arm64-apple-macosx14.0 -vfsoverlay "$TMP_VFS_DIR/vfs.yaml" \
    "$PROJECT_DIR/StatusbarCountdown/CCFDeadlineService.swift" \
    "$PROJECT_DIR/StatusbarCountdown/AppDelegate.swift" \
    "$PROJECT_DIR/StatusbarCountdown/PreferencesWindow.swift" \
    "$PROJECT_DIR/StatusbarCountdown/ShakeWindow.swift" \
    -o "$MACOS_DIR/StatusbarCountdown"

# Generate resolved Info.plist
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>StatusbarCountdown</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>me.bbrks.dev.StatusbarCountdown</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>StatusbarCountdown</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>2</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2015-2026 Ben Brooks. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# Ad-hoc code sign the bundle
codesign --force --deep --sign - "$APP_BUNDLE"

# Copy to project root for quick access
rm -rf "$PROJECT_DIR/StatusbarCountdown.app"
cp -R "$APP_BUNDLE" "$PROJECT_DIR/StatusbarCountdown.app"

echo "✅ Built successfully:"
echo "   - $PROJECT_DIR/StatusbarCountdown.app"
echo "   - $APP_BUNDLE"
