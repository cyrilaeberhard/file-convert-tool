"""Eine Einstiegsfunktion für alle Konvertierungen der Matrix."""
from __future__ import annotations

from pathlib import Path

import fileconvert as fc
import matrix

IMAGE_FOLDER_TARGETS = {"jpg", "png"}


def _base_name(src: Path) -> str:
    name = src.name[: -len(src.suffix)] if src.suffix else src.name
    return name[:-4] if name.lower().endswith(".tar") else name


def default_output(src: Path, source_group: str, target: str) -> Path:
    """Ausgabepfad neben dem Original, ohne etwas zu überschreiben."""
    base, suffix = _base_name(src), matrix.output_suffix(target)
    folder_output = source_group == "Documents" and target in IMAGE_FOLDER_TARGETS
    n = 1
    while True:
        name = base if n == 1 else f"{base}-{n}"
        candidate = src.with_name(name + suffix)
        taken = src.with_name(name + "_pages").exists() if folder_output else candidate.exists()
        if not taken:
            return candidate
        n += 1


def convert_any(src: Path, target: str, quality: int = 80, keep_metadata: bool = True,
                out: Path | None = None) -> Path:
    src = Path(src)
    if not src.is_file() and not (src.is_dir() and src.suffix.lower() == ".rtfd"):
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if not 1 <= quality <= 100:
        raise fc.ConvertError("Qualität muss 1-100 sein")
    source, target = matrix.normalize(src.suffix), matrix.normalize(target)
    group = matrix.group_of(source)
    if group is None:
        raise fc.ConvertError(f"Dateityp '{src.suffix}' nicht unterstützt")
    if target not in matrix.targets_of(source):
        raise fc.ConvertError(f"{source.upper()} nach {target.upper()} wird nicht unterstützt. "
                              f"Möglich: {', '.join(t.upper() for t in matrix.targets_of(source))}")
    out = out or default_output(src, group, target)
    if out.resolve() == src.resolve():
        raise fc.ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    if group == "Images":
        import imageconv
        return imageconv.convert_image(src, source, target, out, quality, keep_metadata)
    if group in {"Audio", "Video"}:
        import mediaconv
        return mediaconv.convert_media(src, source, target, out, quality, keep_metadata)
    if group == "Subtitles":
        import mediaconv
        return mediaconv.convert_subtitle(src, source, target, out)
    if group == "Archives":
        import archiveconv
        return archiveconv.convert_archive(src, source, target, out)
    if group == "Spreadsheets":
        import sheetconv
        return sheetconv.convert_sheet(src, source, target, out)
    import docconv
    return docconv.convert_document(src, source, target, out)


LOSSY_TARGETS = {"jpg", "webp", "heic", "avif"}


def recompress_image(src: Path, target: str, quality: int, out: Path, max_edge: int = 0,
                     keep_metadata: bool = True) -> Path:
    """Bild neu kodieren (auch im gleichen Format), optional auf längste Kante verkleinert."""
    import imageconv
    import tempfile
    src, target = Path(src), matrix.normalize(target)
    source = matrix.normalize(src.suffix)
    if matrix.group_of(source) != "Images" or source == "svg":
        raise fc.ConvertError("Nur Rasterbilder lassen sich komprimieren")
    if target not in LOSSY_TARGETS:
        raise fc.ConvertError(f"Zielformat '{target}' ist nicht verlustbehaftet. Erlaubt: {', '.join(sorted(LOSSY_TARGETS))}")
    if not 1 <= quality <= 100 or not 0 <= max_edge <= 20000:
        raise fc.ConvertError("Qualität 1-100, Kantenlänge 0-20000")
    with tempfile.TemporaryDirectory() as tmp:
        source_file = src
        if max_edge:
            source_file = Path(tmp) / ("in" + src.suffix)
            fc.run(["/usr/bin/sips", "-Z", str(max_edge), str(src), "--out", str(source_file)])
        return imageconv.convert_image(source_file, source, target, Path(out), quality, keep_metadata)
