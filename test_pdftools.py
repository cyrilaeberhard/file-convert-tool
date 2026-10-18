import shutil
import subprocess

import pytest

import fileconvert as fc
import pdftools as pt

needs_gs = pytest.mark.skipif(shutil.which("gs") is None, reason="gs fehlt")


@pytest.fixture
def pdfs(tmp_path):
    made = []
    for n in ("a", "b"):
        f = tmp_path / f"{n}.pdf"
        subprocess.run(["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite",
                        f"-sOutputFile={f}", "-c", f"/Helvetica findfont 20 scalefont setfont 50 700 moveto ({n}) show showpage"],
                       check=True)
        made.append(f)
    return made


def test_merge_needs_two(tmp_path):
    with pytest.raises(fc.ConvertError):
        pt.merge_pdfs([tmp_path / "a.pdf"], tmp_path / "o.pdf")


def test_rejects_non_pdf(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("x")
    with pytest.raises(fc.ConvertError):
        pt.compress_pdf(f)


def test_bad_level_and_dpi(tmp_path):
    with pytest.raises(fc.ConvertError):
        pt.compress_pdf(tmp_path / "a.pdf", level="x")
    with pytest.raises(fc.ConvertError):
        pt.pdf_to_images(tmp_path / "a.pdf", dpi=5)


@needs_gs
def test_merge_rejects_overwriting_input(pdfs):
    with pytest.raises(fc.ConvertError):
        pt.merge_pdfs(pdfs, pdfs[0])


@needs_gs
def test_images_one_per_page(pdfs, tmp_path):
    merged = pt.merge_pdfs(pdfs, tmp_path / "m.pdf")
    imgs = sorted(p.name for p in pt.pdf_to_images(merged, out_dir=tmp_path / "pg").iterdir())
    assert imgs == ["page-001.png", "page-002.png"]


@needs_gs
def test_compress_writes_new_file(pdfs, tmp_path):
    out = pt.compress_pdf(pdfs[0])
    assert out.name == "a_compressed.pdf" and out.stat().st_size > 0


@needs_gs
def test_split_makes_one_file_per_page(pdfs, tmp_path):
    merged = pt.merge_pdfs(pdfs, tmp_path / "m.pdf")
    out = pt.split_pdf(merged)
    assert sorted(p.name for p in out.iterdir()) == ["page-001.pdf", "page-002.pdf"]
