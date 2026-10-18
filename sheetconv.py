"""Tabellen: xlsx, xls (mit xlrd), ods, csv, tsv lesen; xlsx, ods, csv, tsv, pdf schreiben."""
from __future__ import annotations

import csv
import html
import re
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

import fileconvert as fc
import packages

MAX_BYTES = 200 * 1024 * 1024
MAX_REPEAT = 200
_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_ODS = {"table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0",
        "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
        "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0"}


def _xml(data: bytes) -> ET.Element:
    if b"<!ENTITY" in data:
        raise fc.ConvertError("XML mit Entity-Deklarationen wird nicht unterstützt")
    return ET.fromstring(data)


def _read_zip_member(zf: zipfile.ZipFile, name: str) -> bytes:
    info = zf.getinfo(name)
    if info.file_size > MAX_BYTES:
        raise fc.ConvertError("Datei ist zu groß")
    return zf.read(name)


def _col_index(ref: str) -> int:
    letters = re.match(r"[A-Z]+", ref).group(0)
    index = 0
    for ch in letters:
        index = index * 26 + ord(ch) - 64
    return index - 1


def read_csv(path: Path, delimiter: str) -> list[list[str]]:
    with open(path, newline="", encoding="utf-8-sig", errors="replace") as handle:
        return [row for row in csv.reader(handle, delimiter=delimiter)]


def read_xlsx(path: Path) -> list[list[str]]:
    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        raise fc.ConvertError("XLSX ist kein gültiges Archiv")
    with zf:
        shared: list[str] = []
        if "xl/sharedStrings.xml" in zf.namelist():
            for si in _xml(_read_zip_member(zf, "xl/sharedStrings.xml")).iter(_MAIN + "si"):
                shared.append("".join(t.text or "" for t in si.iter(_MAIN + "t")))
        sheets = sorted(n for n in zf.namelist() if re.fullmatch(r"xl/worksheets/sheet\d+\.xml", n))
        if not sheets:
            raise fc.ConvertError("XLSX ohne Tabellenblatt")
        rows: list[list[str]] = []
        for row in _xml(_read_zip_member(zf, sheets[0])).iter(_MAIN + "row"):
            cells: dict[int, str] = {}
            for c in row.iter(_MAIN + "c"):
                kind = c.get("t")
                value = c.find(_MAIN + "v")
                if kind == "inlineStr":
                    text = "".join(t.text or "" for t in c.iter(_MAIN + "t"))
                elif value is None:
                    text = ""
                elif kind == "s":
                    text = shared[int(value.text)] if value.text and int(value.text) < len(shared) else ""
                else:
                    text = value.text or ""
                cells[_col_index(c.get("r", "A1"))] = text
            rows.append([cells.get(i, "") for i in range(max(cells) + 1)] if cells else [])
        return rows


def read_ods(path: Path) -> list[list[str]]:
    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        raise fc.ConvertError("ODS ist kein gültiges Archiv")
    with zf:
        root = _xml(_read_zip_member(zf, "content.xml"))
    table_ns = "{%s}" % _ODS["table"]
    table = root.find(".//table:table", _ODS)
    if table is None:
        raise fc.ConvertError("ODS ohne Tabelle")
    rows: list[list[str]] = []
    for row in table.iter(table_ns + "table-row"):
        cells: list[str] = []
        for cell in row:
            if cell.tag not in (table_ns + "table-cell", table_ns + "covered-table-cell"):
                continue
            text = "\n".join("".join(p.itertext()) for p in cell.findall("text:p", _ODS))
            value = cell.get("{%s}value" % _ODS["office"])
            repeat = min(int(cell.get(table_ns + "number-columns-repeated", "1")), MAX_REPEAT)
            cells.extend([value if value is not None and text == "" else text] * repeat)
        while cells and cells[-1] == "":
            cells.pop()
        repeat_rows = min(int(row.get(table_ns + "number-rows-repeated", "1")), MAX_REPEAT if cells else 1)
        rows.extend([list(cells) for _ in range(repeat_rows)] if cells else [[]])
    while rows and not rows[-1]:
        rows.pop()
    return rows


def read_xls(path: Path) -> list[list[str]]:
    try:
        import xlrd
    except ImportError:
        raise fc.ConvertError("XLS braucht xlrd. Installieren: pip3 install --user xlrd")
    sheet = xlrd.open_workbook(str(path)).sheet_by_index(0)
    return [[str(sheet.cell_value(r, c)) if sheet.cell_value(r, c) != "" else "" for c in range(sheet.ncols)]
            for r in range(sheet.nrows)]


def read_table(src: Path, source: str) -> list[list[str]]:
    if source == "csv":
        return read_csv(src, ",")
    if source == "tsv":
        return read_csv(src, "\t")
    readers = {"xlsx": read_xlsx, "ods": read_ods, "xls": read_xls}
    return readers[source](src)


def table_html(rows: list[list[str]]) -> str:
    body = "".join("<tr>" + "".join(f"<td>{html.escape(c)}</td>" for c in row) + "</tr>" for row in rows)
    return f"<table>{body}</table>"


def write_table(rows: list[list[str]], target: str, out: Path) -> Path:
    if target in {"csv", "tsv"}:
        with open(out, "w", newline="", encoding="utf-8") as handle:
            csv.writer(handle, delimiter="," if target == "csv" else "\t").writerows(rows)
    elif target == "xlsx":
        packages.write_xlsx(rows, out)
    elif target == "ods":
        packages.write_ods(rows, out)
    elif target == "pdf":
        import doctools
        import markup
        with tempfile.TemporaryDirectory() as tmp:
            page = Path(tmp) / "table.html"
            page.write_text(markup.wrap_html(table_html(rows), out.stem), encoding="utf-8")
            fc.run([doctools.find_helper(), "--root", tmp, str(out), str(page)])
    else:
        raise fc.ConvertError(f"Zielformat '{target}' nicht unterstützt")
    return out


def convert_sheet(src: Path, source: str, target: str, out: Path) -> Path:
    return write_table(read_table(src, source), target, out)
