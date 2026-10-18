import pytest

import fileconvert as fc
import imageedit as ie


def test_crop_filter():
    assert ie.crop_filter(100, 50, 10, 5) == "crop=100:50:10:5"


@pytest.mark.parametrize("args", [(0, 10), (10, 0), (10, 10, -1, 0), (30000, 10)])
def test_crop_rejects_bad_values(args):
    with pytest.raises(fc.ConvertError):
        ie.crop_filter(*args)


def test_resize_keeps_aspect_with_one_side():
    assert ie.resize_filter(800, None) == "scale=800:-1"
    assert ie.resize_filter(None, 400) == "scale=-1:400"


def test_resize_needs_a_side():
    with pytest.raises(fc.ConvertError):
        ie.resize_filter(None, None)


def test_grid_layout():
    cols, rows, layout = ie.grid_layout(3, 100)
    assert (cols, rows) == (2, 2)
    assert layout == "0_0|100_0|0_100"


def test_grid_needs_two():
    with pytest.raises(fc.ConvertError):
        ie.grid_layout(1, 100)


def test_rejects_non_image(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("x")
    with pytest.raises(fc.ConvertError):
        ie.crop_image(f, 10, 10)
