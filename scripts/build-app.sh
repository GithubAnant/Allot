#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product Quota --arch arm64 --arch x86_64
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
mkdir -p "$PWD/dist"
staging=$(mktemp -d "$PWD/dist/ration-package.XXXXXX")
app="$staging/Ration.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$staging/Quota.iconset"
cp "$binary_dir/Quota" "$app/Contents/MacOS/Quota"
ditto "$binary_dir/Quota_Quota.bundle" "$app/Contents/Resources/Quota_Quota.bundle"
cp docs/T3-LICENSE.txt docs/GEIST-LICENSE.txt docs/PROVIDER-ICONS-LICENSE.txt "$app/Contents/Resources/"
swift scripts/AppIcon.swift "$staging/Quota.iconset"
iconutil -c icns "$staging/Quota.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Ration</string>
<key>CFBundleDisplayName</key><string>Ration</string>
<key>CFBundleIdentifier</key><string>app.quota.monitor</string>
<key>CFBundleExecutable</key><string>Quota</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Ration. Contains MIT-licensed T3 Code usage logic, copyright 2026 T3 Tools Inc.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --strict "$app"
if [[ -d "$PWD/dist/Ration.app" ]]; then
  mv "$PWD/dist/Ration.app" "$staging/previous-Ration.app"
fi
mv "$app" "$PWD/dist/Ration.app"
print "Built $PWD/dist/Ration.app"
