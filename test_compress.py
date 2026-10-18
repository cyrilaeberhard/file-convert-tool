import pytest

import compress as comp
import fileconvert as fc


def test_best_quality_finds_threshold():
    assert comp.best_quality(lambda q: q <= 62) == 62


def test_best_quality_none_when_nothing_fits():
    assert comp.best_quality(lambda q: False) is None


def test_best_quality_all_fit_returns_max():
    assert comp.best_quality(lambda q: True) == 95


def test_video_bitrate_matches_target():
    kbps = comp.video_bitrate_kbps(10, 60)
    total_mb = (kbps + comp.AUDIO_KBPS) * 60 / 8192
    assert 8.5 < total_mb <= 10


def test_video_bitrate_too_small_rejected():
    with pytest.raises(fc.ConvertError):
        comp.video_bitrate_kbps(0.1, 600)


def test_zero_duration_rejected():
    with pytest.raises(fc.ConvertError):
        comp.video_bitrate_kbps(5, 0)
