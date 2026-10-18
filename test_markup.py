import markup


def test_md_to_html_basics():
    html = markup.md_to_html("# T\n\nHallo **fett** und *kursiv*\n\n- a\n- b\n")
    assert "<h1>T</h1>" in html and "<strong>fett</strong>" in html and "<em>kursiv</em>" in html
    assert "<ul><li>a</li><li>b</li></ul>" in html


def test_md_escapes_html_and_blocks_javascript_links():
    html = markup.md_to_html("<script>x</script> [böse](javascript:alert1)")
    assert "<script>" not in html
    assert 'href="javascript' not in html


def test_html_to_md_roundtrip():
    md = markup.html_to_md("<h2>Kopf</h2><p>Text <b>fett</b> <a href='https://x.y'>Link</a></p><ul><li>eins</li></ul>")
    assert "## Kopf" in md and "**fett**" in md and "[Link](https://x.y)" in md and "- eins" in md


def test_html_to_text_keeps_spaces_around_bold():
    assert "Absatz mit Link" in markup.html_to_text("<p>Absatz <b>mit</b> Link</p>")


def test_text_to_html_paragraphs():
    assert markup.text_to_html("a\n\nb<c").count("<p>") == 2
    assert "&lt;" in markup.text_to_html("b<c")
