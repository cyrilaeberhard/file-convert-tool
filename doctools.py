"""Dokumente zu PDF: Textverarbeitung (textutil) und EPUB, gerendert mit dem html2pdf-Helfer."""
from __future__ import annotations

import posixpath
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from urllib.parse import unquote

import fileconvert as fc

TEXTUTIL_FORMATS = {"doc", "docx", "rtf", "rtfd", "odt", "html", "htm", "txt", "wordml"}
MAX_EPUB_BYTES = 500 * 1024 * 1024
_NS = {"c": "urn:oasis:names:tc:opendocument:xmlns:container", "o": "http://www.idpf.org/2007/opf"}


def find_helper() -> str:
    here = Path(__file__).parent
    for candidate in (here / "html2pdf", here / "build" / "FileConvert.app" / "Contents" / "Resources" / "html2pdf"):
        if candidate.is_file():
            return str(candidate)
    raise fc.ConvertError("html2pdf-Helfer fehlt. Zuerst build.sh ausführen")


def _parse_xml(data: bytes) -> ET.Element:
    if b"<!ENTITY" in data or b"<!DOCTYPE" in data and b"[" in data:
        raise fc.ConvertError("XML mit Entity-Deklarationen wird nicht unterstützt")
    try:
        return ET.fromstring(data)
    except ET.ParseError as err:
        raise fc.ConvertError(f"EPUB-XML ungültig: {err}")


def spine_paths(container_xml: bytes, read_opf) -> list[str]:
    """Lesereihenfolge als Pfade innerhalb des Archivs. read_opf(pfad) liefert die OPF-Bytes."""
    rootfile = _parse_xml(container_xml).find(".//c:rootfile", _NS)
    if rootfile is None or not rootfile.get("full-path"):
        raise fc.ConvertError("EPUB ohne Paketdokument")
    opf_path = rootfile.get("full-path")
    opf = _parse_xml(read_opf(opf_path))
    manifest = {i.get("id"): i.get("href") for i in opf.findall(".//o:manifest/o:item", _NS)}
    base = posixpath.dirname(opf_path)
    paths = []
    for ref in opf.findall(".//o:spine/o:itemref", _NS):
        href = manifest.get(ref.get("idref"))
        if href:
            paths.append(posixpath.normpath(posixpath.join(base, unquote(href.split("#")[0]))))
    if not paths:
        raise fc.ConvertError("EPUB ohne Kapitel")
    return paths


def _safe_extract(zf: zipfile.ZipFile, dest: Path) -> None:
    if sum(i.file_size for i in zf.infolist()) > MAX_EPUB_BYTES:
        raise fc.ConvertError("EPUB ist zu groß")
    root = dest.resolve()
    for info in zf.infolist():
        target = (dest / info.filename).resolve()
        if root not in target.parents and target != root:
            raise fc.ConvertError("EPUB enthält unsichere Pfade")
    zf.extractall(dest)


def _finish(src: Path, out: Path | None, check_overwrite: bool = True) -> Path:
    out = out or src.with_suffix(".pdf")
    if check_overwrite and out.resolve() == src.resolve():
        raise fc.ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    return out


def office_to_pdf(src: Path, out: Path | None = None) -> Path:
    if not src.is_file():
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if src.suffix.lower().lstrip(".") not in TEXTUTIL_FORMATS:
        raise fc.ConvertError(f"Format '{src.suffix}' nicht unterstützt (nur {', '.join(sorted(TEXTUTIL_FORMATS))})")
    out = _finish(src, out)
    helper = find_helper()
    with tempfile.TemporaryDirectory() as tmp:
        html = Path(tmp) / "doc" / "doc.html"
        html.parent.mkdir()
        fc.run(["/usr/bin/textutil", "-convert", "html", str(src), "-output", str(html)])
        fc.run([helper, "--root", tmp, str(out), str(html)])
    return out


def epub_to_pdf(src: Path, out: Path | None = None) -> Path:
    if not src.is_file():
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if src.suffix.lower() != ".epub":
        raise fc.ConvertError("Keine EPUB-Datei")
    out = _finish(src, out)
    helper = find_helper()
    try:
        zf = zipfile.ZipFile(src)
    except zipfile.BadZipFile:
        raise fc.ConvertError("EPUB ist kein gültiges Archiv")
    with zf, tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "epub"
        root.mkdir()
        paths = spine_paths(zf.read("META-INF/container.xml"), zf.read)
        _safe_extract(zf, root)
        chapters = [str(root / p) for p in paths if (root / p).is_file()]
        if not chapters:
            raise fc.ConvertError("EPUB-Kapitel nicht gefunden")
        fc.run([helper, "--root", str(root), str(out), *chapters])
    return out
