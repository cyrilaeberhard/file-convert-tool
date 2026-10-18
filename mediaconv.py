"""Audio, Video und Untertitel über ffmpeg."""
from __future__ import annotations

import re
from pathlib import Path

import fileconvert as fc

GIF_FILTER = "fps=12,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
EVEN_FILTER = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
_TIMING = re.compile(r"^\d{1,2}:\d{2}:\d{2}[,.]\d{3}\s*-->")


def audio_bitrate(quality: int) -> str:
    return "96k" if quality < 70 else "160k" if quality < 88 else "256k" if quality < 98 else "320k"


def crf(quality: int) -> int:
    return max(18, min(35, round(51 - quality * 0.33)))


def audio_args(target: str, quality: int) -> list[str]:
    br = audio_bitrate(quality)
    table = {
        "mp3": ["-c:a", "libmp3lame", "-b:a", br],
        "m4a": ["-c:a", "aac", "-b:a", br],
        "wav": ["-c:a", "pcm_s16le"],
        "flac": ["-c:a", "flac"],
        "ogg": ["-c:a", "vorbis", "-strict", "-2", "-b:a", br],
        "opus": ["-c:a", "libopus", "-b:a", br],
        "aiff": ["-c:a", "pcm_s16be"],
        "wma": ["-c:a", "wmav2", "-b:a", br],
    }
    return table[target]


def video_args(target: str, quality: int, source: str) -> list[str]:
    br = audio_bitrate(quality)
    if target == "gif":
        return ["-an", "-vf", GIF_FILTER, "-loop", "0"]
    if target == "wmv":
        return ["-c:v", "wmv2", "-b:v", "2M", "-c:a", "wmav2", "-b:a", br]
    if target == "avi":
        return ["-c:v", "mpeg4", "-q:v", "5", "-c:a", "libmp3lame", "-b:a", br]
    flags = ["-pix_fmt", "yuv420p", "-vf", EVEN_FILTER]
    args = ["-c:v", "libx264", "-crf", str(crf(quality)), *flags, "-c:a", "aac", "-b:a", br]
    if source == "gif":
        args = args + ["-an"]
    if target in {"mp4", "mov"}:
        args += ["-movflags", "+faststart"]
    return args


def build_media_command(src: Path, source: str, target: str, out: Path, quality: int, keep_metadata: bool) -> list[str]:
    meta = [] if keep_metadata else ["-map_metadata", "-1"]
    if target in {"mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"}:
        return ["ffmpeg", "-y", "-i", str(src), "-vn", *meta, *audio_args(target, quality), str(out)]
    return ["ffmpeg", "-y", "-i", str(src), *meta, *video_args(target, quality, source), str(out)]


def convert_media(src: Path, source: str, target: str, out: Path, quality: int, keep_metadata: bool) -> Path:
    cmd = build_media_command(src, source, target, out, quality, keep_metadata)
    cmd[0] = fc.require_tool("ffmpeg")
    try:
        fc.run(cmd)
    except fc.ConvertError as err:
        if "does not contain any stream" in str(err):
            raise fc.ConvertError("Die Datei hat keine Tonspur")
        raise
    return out


def strip_subtitle_text(content: str) -> str:
    """Nur gesprochener Text: ohne Nummern, Zeitangaben und WEBVTT-Kopf."""
    lines = []
    for raw in content.replace("\r\n", "\n").split("\n"):
        line = raw.strip()
        if not line or line.isdigit() or _TIMING.match(line):
            continue
        if line.upper().startswith(("WEBVTT", "NOTE", "STYLE", "X-TIMESTAMP")):
            continue
        lines.append(re.sub(r"<[^>]+>", "", line))
    return "\n".join(lines) + "\n"


def convert_subtitle(src: Path, source: str, target: str, out: Path) -> Path:
    if target == "txt":
        out.write_text(strip_subtitle_text(src.read_text(encoding="utf-8-sig", errors="replace")), encoding="utf-8")
        return out
    fc.run([fc.require_tool("ffmpeg"), "-y", "-i", str(src), str(out)])
    return out
