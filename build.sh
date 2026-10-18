#!/bin/sh
# Baut FileConvert.app (Menüleisten-App) aus App/main.swift + fileconvert.py
set -e
cd "$(dirname "$0")"
APP=build/FileConvert.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Universal (Apple Silicon + Intel)
universal() { # <out> <swift files...>
    out=$1; shift
    for arch in arm64 x86_64; do
        swiftc -O -target "$arch-apple-macos14.0" "$@" -o "$out.$arch"
    done
    lipo -create "$out.arm64" "$out.x86_64" -output "$out"
    rm "$out.arm64" "$out.x86_64"
}
universal "$APP/Contents/MacOS/FileConvert" App/*.swift
universal "$APP/Contents/Resources/html2pdf" Helper/html2pdf.swift

# Eingebettetes Python (python-build-standalone), damit der Nutzer nichts installieren muss
PBS_TAG=20261013
PBS_VER=3.13.16
CACHE=build-cache
mkdir -p "$CACHE"
for pair in "arm64:aarch64" "x86_64:x86_64"; do
    name=${pair%%:*}; triple=${pair##*:}
    tarball="cpython-$PBS_VER+$PBS_TAG-$triple-apple-darwin-install_only_stripped.tar.gz"
    [ -f "$CACHE/$tarball" ] || curl -fL -o "$CACHE/$tarball" \
        "https://github.com/astral-sh/python-build-standalone/releases/download/$PBS_TAG/$tarball"
    dest="$APP/Contents/Resources/python-$name"
    mkdir -p "$dest"
    tar -xzf "$CACHE/$tarball" -C "$dest" --strip-components=1
    # Unnötiges entfernen (Tests, Tk, IDLE, pip, Header)
    L="$dest/lib/python${PBS_VER%.*}"
    rm -rf "$L/test" "$L/idlelib" "$L/tkinter" "$L/turtledemo" "$L/ensurepip" "$L/site-packages" \
        "$dest/include" "$dest/share" "$dest"/lib/libtcl* "$dest"/lib/libtk* "$dest"/lib/tcl* "$dest"/lib/tk* "$dest"/lib/itcl* "$dest"/lib/thread*
    find "$dest" -name __pycache__ -prune -exec rm -rf {} +
done
# Ghostscript (nur arm64, aus Homebrew); ohne Homebrew-gs bleibt es draussen
if [ -x /opt/homebrew/bin/gs ]; then
    python3 Helper/bundle_gs.py "$APP/Contents/Resources/gs"
else
    echo "WARNUNG: Homebrew-gs fehlt, PDF-Funktionen im Bundle nicht enthalten" >&2
fi
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
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
EOF
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "$APP"
