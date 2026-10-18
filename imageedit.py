"""Bildbearbeitung über ffmpeg: zuschneiden, Größe ändern, Collage."""
from __future__ import annotations

import math
from pathlib import Path

import fileconvert as fc

MAX_SIDE = 20000


def _check_image(src: Path) -> None:
    if not src.is_file():
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if src.suffix.lower().lstrip(".") not in fc.IMAGE_FORMATS:
        raise fc.ConvertError(f"Kein unterstütztes Bild: {src.name}")


def _positive(value: int, name: str) -> int:
    if not 1 <= value <= MAX_SIDE:
        raise fc.ConvertError(f"{name} muss zwischen 1 und {MAX_SIDE} liegen")
    return value


def crop_filter(width: int, height: int, x: int = 0, y: int = 0) -> str:
    if x < 0 or y < 0:
        raise fc.ConvertError("x und y dürfen nicht negativ sein")
    return f"crop={_positive(width, 'Breite')}:{_positive(height, 'Höhe')}:{x}:{y}"


def resize_filter(width: int | None, height: int | None) -> str:
    if width is None and height is None:
        raise fc.ConvertError("Breite oder Höhe angeben")
    w = _positive(width, "Breite") if width is not None else -1
    h = _positive(height, "Höhe") if height is not None else -1
    return f"scale={w}:{h}"


def grid_layout(count: int, cell: int) -> tuple[int, int, str]:
    """Spalten, Zeilen und xstack-Layout für ein quadratisches Raster."""
    if count < 2:
        raise fc.ConvertError("Collage braucht mindestens 2 Bilder")
    cols = math.ceil(math.sqrt(count))
    rows = math.ceil(count / cols)
    layout = "|".join(f"{(i % cols) * cell}_{(i // cols) * cell}" for i in range(count))
    return cols, rows, layout


def _apply(src: Path, vf: str, suffix: str, out: Path | None) -> Path:
    _check_image(src)
    out = out or src.with_name(f"{src.stem}_{suffix}{src.suffix}")
    if out.resolve() == src.resolve():
        raise fc.ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    fc.run([fc.require_tool("ffmpeg"), "-y", "-i", str(src), "-vf", vf, "-frames:v", "1", str(out)])
    return out


def crop_image(src: Path, width: int, height: int, x: int = 0, y: int = 0, out: Path | None = None) -> Path:
    return _apply(src, crop_filter(width, height, x, y), "cropped", out)


def resize_image(src: Path, width: int | None, height: int | None, out: Path | None = None) -> Path:
    return _apply(src, resize_filter(width, height), "resized", out)


def collage(files: list[Path], out: Path | None = None, cell: int = 600) -> Path:
    _positive(cell, "Zellgröße")
    for f in files:
        _check_image(f)
    _, _, layout = grid_layout(len(files), cell)
    out = out or files[0].with_name("collage.jpg")
    if out.resolve() in {f.resolve() for f in files}:
        raise fc.ConvertError("Ausgabe darf keine Eingabe überschreiben")
    fit = (f"scale={cell}:{cell}:force_original_aspect_ratio=decrease,"
           f"pad={cell}:{cell}:(ow-iw)/2:(oh-ih)/2:white")
    chains = ";".join(f"[{i}:v]{fit}[v{i}]" for i in range(len(files)))
    inputs = "".join(f"[v{i}]" for i in range(len(files)))
    graph = f"{chains};{inputs}xstack=inputs={len(files)}:layout={layout}:fill=white[out]"
    cmd = [fc.require_tool("ffmpeg"), "-y"]
    for f in files:
        cmd += ["-i", str(f)]
    fc.run(cmd + ["-filter_complex", graph, "-map", "[out]", "-frames:v", "1", str(out)])
    return out
