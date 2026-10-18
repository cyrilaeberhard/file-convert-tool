import pytest

import audiotools as at
import fileconvert as fc

SAMPLE = """\
[silencedetect @ 0x1] silence_start: -0.00133
[silencedetect @ 0x1] silence_end: 1.5 | silence_duration: 1.50133
[silencedetect @ 0x1] silence_start: 4.2
"""


def test_parse_silence_closed_and_open():
    assert at.parse_silence(SAMPLE, total=6.0) == [(0.0, 1.5), (4.2, 6.0)]


def test_parse_silence_open_without_total():
    assert at.parse_silence(SAMPLE) == [(0.0, 1.5), (4.2, None)]


def test_parse_silence_none():
    assert at.parse_silence("nothing here") == []


def test_bad_channel_mode(tmp_path):
    with pytest.raises(fc.ConvertError):
        at.convert_channels(tmp_path / "a.mp3", "surround")


def test_rejects_non_media(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("x")
    with pytest.raises(fc.ConvertError):
        at.waveform(f)


@pytest.mark.parametrize("db,sec", [(5, 0.5), (-100, 0.5), (-40, 0)])
def test_silence_param_validation(tmp_path, db, sec):
    with pytest.raises(fc.ConvertError):
        at.detect_silence(tmp_path / "a.mp3", db, sec)


def test_waveform_size_validation(tmp_path):
    with pytest.raises(fc.ConvertError):
        at.waveform(tmp_path / "a.mp3", size="big")
