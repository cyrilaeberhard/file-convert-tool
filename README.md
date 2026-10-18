<p align="center"><img src="Assets/icon_1024.png" width="160" alt="FileConvert"></p>

# FileConvert

macOS menu-bar app to convert, compress and edit files (images, PDFs, documents, audio/video, archives, spreadsheets, markup).

## Download

Get `FileConvert.dmg` from the [latest release](../../releases/latest), open it and drag **FileConvert** to **Applications**.

The app is not notarized. On first launch: right-click the app, choose **Open**, confirm. Or run:

```sh
xattr -dr com.apple.quarantine /Applications/FileConvert.app
```

Requires macOS 14+ on Apple Silicon. Everything is bundled (Python, Ghostscript, ffmpeg, cwebp, exiftool): nothing else to install. Intel Macs are not supported by the bundled tools.

Bundled third-party tools keep their own licenses: Ghostscript (AGPL, https://ghostscript.com), ffmpeg (GPL, https://ffmpeg.org), libwebp/cwebp (BSD), ExifTool (Perl Artistic/GPL, https://exiftool.org), Python (PSF).

## Build from source

```sh
sh build.sh
```

Needs Xcode command line tools (`swiftc`) and `brew install ghostscript ffmpeg webp exiftool` (they get bundled). Output: `build/FileConvert.app`.

## Tests

```sh
python3 -m pytest
```
