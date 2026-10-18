import matrix


def test_normalize_aliases():
    assert matrix.normalize(".JPEG") == "jpg"
    assert matrix.normalize(".tgz") == "gzip"
    assert matrix.normalize(".textClipping") == "textclipping"


def test_images_follow_original_matrix():
    assert matrix.targets_of("jpg") == ["png", "webp", "heic", "tiff", "avif", "bmp", "pdf"]
    assert "svg" not in matrix.targets_of("png")
    assert "svg" not in matrix.IMAGE_COLS
    assert matrix.targets_of("svg") == matrix.IMAGE_COLS


def test_video_rules():
    assert "webm" not in matrix.targets_of("mp4")
    assert "mp3" in matrix.targets_of("mp4")
    assert matrix.targets_of("gif") == ["mp4", "mov", "mkv", "avi", "wmv"]
    assert matrix.targets_of("webm")[0] == "mp4"


def test_documents_and_pdf_wheel_order():
    assert matrix.targets_of("pptx") == ["pdf", "jpg", "png"]
    assert matrix.targets_of("epub") == ["pdf", "docx", "txt", "md", "html"]
    assert matrix.wheel_order("pdf")[:3] == ["docx", "pptx", "xlsx"]
    assert set(matrix.wheel_order("pdf")) == set(matrix.targets_of("pdf"))


def test_archives_subtitles_audio():
    assert matrix.targets_of("rar") == ["zip", "tar", "gzip"]
    assert matrix.targets_of("srt") == ["vtt", "txt"]
    assert "opus" in matrix.targets_of("mp3") and "mp3" not in matrix.targets_of("mp3")


def test_unknown_extension_has_no_targets():
    assert matrix.targets_of("xyz") == [] and matrix.group_of("xyz") is None


def test_output_suffix():
    assert matrix.output_suffix("gzip") == ".tar.gz" and matrix.output_suffix("png") == ".png"
