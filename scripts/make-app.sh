#!/bin/bash
# Builds Meatproxy.app (D54): the executable, its resources in Contents/Resources, the brand icon as AppIcon.icns, an
# Info.plist with the bundle id dev.tuinstra.meatproxy, and an ad-hoc signature (for this Mac; not notarised).
# Usage: scripts/make-app.sh [release|debug]   → build/Meatproxy.app
set -euo pipefail
cd "$(dirname "$0")/.."
config="${1:-release}"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)"
app="build/Meatproxy.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Meatproxy" "$app/Contents/MacOS/Meatproxy"
for b in Meatproxy_Meatproxy.bundle Meatproxy_FactoryScenes.bundle; do cp -R "$bin/$b" "$app/Contents/Resources/"; done

# the icon: every size macOS asks for, from the brand's 1024 px icon
iconset="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$iconset"
src="Sources/Meatproxy/Brand/AppIcon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$src" --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$src" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

version="0.1.$(git rev-list --count HEAD 2>/dev/null || echo 0)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.tuinstra.meatproxy</string>
  <key>CFBundleName</key><string>Meatproxy</string>
  <key>CFBundleDisplayName</key><string>Meatproxy</string>
  <key>CFBundleExecutable</key><string>Meatproxy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Tuinstra Meatproxy. Approved by a human. Reviewed by nobody.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$app" >/dev/null
echo "$app ($version)"
