"""Bilder: jpg, png, webp, heic, tiff, svg, avif, bmp, pdf (sips, cwebp, ffmpeg, WebKit-Helfer)."""
from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

import fileconvert as fc

SIPS_FORMATS = {"jpg": "jpeg", "png": "png", "tiff": "tiff", "bmp": "bmp", "heic": "heic", "avif": "avif", "pdf": "pdf"}
SIPS_READ = {"jpg", "png", "tiff", "bmp", "heic", "avif", "gif"}


def sips_command(src: Path, target: str, out: Path, quality: int) -> list[str]:
    cmd = ["/usr/bin/sips", "-s", "format", SIPS_FORMATS[target]]
    if target in {"jpg", "heic", "avif"}:
        cmd += ["-s", "formatOptions", str(quality)]
    return cmd + [str(src), "--out", str(out)]


def _pivot_png(src: Path, source: str, tmp: Path) -> Path:
    """Beliebiges Quellbild als PNG, wenn sips es nicht direkt schreiben kann."""
    png = tmp / "pivot.png"
    if source in SIPS_READ:
        fc.run(sips_command(src, "png", png, 100))
    elif source == "webp":
        fc.run([fc.require_tool("ffmpeg"), "-y", "-i", str(src), "-frames:v", "1", str(png)])
    elif source == "svg":
        import doctools
        pdf = tmp / "svg.pdf"
        fc.run([doctools.find_helper(), "--root", str(src.parent), str(pdf), str(src)])
        fc.run([fc.require_tool("gs"), "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=png16m", "-r150",
                "-dFirstPage=1", "-dLastPage=1", f"-sOutputFile={png}", str(pdf)])
    else:
        raise fc.ConvertError(f"Bildformat '{source}' nicht lesbar")
    return png


def convert_image(src: Path, source: str, target: str, out: Path, quality: int, keep_metadata: bool) -> Path:
    with tempfile.TemporaryDirectory() as tmp_name:
        tmp = Path(tmp_name)
        direct = source in SIPS_READ and target in SIPS_FORMATS
        if source == "svg" and target == "pdf":
            import doctools
            fc.run([doctools.find_helper(), "--root", str(src.parent), str(out), str(src)])
        elif direct:
            fc.run(sips_command(src, target, out, quality))
        else:
            png = _pivot_png(src, source, tmp)
            if target == "webp":
                fc.run([fc.require_tool("cwebp"), "-q", str(quality), "-quiet", str(png), "-o", str(out)])
            else:
                fc.run(sips_command(png, target, out, quality))
    if not keep_metadata and target != "pdf" and shutil.which("exiftool"):
        fc.run([shutil.which("exiftool"), "-all=", "-overwrite_original", str(out)])
    return out
