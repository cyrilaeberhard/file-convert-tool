"""PDF-Werkzeuge über Ghostscript: zusammenfügen, komprimieren, Seiten als Bild."""
from __future__ import annotations

from pathlib import Path

import fileconvert as fc

PRESETS = {"low": "/screen", "medium": "/ebook", "high": "/printer"}
IMAGE_DEVICES = {"png": "png16m", "jpg": "jpeg"}


def _gs(*args: str) -> None:
    fc.run([fc.require_tool("gs"), "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", *args])


def _check_pdfs(files: list[Path]) -> None:
    for f in files:
        if not f.is_file():
            raise fc.ConvertError(f"Datei fehlt: {f}")
        if f.suffix.lower() != ".pdf":
            raise fc.ConvertError(f"Keine PDF: {f.name}")


def merge_pdfs(files: list[Path], out: Path) -> Path:
    if len(files) < 2:
        raise fc.ConvertError("Zum Zusammenfügen mindestens 2 PDFs nötig")
    _check_pdfs(files)
    if out.resolve() in {f.resolve() for f in files}:
        raise fc.ConvertError("Ausgabe darf keine Eingabe überschreiben")
    _gs("-sDEVICE=pdfwrite", f"-sOutputFile={out}", *map(str, files))
    return out


def compress_pdf(src: Path, out: Path | None = None, level: str = "medium") -> Path:
    if level not in PRESETS:
        raise fc.ConvertError(f"Stufe '{level}' unbekannt. Erlaubt: {', '.join(PRESETS)}")
    _check_pdfs([src])
    out = out or src.with_name(f"{src.stem}_compressed.pdf")
    if out.resolve() == src.resolve():
        raise fc.ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    _gs("-sDEVICE=pdfwrite", f"-dPDFSETTINGS={PRESETS[level]}", f"-sOutputFile={out}", str(src))
    return out


def pdf_to_images(src: Path, fmt: str = "png", dpi: int = 150, out_dir: Path | None = None) -> Path:
    if fmt not in IMAGE_DEVICES:
        raise fc.ConvertError(f"Bildformat '{fmt}' unbekannt. Erlaubt: {', '.join(IMAGE_DEVICES)}")
    if not 36 <= dpi <= 600:
        raise fc.ConvertError("DPI muss zwischen 36 und 600 liegen")
    _check_pdfs([src])
    out_dir = out_dir or src.with_name(f"{src.stem}_pages")
    out_dir.mkdir(parents=True, exist_ok=True)
    _gs(f"-sDEVICE={IMAGE_DEVICES[fmt]}", f"-r{dpi}",
        f"-sOutputFile={out_dir / ('page-%03d.' + fmt)}", str(src))
    return out_dir


def split_pdf(src: Path, out_dir: Path | None = None) -> Path:
    """Jede Seite als eigene PDF in einen Ordner neben dem Original."""
    _check_pdfs([src])
    out_dir = out_dir or src.with_name(f"{src.stem}_split")
    out_dir.mkdir(parents=True, exist_ok=True)
    _gs("-sDEVICE=pdfwrite", f"-sOutputFile={out_dir / 'page-%03d.pdf'}", str(src))
    return out_dir
