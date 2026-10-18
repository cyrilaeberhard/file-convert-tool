"""Archive ineinander umwandeln: zip, tar, gzip (.tar.gz) und rar (nur als Quelle)."""
from __future__ import annotations

import gzip
import shutil
import tarfile
import tempfile
import zipfile
from pathlib import Path

import fileconvert as fc


def _extract_to(src: Path, source: str, dest: Path) -> None:
    if source == "gzip" and not _is_tar_gz(src):
        # einfache .gz-Datei: eine Datei ohne Tar-Hülle
        with gzip.open(src, "rb") as fin, open(dest / (src.stem or "file"), "wb") as fout:
            shutil.copyfileobj(fin, fout)
        return
    fc.run(["/usr/bin/bsdtar", "-xf", str(src), "-C", str(dest)])


def _is_tar_gz(src: Path) -> bool:
    try:
        return tarfile.is_tarfile(src)
    except OSError:
        return False


def _members(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*") if not p.is_symlink())


def pack(root: Path, target: str, out: Path) -> None:
    if target == "zip":
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in _members(root):
                zf.write(path, path.relative_to(root))
    else:
        mode = "w:gz" if target == "gzip" else "w"
        with tarfile.open(out, mode) as tf:
            for path in _members(root):
                tf.add(path, arcname=str(path.relative_to(root)), recursive=False)


def convert_archive(src: Path, source: str, target: str, out: Path) -> Path:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _extract_to(src, source, root)
        if not any(root.iterdir()):
            raise fc.ConvertError("Archiv ist leer oder nicht lesbar")
        pack(root, target, out)
    return out
