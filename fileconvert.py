#!/usr/bin/env python3
"""Kleines Konvertier-CLI: Bild, Video, Audio, Metadaten entfernen.

Nutzung:
    fileconvert.py convert INPUT FORMAT [-o OUT] [-q QUALITAET]
    fileconvert.py strip INPUT [-o OUT]
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

IMAGE_FORMATS = {"jpg", "jpeg", "png", "webp", "gif", "tiff", "bmp", "heic"}
VIDEO_FORMATS = {"mp4", "mov", "mkv", "webm", "avi"}
AUDIO_FORMATS = {"mp3", "wav", "flac", "aac", "m4a", "ogg"}
SUBTITLE_FORMATS = {"srt", "vtt", "ass", "ssa"}
ALL_FORMATS = IMAGE_FORMATS | VIDEO_FORMATS | AUDIO_FORMATS | SUBTITLE_FORMATS


class ConvertError(Exception):
    pass


INSTALL_HINTS = {"rar": "brew install --cask rar", "ffprobe": "brew install ffmpeg"}


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        hint = INSTALL_HINTS.get(name, f"brew install {name}")
        raise ConvertError(f"'{name}' nicht gefunden. Installieren: {hint}")
    return path


def run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        tail = result.stderr.strip().splitlines()[-3:]
        raise ConvertError(f"{Path(cmd[0]).name} fehlgeschlagen: " + " | ".join(tail))


def build_command(src: Path, fmt: str, out: Path, quality: int, keep_metadata: bool = True) -> list[str]:
    """Baut den Befehl. Reine Funktion, ohne Tool-Aufruf."""
    src_fmt = src.suffix.lower().lstrip(".")
    meta = [] if keep_metadata else ["-map_metadata", "-1"]
    if fmt == "webp" and src_fmt in {"jpg", "jpeg", "png", "tiff"}:
        keep = ["-metadata", "all"] if keep_metadata else []
        return ["cwebp", "-q", str(quality), *keep, str(src), "-o", str(out)]
    if fmt in SUBTITLE_FORMATS:
        if src_fmt not in SUBTITLE_FORMATS:
            raise ConvertError(f"'{src_fmt}' ist keine Untertitel-Datei")
        return ["ffmpeg", "-y", "-i", str(src), *meta, str(out)]
    if fmt in IMAGE_FORMATS:
        qscale = max(2, min(31, round(31 - quality * 0.29)))
        return ["ffmpeg", "-y", "-i", str(src), *meta, "-q:v", str(qscale), "-frames:v", "1", str(out)]
    if fmt in VIDEO_FORMATS:
        crf = max(18, min(35, round(51 - quality * 0.33)))
        return ["ffmpeg", "-y", "-i", str(src), *meta, "-crf", str(crf), str(out)]
    if fmt in AUDIO_FORMATS:
        return ["ffmpeg", "-y", "-i", str(src), *meta, "-vn", str(out)]
    raise ConvertError(f"Format '{fmt}' nicht unterstützt")


def convert(src: Path, fmt: str, out: Path | None, quality: int, keep_metadata: bool = True) -> Path:
    fmt = fmt.lower().lstrip(".")
    if fmt not in ALL_FORMATS:
        raise ConvertError(f"Format '{fmt}' nicht unterstützt. Erlaubt: {', '.join(sorted(ALL_FORMATS))}")
    if not src.is_file():
        raise ConvertError(f"Datei fehlt: {src}")
    if not 1 <= quality <= 100:
        raise ConvertError("Qualität muss 1-100 sein")
    out = out or src.with_suffix(f".{fmt}")
    if out.resolve() == src.resolve():
        raise ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    cmd = build_command(src, fmt, out, quality, keep_metadata)
    cmd[0] = require_tool(cmd[0])
    run(cmd)
    return out


def strip_metadata(src: Path, out: Path | None) -> Path:
    if not src.is_file():
        raise ConvertError(f"Datei fehlt: {src}")
    out = out or src.with_name(f"{src.stem}_clean{src.suffix}")
    if out.resolve() == src.resolve():
        raise ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    shutil.copy2(src, out)
    try:
        run([require_tool("exiftool"), "-all=", "-overwrite_original", str(out)])
    except ConvertError:
        out.unlink(missing_ok=True)
        raise
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_conv = sub.add_parser("convert", help="Datei konvertieren")
    p_conv.add_argument("input", type=Path)
    p_conv.add_argument("format")
    p_conv.add_argument("-o", "--output", type=Path)
    p_conv.add_argument("-q", "--quality", type=int, default=80)
    p_conv.add_argument("--no-metadata", action="store_true", help="Metadaten nicht übernehmen")
    p_strip = sub.add_parser("strip", help="Metadaten entfernen (Kopie)")
    p_strip.add_argument("input", type=Path)
    p_strip.add_argument("-o", "--output", type=Path)
    p_comp = sub.add_parser("compress", help="Auf Zielgröße komprimieren")
    p_comp.add_argument("input", type=Path)
    p_comp.add_argument("target_mb", type=float)
    p_comp.add_argument("-o", "--output", type=Path)
    p_merge = sub.add_parser("pdf-merge", help="PDFs zusammenfügen")
    p_merge.add_argument("output", type=Path)
    p_merge.add_argument("inputs", type=Path, nargs="+")
    p_pcomp = sub.add_parser("pdf-compress", help="PDF komprimieren")
    p_pcomp.add_argument("input", type=Path)
    p_pcomp.add_argument("-l", "--level", default="medium")
    p_pcomp.add_argument("-o", "--output", type=Path)
    p_recomp = sub.add_parser("recompress", help="Bild neu kodieren (Qualität, optional verkleinern)")
    p_recomp.add_argument("input", type=Path)
    p_recomp.add_argument("format")
    p_recomp.add_argument("-q", "--quality", type=int, default=75)
    p_recomp.add_argument("--max-edge", type=int, default=0)
    p_recomp.add_argument("-o", "--output", type=Path, required=True)
    p_psplit = sub.add_parser("pdf-split", help="PDF in Einzelseiten teilen")
    p_psplit.add_argument("input", type=Path)
    p_pimg = sub.add_parser("pdf-images", help="PDF-Seiten als Bilder")
    p_pimg.add_argument("input", type=Path)
    p_pimg.add_argument("-f", "--format", default="png")
    p_pimg.add_argument("-d", "--dpi", type=int, default=150)
    p_zip = sub.add_parser("zip", help="Dateien in ZIP packen")
    p_zip.add_argument("inputs", type=Path, nargs="+")
    p_rar = sub.add_parser("rar", help="Dateien in RAR packen (braucht 'rar')")
    p_rar.add_argument("inputs", type=Path, nargs="+")
    p_unp = sub.add_parser("unpack", help="Archiv entpacken")
    p_unp.add_argument("input", type=Path)
    p_crop = sub.add_parser("crop", help="Bild zuschneiden")
    p_crop.add_argument("input", type=Path)
    p_crop.add_argument("width", type=int)
    p_crop.add_argument("height", type=int)
    p_crop.add_argument("-x", type=int, default=0)
    p_crop.add_argument("-y", type=int, default=0)
    p_size = sub.add_parser("resize", help="Bildgröße ändern")
    p_size.add_argument("input", type=Path)
    p_size.add_argument("-W", "--width", type=int)
    p_size.add_argument("-H", "--height", type=int)
    p_col = sub.add_parser("collage", help="Bilder zu einer Collage")
    p_col.add_argument("inputs", type=Path, nargs="+")
    p_chan = sub.add_parser("channels", help="Audiokanäle umwandeln")
    p_chan.add_argument("input", type=Path)
    p_chan.add_argument("mode", help="mono, stereo, left, right")
    p_sil = sub.add_parser("silence", help="Stille erkennen")
    p_sil.add_argument("input", type=Path)
    p_sil.add_argument("-t", "--threshold", type=float, default=-40)
    p_sil.add_argument("-d", "--duration", type=float, default=0.5)
    p_wave = sub.add_parser("waveform", help="Waveform als PNG")
    p_wave.add_argument("input", type=Path)
    sub.add_parser("caps", help="Unterstützte Konvertierungen als JSON")
    p_doc = sub.add_parser("doc-pdf", help="Dokument oder EPUB zu PDF")
    p_doc.add_argument("input", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.cmd == "recompress":
            import dispatcher
            result = dispatcher.recompress_image(args.input, args.format, args.quality, args.output, args.max_edge)
        elif args.cmd == "caps":
            import matrix
            print(json.dumps(matrix.caps()))
            return 0
        elif args.cmd == "doc-pdf":
            import doctools
            result = (doctools.epub_to_pdf(args.input) if args.input.suffix.lower() == ".epub"
                      else doctools.office_to_pdf(args.input))
        elif args.cmd == "silence":
            import audiotools
            spans = audiotools.detect_silence(args.input, args.threshold, args.duration)
            lines = [f"{s:.2f}s - {'Ende' if e is None else f'{e:.2f}s'}" for s, e in spans]
            result = f"{len(spans)} Stille(n): " + "; ".join(lines) if spans else "Keine Stille gefunden"
        elif args.cmd in {"channels", "waveform"}:
            import audiotools
            result = (audiotools.convert_channels(args.input, args.mode) if args.cmd == "channels"
                      else audiotools.waveform(args.input))
        elif args.cmd in {"crop", "resize", "collage"}:
            import imageedit
            if args.cmd == "crop":
                result = imageedit.crop_image(args.input, args.width, args.height, args.x, args.y)
            elif args.cmd == "resize":
                result = imageedit.resize_image(args.input, args.width, args.height)
            else:
                result = imageedit.collage(args.inputs)
        elif args.cmd in {"zip", "rar", "unpack"}:
            import archives
            if args.cmd == "zip":
                result = archives.pack_zip(args.inputs)
            elif args.cmd == "rar":
                result = archives.pack_rar(args.inputs)
            else:
                result = archives.extract(args.input)
        elif args.cmd.startswith("pdf-"):
            import pdftools
            if args.cmd == "pdf-merge":
                result = pdftools.merge_pdfs(args.inputs, args.output)
            elif args.cmd == "pdf-compress":
                result = pdftools.compress_pdf(args.input, args.output, args.level)
            elif args.cmd == "pdf-split":
                result = pdftools.split_pdf(args.input)
            else:
                result = pdftools.pdf_to_images(args.input, args.format, args.dpi)
        elif args.cmd == "convert":
            import dispatcher
            result = dispatcher.convert_any(args.input, args.format, args.quality, not args.no_metadata, args.output)
        elif args.cmd == "compress":
            import compress as comp
            result = comp.compress(args.input, args.target_mb, args.output)
        else:
            result = strip_metadata(args.input, args.output)
    except ConvertError as err:
        print(f"Fehler: {err}", file=sys.stderr)
        return 1
    print(result)
    return 0


if __name__ == "__main__":
    # Als Modul neu importieren, damit ConvertError aus Untermodulen dieselbe Klasse ist.
    import fileconvert

    sys.exit(fileconvert.main())
