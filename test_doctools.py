import zipfile

import pytest

import doctools as dt
import fileconvert as fc

CONTAINER = b"""<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

OPF = b"""<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
<manifest>
<item id="c2" href="ch%202.xhtml" media-type="application/xhtml+xml"/>
<item id="c1" href="ch1.xhtml#top" media-type="application/xhtml+xml"/>
<item id="css" href="s.css" media-type="text/css"/>
</manifest>
<spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>"""


def test_spine_order_and_paths():
    paths = dt.spine_paths(CONTAINER, lambda p: OPF)
    assert paths == ["OEBPS/ch1.xhtml", "OEBPS/ch 2.xhtml"]


def test_entity_declarations_rejected():
    evil = b'<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "b">]><container/>'
    with pytest.raises(fc.ConvertError):
        dt.spine_paths(evil, lambda p: OPF)


def test_epub_without_rootfile():
    with pytest.raises(fc.ConvertError):
        dt.spine_paths(b"<container xmlns='urn:oasis:names:tc:opendocument:xmlns:container'/>", lambda p: OPF)


def test_zip_slip_blocked(tmp_path):
    bad = tmp_path / "bad.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("../evil.txt", "x")
    dest = tmp_path / "out"
    dest.mkdir()
    with zipfile.ZipFile(bad) as zf, pytest.raises(fc.ConvertError):
        dt._safe_extract(zf, dest)
    assert not (tmp_path / "evil.txt").exists()


def test_unsupported_office_format(tmp_path):
    f = tmp_path / "a.xlsx"
    f.write_text("x")
    with pytest.raises(fc.ConvertError):
        dt.office_to_pdf(f)


def test_not_an_epub(tmp_path):
    f = tmp_path / "a.epub"
    f.write_text("kein zip")
    with pytest.raises(fc.ConvertError):
        dt.epub_to_pdf(f)
