#!/bin/sh
# Baut FileConvert.app (Menüleisten-App) aus App/main.swift + fileconvert.py
set -e
cd "$(dirname "$0")"
APP=build/FileConvert.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O App/*.swift -o "$APP/Contents/MacOS/FileConvert"
swiftc -O Helper/html2pdf.swift -o "$APP/Contents/Resources/html2pdf"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
for f in *.py; do case "$f" in test_*|check_matrix.py) ;; *) cp "$f" "$APP/Contents/Resources/" ;; esac; done
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FileConvert</string>
<key>CFBundleIdentifier</key><string>local.fileconvert</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>FileConvert</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
EOF
codesign --force --sign - "$APP" 2>/dev/null || true
echo "$APP"
