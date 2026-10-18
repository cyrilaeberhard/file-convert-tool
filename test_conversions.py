import zipfile

import pytest

import archiveconv
import dispatcher
import docconv
import fileconvert as fc
import mediaconv
import packages
import sheetconv

ROWS = [["Name", "Wert"], ["ä&<b>", "2.5"], ["", "x"]]


def test_col_names():
    assert [packages.col_name(i) for i in (0, 25, 26, 701)] == ["A", "Z", "AA", "ZZ"]


@pytest.mark.parametrize("target", ["xlsx", "ods", "csv", "tsv"])
def test_table_roundtrip(tmp_path, target):
    out = sheetconv.write_table(ROWS, target, tmp_path / f"t.{target}")
    assert sheetconv.read_table(out, target) == ROWS


def test_xlsx_rejects_entities(tmp_path):
    bad = tmp_path / "bad.xlsx"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("xl/worksheets/sheet1.xml", '<!DOCTYPE x [<!ENTITY a "b">]><worksheet/>')
    with pytest.raises(fc.ConvertError):
        sheetconv.read_xlsx(bad)


def test_epub_roundtrip(tmp_path):
    epub = packages.write_epub("Buch", "<h1>Kapitel</h1><p>Hallo Welt.</p>", tmp_path / "b.epub")
    with zipfile.ZipFile(epub) as zf:
        assert zf.namelist()[0] == "mimetype" and zf.getinfo("mimetype").compress_type == zipfile.ZIP_STORED
    doc = docconv.read_doc(epub, "epub")
    assert "Hallo Welt." in doc.text


def test_text_conversions(tmp_path):
    md = tmp_path / "a.md"
    md.write_text("# Titel\n\nText **fett**\n")
    html = docconv.convert_document(md, "md", "html", tmp_path / "a.html")
    assert "<h1>Titel</h1>" in html.read_text()
    txt = docconv.convert_document(md, "md", "txt", tmp_path / "a.txt")
    assert "# Titel" in txt.read_text()


def test_pptx_needs_images(tmp_path):
    with pytest.raises(ValueError):
        packages.write_pptx([], tmp_path / "x.pptx")


def test_subtitle_text_strip():
    srt = "1\n00:00:01,000 --> 00:00:02,000\nHallo <i>Welt</i>\n\n2\n00:00:03,000 --> 00:00:04,000\nZwei\n"
    assert mediaconv.strip_subtitle_text(srt) == "Hallo Welt\nZwei\n"
    assert mediaconv.strip_subtitle_text("WEBVTT\n\n00:01.000 --> 00:02.000\nx\n").startswith("WEBVTT") is False


def test_media_commands():
    from pathlib import Path
    cmd = mediaconv.build_media_command(Path("a.mp4"), "mp4", "mp3", Path("a.mp3"), 80, False)
    assert "-vn" in cmd and "libmp3lame" in cmd and cmd[cmd.index("-map_metadata") + 1] == "-1"
    gif = mediaconv.build_media_command(Path("a.mp4"), "mp4", "gif", Path("a.gif"), 80, True)
    assert "palettegen" in " ".join(gif)
    assert mediaconv.audio_bitrate(100) == "320k" and mediaconv.audio_bitrate(50) == "96k"


def test_archive_chain(tmp_path):
    (tmp_path / "x.txt").write_text("Inhalt")
    zip_path = tmp_path / "a.zip"
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.write(tmp_path / "x.txt", "x.txt")
    tar = archiveconv.convert_archive(zip_path, "zip", "tar", tmp_path / "a.tar")
    gz = archiveconv.convert_archive(tar, "tar", "gzip", tmp_path / "a.tar.gz")
    back = archiveconv.convert_archive(gz, "gzip", "zip", tmp_path / "b.zip")
    assert zipfile.ZipFile(back).read("x.txt") == b"Inhalt"


def test_unsupported_pair_message(tmp_path):
    f = tmp_path / "a.png"
    f.write_bytes(b"x")
    with pytest.raises(fc.ConvertError, match="Möglich"):
        dispatcher.convert_any(f, "docx")
    with pytest.raises(fc.ConvertError):
        dispatcher.convert_any(tmp_path / "x.unknown", "png")


def test_default_output_never_overwrites(tmp_path):
    src = tmp_path / "a.png"
    src.write_bytes(b"x")
    (tmp_path / "a.jpg").write_bytes(b"y")
    assert dispatcher.default_output(src, "Images", "jpg").name == "a-2.jpg"
    (tmp_path / "doc.pdf").write_bytes(b"x")
    (tmp_path / "doc_pages").mkdir()
    assert dispatcher.default_output(tmp_path / "doc.pdf", "Documents", "png").name == "doc-2.png"
    tgz = tmp_path / "pack.tar.gz"
    assert dispatcher.default_output(tgz, "Archives", "zip").name == "pack.zip"


def test_recompress_rejects_lossless_target_and_svg(tmp_path):
    f = tmp_path / "a.png"
    f.write_bytes(b"x")
    with pytest.raises(fc.ConvertError):
        dispatcher.recompress_image(f, "png", 70, tmp_path / "o.png")
    svg = tmp_path / "a.svg"
    svg.write_text("<svg/>")
    with pytest.raises(fc.ConvertError):
        dispatcher.recompress_image(svg, "jpg", 70, tmp_path / "o.jpg")


@pytest.mark.skipif(__import__("shutil").which("sips") is None, reason="sips fehlt")
def test_recompress_jpg_gets_smaller(tmp_path):
    import subprocess
    png = tmp_path / "a.png"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=640x480", "-frames:v", "1", str(png)], check=True)
    jpg = tmp_path / "a.jpg"
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", str(png), "--out", str(jpg)], check=True, capture_output=True)
    small = dispatcher.recompress_image(jpg, "jpg", 30, tmp_path / "small.jpg")
    assert small.stat().st_size < jpg.stat().st_size
    tiny = dispatcher.recompress_image(jpg, "webp", 60, tmp_path / "t.webp", max_edge=200)
    assert tiny.stat().st_size < jpg.stat().st_size
