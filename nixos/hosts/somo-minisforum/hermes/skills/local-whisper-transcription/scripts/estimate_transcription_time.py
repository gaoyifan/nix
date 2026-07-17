#!/usr/bin/env python3
"""Estimate whisper.cpp transcription time for a local audio file."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


DEFAULT_SPEED_RATIO = 49.04


def _json_exit(payload: dict, code: int) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(code)


def _probe_duration_seconds(file_path: Path) -> float:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        raise RuntimeError("ffprobe is required to estimate audio duration")
    proc = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(file_path),
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    duration = float(proc.stdout.strip())
    if duration <= 0:
        raise RuntimeError("ffprobe returned a non-positive duration")
    return duration


def _format_seconds(seconds: float) -> str:
    total = int(round(seconds))
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio_path", help="Absolute or relative path to the audio file")
    parser.add_argument(
        "--speed-ratio",
        type=float,
        default=float(os.getenv("HERMES_WHISPER_SPEED_RATIO", DEFAULT_SPEED_RATIO)),
        help=f"Audio duration divided by transcription time (default: {DEFAULT_SPEED_RATIO})",
    )
    args = parser.parse_args()

    audio_path = Path(args.audio_path).expanduser()
    if not audio_path.is_absolute():
        audio_path = audio_path.resolve()
    if audio_path.is_symlink():
        _json_exit({"ok": False, "error": f"Refusing symlink: {audio_path}"}, 1)
    if not audio_path.exists():
        _json_exit({"ok": False, "error": f"Audio file not found: {audio_path}"}, 1)
    if not audio_path.is_file():
        _json_exit({"ok": False, "error": f"Path is not a regular file: {audio_path}"}, 1)
    if args.speed_ratio <= 0:
        _json_exit({"ok": False, "error": "speed ratio must be positive"}, 1)

    try:
        duration = _probe_duration_seconds(audio_path)
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as exc:
        _json_exit({"ok": False, "error": str(exc)}, 1)

    estimated = duration / args.speed_ratio
    _json_exit(
        {
            "ok": True,
            "audio_path": str(audio_path),
            "audio_duration_seconds": round(duration, 3),
            "speed_ratio": round(args.speed_ratio, 3),
            "estimated_transcription_seconds": round(estimated, 1),
            "estimated_transcription_time": _format_seconds(estimated),
        },
        0,
    )


if __name__ == "__main__":
    main()
