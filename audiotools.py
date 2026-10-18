"""Audio-Werkzeuge über ffmpeg: Kanäle, Stille erkennen, Waveform."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

import fileconvert as fc

CHANNEL_MODES = {
    "mono": ["-ac", "1"],
    "stereo": ["-ac", "2"],
    "left": ["-af", "pan=mono|c0=FL"],
    "right": ["-af", "pan=mono|c0=FR"],
}
MEDIA_FORMATS = fc.AUDIO_FORMATS | fc.VIDEO_FORMATS
_START = re.compile(r"silence_start: (-?[\d.]+)")
_END = re.compile(r"silence_end: ([\d.]+)")


def _check_media(src: Path) -> None:
    if not src.is_file():
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if src.suffix.lower().lstrip(".") not in MEDIA_FORMATS:
        raise fc.ConvertError(f"Kein Audio/Video: {src.name}")


def parse_silence(stderr: str, total: float | None = None) -> list[tuple[float, float | None]]:
    """Liest silencedetect-Ausgabe; offenes Ende bleibt None (oder total)."""
    spans: list[tuple[float, float | None]] = []
    start = None
    for line in stderr.splitlines():
        if (m := _START.search(line)):
            start = max(0.0, float(m.group(1)))
        elif (m := _END.search(line)) and start is not None:
            spans.append((start, float(m.group(1))))
            start = None
    if start is not None:
        spans.append((start, total))
    return spans


def convert_channels(src: Path, mode: str, out: Path | None = None) -> Path:
    if mode not in CHANNEL_MODES:
        raise fc.ConvertError(f"Modus '{mode}' unbekannt. Erlaubt: {', '.join(CHANNEL_MODES)}")
    _check_media(src)
    out = out or src.with_name(f"{src.stem}_{mode}{src.suffix}")
    if out.resolve() == src.resolve():
        raise fc.ConvertError("Ausgabe darf die Eingabe nicht überschreiben")
    fc.run([fc.require_tool("ffmpeg"), "-y", "-i", str(src), "-vn", *CHANNEL_MODES[mode], str(out)])
    return out


def detect_silence(src: Path, noise_db: float = -40, min_seconds: float = 0.5) -> list[tuple[float, float | None]]:
    if not -90 <= noise_db <= 0:
        raise fc.ConvertError("Schwelle muss zwischen -90 und 0 dB liegen")
    if min_seconds <= 0:
        raise fc.ConvertError("Mindestdauer muss größer als 0 sein")
    _check_media(src)
    result = subprocess.run(
        [fc.require_tool("ffmpeg"), "-hide_banner", "-i", str(src), "-vn",
         "-af", f"silencedetect=noise={noise_db}dB:d={min_seconds}", "-f", "null", "-"],
        capture_output=True, text=True)
    if result.returncode != 0:
        raise fc.ConvertError("ffmpeg fehlgeschlagen: " + " | ".join(result.stderr.strip().splitlines()[-2:]))
    return parse_silence(result.stderr)


def waveform(src: Path, out: Path | None = None, size: str = "1200x300") -> Path:
    if not re.fullmatch(r"\d{2,5}x\d{2,5}", size):
        raise fc.ConvertError("Größe im Format BREITExHÖHE, z. B. 1200x300")
    _check_media(src)
    out = out or src.with_name(f"{src.stem}_waveform.png")
    graph = f"aformat=channel_layouts=mono,showwavespic=s={size}:colors=#ff9500"
    fc.run([fc.require_tool("ffmpeg"), "-y", "-i", str(src), "-filter_complex", graph,
            "-frames:v", "1", str(out)])
    return out
