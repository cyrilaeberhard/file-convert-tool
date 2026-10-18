"""Schreibt einfache Office-/E-Book-Pakete (xlsx, ods, pptx, epub) mit zipfile."""
from __future__ import annotations

import re
import zipfile
import zlib
from pathlib import Path
from xml.sax.saxutils import escape

XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
EMU_PER_PT = 12700
SLIDE_W, SLIDE_H = 9144000, 6858000


def col_name(index: int) -> str:
    """0 -> A, 25 -> Z, 26 -> AA."""
    name = ""
    index += 1
    while index:
        index, rem = divmod(index - 1, 26)
        name = chr(65 + rem) + name
    return name


def _is_number(text: str) -> bool:
    return bool(re.fullmatch(r"-?\d+(\.\d+)?", text.strip())) and len(text.strip()) < 16


def write_xlsx(rows: list[list[str]], out: Path) -> Path:
    cells = []
    for r, row in enumerate(rows, start=1):
        parts = []
        for c, value in enumerate(row):
            ref = f"{col_name(c)}{r}"
            if value == "":
                continue
            if _is_number(value):
                parts.append(f'<c r="{ref}"><v>{value.strip()}</v></c>')
            else:
                parts.append(f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{escape(value)}</t></is></c>')
        cells.append(f'<row r="{r}">{"".join(parts)}</row>')
    sheet = (XML_HEAD + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
             f'<sheetData>{"".join(cells)}</sheetData></worksheet>')
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", XML_HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                    '<Default Extension="xml" ContentType="application/xml"/>'
                    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
                    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        zf.writestr("_rels/.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        zf.writestr("xl/workbook.xml", XML_HEAD + '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                    '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>')
        zf.writestr("xl/_rels/workbook.xml.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        zf.writestr("xl/worksheets/sheet1.xml", sheet)
    return out


def write_ods(rows: list[list[str]], out: Path) -> Path:
    body = []
    for row in rows:
        cells = []
        for value in row:
            if _is_number(value):
                cells.append(f'<table:table-cell office:value-type="float" office:value="{value.strip()}"><text:p>{escape(value)}</text:p></table:table-cell>')
            else:
                cells.append(f'<table:table-cell office:value-type="string"><text:p>{escape(value)}</text:p></table:table-cell>')
        body.append(f'<table:table-row>{"".join(cells)}</table:table-row>')
    content = (XML_HEAD + '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
               'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
               'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2"><office:body>'
               f'<office:spreadsheet><table:table table:name="Sheet1">{"".join(body)}</table:table></office:spreadsheet>'
               '</office:body></office:document-content>')
    with zipfile.ZipFile(out, "w") as zf:
        zf.writestr(zipfile.ZipInfo("mimetype"), "application/vnd.oasis.opendocument.spreadsheet")
        zf.writestr("content.xml", content, zipfile.ZIP_DEFLATED)
        zf.writestr("META-INF/manifest.xml", XML_HEAD + '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">'
                    '<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>'
                    '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>',
                    zipfile.ZIP_DEFLATED)
    return out


def write_pptx(images: list[Path], out: Path) -> Path:
    """Eine Folie pro Bild (Seite füllt die Folie, Seitenverhältnis bleibt erhalten)."""
    if not images:
        raise ValueError("keine Bilder")
    ct = ['<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
          '<Default Extension="xml" ContentType="application/xml"/>',
          '<Default Extension="png" ContentType="image/png"/>',
          '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>',
          '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>',
          '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>']
    ns = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')
    rel_ns = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    pres_rels = ['<Relationship Id="rIdM" Type="%s/slideMaster" Target="slideMasters/slideMaster1.xml"/>' % rel_ns]
    slide_ids = []
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for n, image in enumerate(images, start=1):
            width, height = png_size(image)
            scale = min(SLIDE_W / width, SLIDE_H / height)
            w, h = int(width * scale), int(height * scale)
            x, y = (SLIDE_W - w) // 2, (SLIDE_H - h) // 2
            zf.write(image, f"ppt/media/image{n}.png")
            zf.writestr(f"ppt/slides/slide{n}.xml", XML_HEAD + f'<p:sld {ns}><p:cSld><p:spTree>'
                        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
                        f'<p:pic><p:nvPicPr><p:cNvPr id="2" name="Page {n}"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
                        '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
                        f'<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm>'
                        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld></p:sld>')
            zf.writestr(f"ppt/slides/_rels/slide{n}.xml.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                        f'<Relationship Id="rId1" Type="{rel_ns}/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
                        f'<Relationship Id="rId2" Type="{rel_ns}/image" Target="../media/image{n}.png"/></Relationships>')
            ct.append(f'<Override PartName="/ppt/slides/slide{n}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>')
            pres_rels.append(f'<Relationship Id="rId{n}" Type="{rel_ns}/slide" Target="slides/slide{n}.xml"/>')
            slide_ids.append(f'<p:sldId id="{255 + n}" r:id="rId{n}"/>')
        zf.writestr("[Content_Types].xml", XML_HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' + "".join(ct) + "</Types>")
        zf.writestr("_rels/.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    f'<Relationship Id="rId1" Type="{rel_ns}/officeDocument" Target="ppt/presentation.xml"/></Relationships>')
        zf.writestr("ppt/presentation.xml", XML_HEAD + f'<p:presentation {ns}><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rIdM"/></p:sldMasterIdLst>'
                    f'<p:sldIdLst>{"".join(slide_ids)}</p:sldIdLst><p:sldSz cx="{SLIDE_W}" cy="{SLIDE_H}"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>')
        zf.writestr("ppt/_rels/presentation.xml.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + "".join(pres_rels) + "</Relationships>")
        tree = '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>'
        zf.writestr("ppt/slideMasters/slideMaster1.xml", XML_HEAD + f'<p:sldMaster {ns}>{tree}<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
                    '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>')
        zf.writestr("ppt/slideMasters/_rels/slideMaster1.xml.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    f'<Relationship Id="rId1" Type="{rel_ns}/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>')
        zf.writestr("ppt/slideLayouts/slideLayout1.xml", XML_HEAD + f'<p:sldLayout {ns} type="blank">{tree}</p:sldLayout>')
        zf.writestr("ppt/slideLayouts/_rels/slideLayout1.xml.rels", XML_HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    f'<Relationship Id="rId1" Type="{rel_ns}/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>')
    return out


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("kein PNG")
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def write_epub(title: str, body_html: str, out: Path) -> Path:
    """Ein-Kapitel-EPUB 3 aus einem HTML-Body."""
    chapter = (XML_HEAD + '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head>'
               f"<title>{escape(title)}</title></head><body>{body_html}</body></html>")
    nav = (XML_HEAD + '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Inhalt</title></head>'
           f'<body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">{escape(title)}</a></li></ol></nav></body></html>')
    opf = (XML_HEAD + '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
           '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
           f'<dc:identifier id="id">urn:fileconvert:{zlib.crc32(title.encode())}</dc:identifier><dc:title>{escape(title)}</dc:title>'
           '<dc:language>de</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata>'
           '<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
           '<item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>'
           '<spine><itemref idref="c1"/></spine></package>')
    container = (XML_HEAD + '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
                 '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    with zipfile.ZipFile(out, "w") as zf:
        zf.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")  # unkomprimiert und zuerst
        for name, data in (("META-INF/container.xml", container), ("OEBPS/content.opf", opf),
                           ("OEBPS/nav.xhtml", nav), ("OEBPS/chapter.xhtml", chapter)):
            zf.writestr(name, data, zipfile.ZIP_DEFLATED)
    return out


def xhtml_body(html_text: str) -> str:
    """Body-Inhalt als XHTML-tauglicher String (Tags schließen, Entities korrigieren)."""
    match = re.search(r"<body[^>]*>(.*)</body>", html_text, re.S | re.I)
    body = match.group(1) if match else html_text
    body = re.sub(r"<(script|style)\b.*?</\1>", "", body, flags=re.S | re.I)
    body = re.sub(r"<(br|hr|img)([^>]*?)/?>", r"<\1\2/>", body, flags=re.I)
    return re.sub(r"&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)", "&amp;", body)

