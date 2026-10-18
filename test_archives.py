import zipfile

import pytest

import archives as ar
import fileconvert as fc


def test_zip_roundtrip(tmp_path):
    (tmp_path / "a.txt").write_text("hallo")
    folder = tmp_path / "d"
    folder.mkdir()
    (folder / "b.txt").write_text("welt")
    z = ar.pack_zip([tmp_path / "a.txt", folder])
    assert sorted(zipfile.ZipFile(z).namelist()) == ["a.txt", "d/b.txt"]
    out = ar.extract(z)
    assert (out / "d" / "b.txt").read_text() == "welt"


def test_pack_never_overwrites(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("x")
    assert ar.pack_zip([f]).name == "a.zip"
    assert ar.pack_zip([f]).name == "a-2.zip"


def test_extract_blocks_path_traversal(tmp_path):
    evil = tmp_path / "evil.zip"
    with zipfile.ZipFile(evil, "w") as zf:
        zf.writestr("../escaped.txt", "x")
    try:
        ar.extract(evil)
    except fc.ConvertError:
        pass
    assert not (tmp_path / "escaped.txt").exists()


def test_extract_rejects_unknown_type(tmp_path):
    f = tmp_path / "a.doc"
    f.write_text("x")
    with pytest.raises(fc.ConvertError):
        ar.extract(f)


def test_empty_and_missing_inputs(tmp_path):
    with pytest.raises(fc.ConvertError):
        ar.pack_zip([])
    with pytest.raises(fc.ConvertError):
        ar.pack_zip([tmp_path / "nope"])


def test_subtitle_needs_subtitle_source(tmp_path):
    with pytest.raises(fc.ConvertError):
        fc.build_command(tmp_path / "a.mp4", "srt", tmp_path / "a.srt", 80)
