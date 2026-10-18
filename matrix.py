"""Welche Konvertierungen es gibt (Quelle für Backend, Wheel und Compatibility-Tab)."""
from __future__ import annotations

import json

ALIASES = {
    "jpeg": "jpg", "tif": "tiff", "htm": "html", "gz": "gzip", "tgz": "gzip", "aif": "aiff",
    "markdown": "md", "textclipping": "textclipping", "tsv": "tsv", "oga": "ogg",
}
OUTPUT_SUFFIX = {"gzip": ".tar.gz", "textclipping": ".textClipping"}

DOC_TARGETS = {
    "pdf": ["docx", "pptx", "txt", "md", "epub", "jpg", "png", "xlsx"],
    "docx": ["pdf", "txt", "md", "html", "epub", "jpg", "png"],
    "pptx": ["pdf", "jpg", "png"],
    "txt": ["pdf", "docx", "md", "html", "epub", "jpg", "png"],
    "md": ["pdf", "docx", "txt", "html", "epub", "jpg", "png"],
    "rtf": ["pdf", "docx", "txt", "md", "html", "epub", "jpg", "png"],
    "rtfd": ["pdf", "docx", "txt", "md", "html", "epub", "jpg", "png"],
    "textclipping": ["pdf", "docx", "txt", "md", "html", "epub", "jpg", "png"],
    "epub": ["pdf", "docx", "txt", "md", "html"],
}
DOC_COLS = ["pdf", "docx", "pptx", "txt", "md", "html", "epub", "jpg", "png", "xlsx"]

IMAGE_ROWS = ["jpg", "png", "webp", "heic", "tiff", "svg", "avif", "bmp"]
IMAGE_COLS = ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "pdf"]
AUDIO = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
VIDEO_ROWS = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]
VIDEO_COLS = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif", "mp3"]
SHEET_COLS = ["xlsx", "ods", "csv", "tsv", "pdf"]
ARCHIVE_ROWS = ["zip", "tar", "gzip", "rar"]
ARCHIVE_COLS = ["zip", "tar", "gzip"]
SUB_ROWS = ["srt", "vtt"]
SUB_COLS = ["srt", "vtt", "txt"]


def has_xlrd() -> bool:
    try:
        import xlrd  # noqa: F401
    except ImportError:
        return False
    return True


def sheet_rows() -> list[str]:
    return ["xlsx"] + (["xls"] if has_xlrd() else []) + ["ods", "csv", "tsv"]


def normalize(ext: str) -> str:
    ext = ext.lower().lstrip(".")
    return ALIASES.get(ext, ext)


def groups() -> list[dict]:
    """Gruppen in der Reihenfolge des Compatibility-Tabs."""
    return [
        {"title": "Images", "symbol": "photo.on.rectangle", "rows": IMAGE_ROWS, "cols": IMAGE_COLS},
        {"title": "Documents", "symbol": "doc.text", "rows": list(DOC_TARGETS), "cols": DOC_COLS},
        {"title": "Spreadsheets", "symbol": "tablecells", "rows": sheet_rows(), "cols": SHEET_COLS},
        {"title": "Audio", "symbol": "waveform", "rows": AUDIO, "cols": AUDIO},
        {"title": "Video", "symbol": "film", "rows": VIDEO_ROWS, "cols": VIDEO_COLS},
        {"title": "Archives", "symbol": "archivebox", "rows": ARCHIVE_ROWS, "cols": ARCHIVE_COLS},
        {"title": "Subtitles", "symbol": "captions.bubble", "rows": SUB_ROWS, "cols": SUB_COLS},
    ]


def group_of(ext: str) -> str | None:
    ext = normalize(ext)
    for g in groups():
        if ext in g["rows"]:
            return g["title"]
    return None


def targets_of(ext: str) -> list[str]:
    """Zielformate in Spaltenreihenfolge des Compatibility-Tabs."""
    ext = normalize(ext)
    for g in groups():
        if ext not in g["rows"]:
            continue
        if g["title"] == "Documents":
            return [c for c in g["cols"] if c in DOC_TARGETS[ext]]
        cols = [c for c in g["cols"] if c != ext]
        if g["title"] == "Video":
            cols = [c for c in cols if c != "webm" and not (ext == "gif" and c == "mp3")]
        return cols
    return []


def wheel_order(ext: str) -> list[str]:
    """Reihenfolge im Conversion-Wheel (für PDF wie im Original)."""
    targets = targets_of(ext)
    if normalize(ext) == "pdf":
        first = ["docx", "pptx", "xlsx", "jpg", "png", "epub", "txt", "md"]
        return [t for t in first if t in targets] + [t for t in targets if t not in first]
    return targets


def output_suffix(target: str) -> str:
    return OUTPUT_SUFFIX.get(target, "." + target)


def caps() -> dict:
    gs = groups()
    sources = []
    for g in gs:
        sources.extend(g["rows"])
    return {
        "groups": gs,
        "targets": {ext: targets_of(ext) for ext in sources},
        "wheel": {ext: wheel_order(ext) for ext in sources},
    }


if __name__ == "__main__":
    print(json.dumps(caps()))
