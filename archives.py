"""Archive: packen (zip, rar) und entpacken (zip, rar, 7z, tar, ...)."""
from __future__ import annotations

import zipfile
from pathlib import Path

import fileconvert as fc

EXTRACT_SUFFIXES = {".zip", ".rar", ".7z", ".tar", ".gz", ".tgz", ".bz2", ".xz"}


def _unique(path: Path) -> Path:
    """Hängt -2, -3 ... an, damit nichts überschrieben wird."""
    candidate, n = path, 2
    while candidate.exists():
        candidate = path.with_name(f"{path.stem}-{n}{path.suffix}")
        n += 1
    return candidate


def _check_inputs(files: list[Path]) -> None:
    if not files:
        raise fc.ConvertError("Keine Dateien angegeben")
    for f in files:
        if not f.exists():
            raise fc.ConvertError(f"Datei fehlt: {f}")


def pack_zip(files: list[Path], out: Path | None = None) -> Path:
    _check_inputs(files)
    out = _unique(out or files[0].parent / (f"{files[0].stem}.zip" if len(files) == 1 else "archive.zip"))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            if f.is_dir():
                for child in sorted(f.rglob("*")):
                    zf.write(child, child.relative_to(f.parent))
            else:
                zf.write(f, f.name)
    return out


def pack_rar(files: list[Path], out: Path | None = None) -> Path:
    _check_inputs(files)
    rar = fc.require_tool("rar")  # proprietär: brew install --cask rar
    out = _unique(out or files[0].parent / (f"{files[0].stem}.rar" if len(files) == 1 else "archive.rar"))
    fc.run([rar, "a", "-ep1", str(out), *map(str, files)])
    return out


def extract(src: Path, out_dir: Path | None = None) -> Path:
    if not src.is_file():
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if src.suffix.lower() not in EXTRACT_SUFFIXES:
        raise fc.ConvertError(f"Archivtyp '{src.suffix}' nicht unterstützt")
    out_dir = out_dir or _unique(src.with_name(src.stem))
    out_dir.mkdir(parents=True, exist_ok=False)
    try:
        # bsdtar (libarchive) liest zip/rar/7z/tar und verweigert '..'-Pfade
        fc.run(["/usr/bin/bsdtar", "-xf", str(src), "-C", str(out_dir)])
    except fc.ConvertError:
        if not any(out_dir.iterdir()):
            out_dir.rmdir()
        raise
    return out_dir
