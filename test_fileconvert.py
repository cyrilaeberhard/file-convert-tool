from pathlib import Path

import pytest

import fileconvert as fc


def test_png_to_webp_uses_cwebp():
    cmd = fc.build_command(Path("a.png"), "webp", Path("a.webp"), 70)
    assert cmd[:3] == ["cwebp", "-q", "70"]


def test_video_crf_in_range():
    for q in (1, 50, 100):
        cmd = fc.build_command(Path("a.mov"), "mp4", Path("a.mp4"), q)
        assert 18 <= int(cmd[cmd.index("-crf") + 1]) <= 35


def test_audio_drops_video():
    assert "-vn" in fc.build_command(Path("a.mp4"), "mp3", Path("a.mp3"), 80)


def test_unknown_format_rejected(tmp_path):
    src = tmp_path / "a.png"
    src.write_bytes(b"x")
    with pytest.raises(fc.ConvertError):
        fc.convert(src, "xyz", None, 80)


def test_missing_input_rejected(tmp_path):
    with pytest.raises(fc.ConvertError):
        fc.convert(tmp_path / "nope.png", "jpg", None, 80)


def test_no_overwrite_of_input(tmp_path):
    src = tmp_path / "a.png"
    src.write_bytes(b"x")
    with pytest.raises(fc.ConvertError):
        fc.convert(src, "png", src, 80)


def test_metadata_flags():
    keep = fc.build_command(Path("a.png"), "webp", Path("a.webp"), 80, True)
    assert keep[3:5] == ["-metadata", "all"]
    drop = fc.build_command(Path("a.mov"), "mp4", Path("a.mp4"), 80, False)
    assert "-map_metadata" in drop and drop[drop.index("-map_metadata") + 1] == "-1"
    default = fc.build_command(Path("a.mov"), "mp4", Path("a.mp4"), 80)
    assert "-map_metadata" not in default
