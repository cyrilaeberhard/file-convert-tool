"""Dokumente: pdf, docx, pptx, txt, md, rtf, rtfd, textclipping, epub in andere Formate."""
from __future__ import annotations

import plistlib
import re
import tempfile
import zipfile
from pathlib import Path

import doctools
import fileconvert as fc
import markup
import packages
import pdftools

TEXTUTIL_SOURCES = {"docx", "rtf", "rtfd"}


class Doc:
    """Gelesenes Dokument als HTML-Body und als reiner Text."""

    def __init__(self, body: str, text: str, title: str) -> None:
        self.body = body
        self.text = text
        self.title = title


def _textutil(src: Path, fmt: str, out: Path) -> None:
    fc.run(["/usr/bin/textutil", "-convert", fmt, str(src), "-output", str(out)])


def _clipping_text(src: Path) -> str:
    try:
        data = plistlib.loads(src.read_bytes())
        text = data["UTI-Data"]["public.utf8-plain-text"]
        return text.decode("utf-8") if isinstance(text, bytes) else str(text)
    except Exception:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "clip.txt"
            _textutil(src, "txt", out)
            return out.read_text(encoding="utf-8", errors="replace")


def _pdf_text(src: Path) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "pdf.txt"
        pdftools._gs("-sDEVICE=txtwrite", f"-sOutputFile={out}", str(src))
        return out.read_text(encoding="utf-8", errors="replace")


def _epub_html(src: Path) -> str:
    try:
        zf = zipfile.ZipFile(src)
    except zipfile.BadZipFile:
        raise fc.ConvertError("EPUB ist kein gültiges Archiv")
    with zf:
        paths = doctools.spine_paths(zf.read("META-INF/container.xml"), zf.read)
        parts = []
        for name in paths:
            if name in zf.namelist():
                raw = zf.read(name).decode("utf-8", errors="replace")
                match = re.search(r"<body[^>]*>(.*)</body>", raw, re.S | re.I)
                parts.append(match.group(1) if match else raw)
    return "\n".join(parts)


def read_doc(src: Path, source: str) -> Doc:
    title = src.stem
    if source == "txt":
        text = src.read_text(encoding="utf-8-sig", errors="replace")
        return Doc(markup.text_to_html(text), text, title)
    if source == "md":
        text = src.read_text(encoding="utf-8-sig", errors="replace")
        return Doc(markup.md_to_html(text), text, title)
    if source == "textclipping":
        text = _clipping_text(src)
        return Doc(markup.text_to_html(text), text, title)
    if source == "pdf":
        text = _pdf_text(src)
        return Doc(markup.text_to_html(text), text, title)
    if source == "epub":
        body = _epub_html(src)
        return Doc(body, markup.html_to_text(body), title)
    if source in TEXTUTIL_SOURCES:
        with tempfile.TemporaryDirectory() as tmp:
            page = Path(tmp) / "doc.html"
            _textutil(src, "html", page)
            body = page.read_text(encoding="utf-8", errors="replace")
        return Doc(packages.xhtml_body(body), markup.html_to_text(body), title)
    raise fc.ConvertError(f"Dokumentformat '{source}' nicht lesbar")


def _images(pdf: Path, fmt: str, out: Path) -> Path:
    """Seiten als Bilder in einen Ordner neben der Ausgabe (name_pages)."""
    return pdftools.pdf_to_images(pdf, fmt, 150, out.with_name(out.stem + "_pages"))


def _render_pdf(doc: Doc, out: Path, root: Path) -> Path:
    page = root / "doc.html"
    page.write_text(markup.wrap_html(doc.body, doc.title), encoding="utf-8")
    fc.run([doctools.find_helper(), "--root", str(root), str(out), str(page)])
    return out


def _pdf_to_pptx(src: Path, out: Path) -> Path:
    with tempfile.TemporaryDirectory() as tmp:
        pages = pdftools.pdf_to_images(src, "png", 110, Path(tmp) / "pages")
        images = sorted(pages.glob("page-*.png"))
        if not images:
            raise fc.ConvertError("PDF hat keine Seiten")
        return packages.write_pptx(images, out)


def _pdf_to_xlsx(src: Path, out: Path) -> Path:
    rows = [re.split(r"\s{2,}|\t", line.strip()) for line in _pdf_text(src).splitlines() if line.strip()]
    return packages.write_xlsx(rows, out)


def pptx_slides(src: Path) -> list[str]:
    """Text je Folie (a:t-Elemente) in Folienreihenfolge."""
    try:
        zf = zipfile.ZipFile(src)
    except zipfile.BadZipFile:
        raise fc.ConvertError("PPTX ist kein gültiges Archiv")
    with zf:
        names = sorted((n for n in zf.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)),
                       key=lambda n: int(re.search(r"(\d+)\.xml", n).group(1)))
        slides = []
        for name in names:
            raw = zf.read(name).decode("utf-8", errors="replace")
            if "<!ENTITY" in raw:
                raise fc.ConvertError("XML mit Entity-Deklarationen wird nicht unterstützt")
            paragraphs = re.findall(r"<a:p>(.*?)</a:p>", raw, re.S) or re.findall(r"<a:p\b[^>]*>(.*?)</a:p>", raw, re.S)
            lines = ["".join(re.findall(r"<a:t>([^<]*)</a:t>", p)) for p in paragraphs]
            slides.append("\n".join(l for l in lines if l.strip()))
    return slides


def _pptx_doc(src: Path) -> Doc:
    import html as h
    slides = pptx_slides(src)
    body = "".join(f"<h2>Folie {i}</h2><p>{h.unescape(s).replace(chr(10), '<br>')}</p>" for i, s in enumerate(slides, 1))
    return Doc(body, "\n\n".join(slides), src.stem)


def convert_document(src: Path, source: str, target: str, out: Path) -> Path:
    if source == "pdf":
        if target in {"jpg", "png"}:
            return _images(src, target, out)
        if target == "pptx":
            return _pdf_to_pptx(src, out)
        if target == "xlsx":
            return _pdf_to_xlsx(src, out)
    doc = _pptx_doc(src) if source == "pptx" else read_doc(src, source)
    if target == "txt":
        out.write_text(doc.text, encoding="utf-8")
    elif target == "md":
        out.write_text(doc.text if source == "txt" else markup.html_to_md(doc.body), encoding="utf-8")
    elif target == "html":
        out.write_text(markup.wrap_html(doc.body, doc.title), encoding="utf-8")
    elif target == "epub":
        packages.write_epub(doc.title, packages.xhtml_body(doc.body), out)
    elif target in {"pdf", "docx", "jpg", "png"}:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            if source == "epub" and target == "pdf":
                return doctools.epub_to_pdf(src, out)
            if target == "docx":
                page = root / "doc.html"
                page.write_text(markup.wrap_html(doc.body, doc.title), encoding="utf-8")
                _textutil(page, "docx", out)
            elif target == "pdf":
                _render_pdf(doc, out, root)
            else:
                pdf = _render_pdf(doc, root / "doc.pdf", root)
                return _images(pdf, target, out)
    else:
        raise fc.ConvertError(f"Zielformat '{target}' nicht unterstützt")
    return out

