#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product Quota --arch arm64 --arch x86_64
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
mkdir -p "$PWD/dist"
staging=$(mktemp -d "$PWD/dist/allot-package.XXXXXX")
app="$staging/Allot.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$staging/Quota.iconset"
cp "$binary_dir/Quota" "$app/Contents/MacOS/Quota"
ditto "$binary_dir/Quota_Quota.bundle" "$app/Contents/Resources/Quota_Quota.bundle"
cp docs/T3-LICENSE.txt docs/GEIST-LICENSE.txt docs/PROVIDER-ICONS-LICENSE.txt docs/LITELLM-LICENSE.txt "$app/Contents/Resources/"
swiftc -O -parse-as-library Sources/Quota/AllotMark.swift scripts/AppIcon.swift -o "$staging/render-icon"
"$staging/render-icon" "$staging/Quota.iconset"
iconutil -c icns "$staging/Quota.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Allot</string>
<key>CFBundleDisplayName</key><string>Allot</string>
<key>CFBundleIdentifier</key><string>app.quota.monitor</string>
<key>CFBundleExecutable</key><string>Quota</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>es</string><string>fr</string><string>de</string><string>hi</string><string>ja</string><string>zh-Hans</string></array>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Allot. Contains MIT-licensed T3 Code usage logic, copyright 2026 T3 Tools Inc.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --strict "$app"
if [[ -d "$PWD/dist/Allot.app" ]]; then
  mv "$PWD/dist/Allot.app" "$staging/previous-Allot.app"
fi
mv "$app" "$PWD/dist/Allot.app"
print "Built $PWD/dist/Allot.app"

ditto -c -k --sequesterRsrc --keepParent "$PWD/dist/Allot.app" "$PWD/dist/Allot.zip"
(cd "$PWD/dist" && shasum -a 256 Allot.zip > Allot.zip.sha256)
print "Share $PWD/dist/Allot.zip with its SHA-256 checksum."
