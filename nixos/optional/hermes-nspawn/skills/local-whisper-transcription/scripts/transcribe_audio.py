#!/usr/bin/env python3
"""Transcribe a local audio file via the preferred whisper.cpp servers."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import subprocess
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_BASE_URLS = (
    "http://100.65.1.63:8178",
    "http://100.65.3.254:8080",
)
DEFAULT_MODEL = "ggml-large-v3-turbo"
DEFAULT_LANGUAGE = "zh"
DEFAULT_TIMEOUT_SECONDS = 7200.0


def _json_exit(payload: dict, code: int) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    raise SystemExit(code)


def _multipart_body(fields: dict[str, str], file_path: Path) -> tuple[bytes, str]:
    boundary = f"----hermes-whisper-cpp-{uuid.uuid4().hex}"
    content_type = mimetypes.guess_type(str(file_path))[0] or "application/octet-stream"
    chunks: list[bytes] = []

    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                str(value).encode(),
                b"\r\n",
            ]
        )

    chunks.extend(
        [
            f"--{boundary}\r\n".encode(),
            (f'Content-Disposition: form-data; name="file"; filename="{file_path.name}"\r\n').encode(),
            f"Content-Type: {content_type}\r\n\r\n".encode(),
            file_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ]
    )
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def _probe_duration_seconds(file_path: Path) -> float | None:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        return None
    try:
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
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if duration <= 0:
        return None
    return duration


def transcribe(args: argparse.Namespace) -> dict:
    audio_path = Path(args.audio_path).expanduser()
    if not audio_path.is_absolute():
        audio_path = audio_path.resolve()
    if audio_path.is_symlink():
        return {"ok": False, "error": f"Refusing symlink: {audio_path}"}
    if not audio_path.exists():
        return {"ok": False, "error": f"Audio file not found: {audio_path}"}
    if not audio_path.is_file():
        return {"ok": False, "error": f"Path is not a regular file: {audio_path}"}

    model = args.model
    fields = {
        "response_format": "verbose_json",
        "temperature": "0.0",
        "temperature_inc": "0.2",
    }
    if args.language:
        fields["language"] = args.language

    audio_duration = _probe_duration_seconds(audio_path)
    body, content_type = _multipart_body(fields, audio_path)
    started = time.monotonic()
    attempts = []
    for base_url in (url.rstrip("/") for url in args.base_urls):
        request = Request(
            f"{base_url}/inference",
            data=body,
            headers={
                "Content-Type": content_type,
                "Content-Length": str(len(body)),
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=args.timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            attempts.append({"base_url": base_url, "error": f"HTTP {exc.code}: {detail}"})
            continue
        except URLError as exc:
            attempts.append({"base_url": base_url, "error": f"Connection failed: {exc.reason}"})
            continue
        except TimeoutError:
            attempts.append(
                {
                    "base_url": base_url,
                    "error": f"Request timed out after {args.timeout}s",
                }
            )
            continue
        except OSError as exc:
            attempts.append({"base_url": base_url, "error": str(exc)})
            continue

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            attempts.append(
                {
                    "base_url": base_url,
                    "error": "Endpoint returned non-JSON response",
                    "raw": raw,
                }
            )
            continue

        text = str(payload.get("text") or "").strip()
        if not text:
            attempts.append(
                {
                    "base_url": base_url,
                    "error": "Endpoint returned an empty transcript",
                    "raw": payload,
                }
            )
            continue
        break
    else:
        return {
            "ok": False,
            "error": "All whisper.cpp endpoints failed",
            "attempts": attempts,
        }

    elapsed = time.monotonic() - started
    result = {
        "ok": True,
        "base_url": base_url,
        "model": model,
        "language": args.language,
        "detected_language": payload.get("language"),
        "elapsed_seconds": round(elapsed, 3),
        "text": text,
    }
    if "duration" in payload:
        result["service_duration_seconds"] = payload["duration"]
    if audio_duration is not None:
        result["audio_duration_seconds"] = round(audio_duration, 3)
        result["speed_ratio"] = round(audio_duration / elapsed, 3) if elapsed > 0 else None
    if "segments" in payload:
        result["segments"] = [
            {
                "id": segment.get("id"),
                "start": segment.get("start"),
                "end": segment.get("end"),
                "text": str(segment.get("text") or "").strip(),
            }
            for segment in payload["segments"]
            if isinstance(segment, dict)
        ]
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio_path", help="Absolute or relative path to the audio file")
    parser.add_argument(
        "--base-url",
        default=os.getenv("HERMES_WHISPER_BASE_URL"),
        help="Use one whisper.cpp server instead of the default endpoint sequence",
    )
    parser.add_argument(
        "--model",
        default=os.getenv("HERMES_WHISPER_MODEL", DEFAULT_MODEL),
        help=f"Model label to include in output metadata (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--language",
        default=os.getenv("HERMES_WHISPER_LANGUAGE", DEFAULT_LANGUAGE),
        help=f"Language hint, e.g. en or zh (default: {DEFAULT_LANGUAGE})",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"Request timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS:g})",
    )
    args = parser.parse_args()
    args.base_urls = (args.base_url,) if args.base_url else DEFAULT_BASE_URLS

    result = transcribe(args)
    _json_exit(result, 0 if result.get("ok") else 1)


if __name__ == "__main__":
    main()
