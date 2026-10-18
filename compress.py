"""Kompression auf eine Zielgröße (MB) für Bild und Video."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

import fileconvert as fc

AUDIO_KBPS = 128
MIN_VIDEO_KBPS = 50


def video_bitrate_kbps(target_mb: float, duration_s: float) -> int:
    """Video-Bitrate in kbit/s, damit Video + Audio ungefähr target_mb ergeben."""
    if duration_s <= 0:
        raise fc.ConvertError("Videodauer unbekannt")
    total_kbps = target_mb * 8192 * 0.95 / duration_s  # 5 % Container-Reserve
    video = int(total_kbps - AUDIO_KBPS)
    if video < MIN_VIDEO_KBPS:
        raise fc.ConvertError(f"{target_mb} MB sind für {duration_s:.0f}s Video zu klein")
    return video


def best_quality(fits, low: int = 1, high: int = 95) -> int | None:
    """Größte Qualität, für die fits(q) wahr ist (Bisektion); None wenn keine passt."""
    best = None
    while low <= high:
        mid = (low + high) // 2
        if fits(mid):
            best, low = mid, mid + 1
        else:
            high = mid - 1
    return best


def probe_duration(src: Path) -> float:
    result = subprocess.run(
        [fc.require_tool("ffprobe"), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(src)],
        capture_output=True, text=True)
    try:
        return float(result.stdout.strip())
    except ValueError:
        raise fc.ConvertError("Videodauer nicht lesbar")


def compress_image(src: Path, target_mb: float, out: Path) -> Path:
    fmt = "webp" if src.suffix.lower() == ".webp" else "jpg"
    limit = int(target_mb * 1024 * 1024)
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / f"p.{fmt}"

        def fits(q: int) -> bool:
            fc.convert(src, fmt, probe, q)
            return probe.stat().st_size <= limit

        q = best_quality(fits)
        if q is None:
            raise fc.ConvertError(f"Bild lässt sich nicht auf {target_mb} MB verkleinern")
        return fc.convert(src, fmt, out.with_suffix(f".{fmt}"), q)


def compress_video(src: Path, target_mb: float, out: Path) -> Path:
    kbps = video_bitrate_kbps(target_mb, probe_duration(src))
    out = out.with_suffix(".mp4")
    fc.run([fc.require_tool("ffmpeg"), "-y", "-i", str(src),
            "-c:v", "libx264", "-b:v", f"{kbps}k", "-maxrate", f"{kbps}k",
            "-bufsize", f"{kbps * 2}k", "-c:a", "aac", "-b:a", f"{AUDIO_KBPS}k", str(out)])
    return out


def compress(src: Path, target_mb: float, out: Path | None = None) -> Path:
    if not src.is_file():
        raise fc.ConvertError(f"Datei fehlt: {src}")
    if target_mb <= 0:
        raise fc.ConvertError("Zielgröße muss größer als 0 sein")
    out = out or src.with_name(f"{src.stem}_compressed{src.suffix}")
    kind = src.suffix.lower().lstrip(".")
    if kind in fc.IMAGE_FORMATS:
        return compress_image(src, target_mb, out)
    if kind in fc.VIDEO_FORMATS:
        return compress_video(src, target_mb, out)
    raise fc.ConvertError(f"Kompression für '{kind}' nicht unterstützt")
