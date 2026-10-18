#!/usr/bin/env python3
"""Probiert jede Konvertierung der Matrix mit echten Beispieldateien aus.

Nutzung: python3 check_matrix.py [Gruppe ...]   (Gruppen: Images Documents Spreadsheets Audio Video Archives Subtitles)
Beispieldateien entstehen in einem Temp-Ordner im Home-Verzeichnis (Folders-Regel der App).
"""
from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import matrix
import packages

HERE = Path(__file__).parent
PYTHON = "/usr/bin/python3"
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="200" height="100" fill="orange"/><text x="20" y="55">Hallo</text></svg>'


def sh(*cmd: str) -> None:
    subprocess.run(cmd, check=True, capture_output=True)


def make_samples(d: Path) -> dict[str, Path]:
    s: dict[str, Path] = {}
    sh("ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240", "-frames:v", "1", str(d / "base.png"))
    s["png"] = d / "base.png"
    for ext, fmt in (("jpg", "jpeg"), ("tiff", "tiff"), ("bmp", "bmp"), ("heic", "heic"), ("avif", "avif")):
        sh("sips", "-s", "format", fmt, str(s["png"]), "--out", str(d / f"base.{ext}"))
        s[ext] = d / f"base.{ext}"
    sh("cwebp", "-quiet", str(s["png"]), "-o", str(d / "base.webp"))
    s["webp"] = d / "base.webp"
    (d / "base.svg").write_text(SVG)
    s["svg"] = d / "base.svg"
    # Dokumente
    (d / "doc.txt").write_text("Titel\n\nErster Absatz.\n\nZweiter Absatz.\n")
    (d / "doc.md").write_text("# Titel\n\nErster **Absatz**.\n\n- eins\n- zwei\n")
    s["txt"], s["md"] = d / "doc.txt", d / "doc.md"
    for ext in ("rtf", "docx"):
        sh("/usr/bin/textutil", "-convert", ext, str(s["txt"]), "-output", str(d / f"doc.{ext}"))
        s[ext] = d / f"doc.{ext}"
    sh("/usr/bin/textutil", "-convert", "rtfd", str(s["txt"]), "-output", str(d / "doc.rtfd"))
    s["rtfd"] = d / "doc.rtfd"
    clip = {"UTI-Data": {"public.utf8-plain-text": b"Ausschnitt Text"}}
    (d / "clip.textClipping").write_bytes(plistlib.dumps(clip, fmt=plistlib.FMT_BINARY))
    s["textclipping"] = d / "clip.textClipping"
    packages.write_epub("Buch", "<h1>Kapitel</h1><p>Hallo Welt.</p>", d / "book.epub")
    s["epub"] = d / "book.epub"
    packages.write_pptx([s["png"]], d / "deck.pptx")
    s["pptx"] = d / "deck.pptx"
    sh("gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite", f"-sOutputFile={d / 'doc.pdf'}",
       "-c", "/Helvetica findfont 20 scalefont setfont 50 700 moveto (Hallo  Welt  42) show showpage")
    s["pdf"] = d / "doc.pdf"
    # Tabellen
    rows = [["Name", "Wert"], ["a", "1"], ["b", "2.5"]]
    (d / "t.csv").write_text("Name,Wert\na,1\nb,2.5\n")
    (d / "t.tsv").write_text("Name\tWert\na\t1\nb\t2.5\n")
    packages.write_xlsx(rows, d / "t.xlsx")
    packages.write_ods(rows, d / "t.ods")
    s.update({"csv": d / "t.csv", "tsv": d / "t.tsv", "xlsx": d / "t.xlsx", "ods": d / "t.ods"})
    try:  # XLS-Beispiel nur, wenn xlwt vorhanden ist (Test-Hilfsmittel, nicht Teil der App)
        import xlwt
        book = xlwt.Workbook()
        sheet = book.add_sheet("Sheet1")
        for r, row in enumerate(rows):
            for c, value in enumerate(row):
                sheet.write(r, c, value)
        book.save(str(d / "t.xls"))
        s["xls"] = d / "t.xls"
    except ImportError:
        pass
    # Audio / Video
    sh("ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-ac", "2", str(d / "tone.wav"))
    for ext in matrix.AUDIO:
        if ext == "wav":
            s["wav"] = d / "tone.wav"
        else:
            sh(PYTHON, str(HERE / "fileconvert.py"), "convert", str(d / "tone.wav"), ext, "-o", str(d / f"tone.{ext}"))
            s[ext] = d / f"tone.{ext}"
    sh("ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=10",
       "-f", "lavfi", "-i", "sine=frequency=440", "-t", "1", "-pix_fmt", "yuv420p", str(d / "clip.mp4"))
    s["mp4"] = d / "clip.mp4"
    for ext in ("mov", "mkv", "webm", "avi", "wmv", "gif"):
        sh(PYTHON, str(HERE / "fileconvert.py"), "convert", str(s["mp4"]), ext, "-o", str(d / f"clip.{ext}")) if ext != "webm" else \
            sh("ffmpeg", "-loglevel", "error", "-y", "-i", str(s["mp4"]), str(d / "clip.webm"))
        s[ext] = d / f"clip.{ext}"
    # Archive / Untertitel
    (d / "inh").mkdir()
    (d / "inh" / "x.txt").write_text("Inhalt")
    sh("/usr/bin/bsdtar", "-cf", str(d / "a.tar"), "-C", str(d / "inh"), "x.txt")
    sh("/usr/bin/bsdtar", "-czf", str(d / "a.tgz"), "-C", str(d / "inh"), "x.txt")
    sh("/usr/bin/bsdtar", "--format", "zip", "-cf", str(d / "a.zip"), "-C", str(d / "inh"), "x.txt")
    s.update({"tar": d / "a.tar", "gzip": d / "a.tgz", "zip": d / "a.zip"})
    (d / "s.srt").write_text("1\n00:00:01,000 --> 00:00:02,500\nHallo Welt\n\n")
    sh("ffmpeg", "-loglevel", "error", "-y", "-i", str(d / "s.srt"), str(d / "s.vtt"))
    s["srt"], s["vtt"] = d / "s.srt", d / "s.vtt"
    return s


def main() -> int:
    wanted = set(sys.argv[1:])
    work = Path(tempfile.mkdtemp(prefix="fcmatrix-", dir=Path.home()))
    failures = 0
    try:
        samples = make_samples(work)
        for g in matrix.groups():
            if wanted and g["title"] not in wanted:
                continue
            for row in g["rows"]:
                if row not in samples:
                    print(f"[{g['title']}] {row}: keine Beispieldatei (übersprungen)")
                    continue
                for target in matrix.targets_of(row):
                    run_dir = work / f"run-{row}-{target}"
                    run_dir.mkdir()
                    src = run_dir / samples[row].name
                    if samples[row].is_dir():
                        shutil.copytree(samples[row], src)
                    else:
                        shutil.copy2(samples[row], src)
                    res = subprocess.run([PYTHON, str(HERE / "fileconvert.py"), "convert", str(src), target],
                                         capture_output=True, text=True, timeout=180)
                    ok = res.returncode == 0 and res.stdout.strip() and Path(res.stdout.strip().splitlines()[-1]).exists()
                    if not ok:
                        failures += 1
                        print(f"FAIL [{g['title']}] {row} -> {target}: {(res.stderr or res.stdout).strip()[-200:]}")
        print(f"fertig, Fehler: {failures}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
