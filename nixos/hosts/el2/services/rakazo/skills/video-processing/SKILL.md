---
name: video-processing
description: Download online video or audio with yt-dlp, inspect media, and use ffmpeg to extract, trim, convert, or combine video, audio, and subtitles.
---

# Video Download and Processing

The computer provides `yt-dlp` with bundled EJS scripts, `ffmpeg`, `ffprobe`, Node 22, and npm. Work in the
current Bot workspace and put deliverables in `exports/`.

Inspect available formats or source metadata before choosing a download:

```bash
yt-dlp --js-runtimes node --list-formats 'VIDEO_URL'
```

For a download that may outlast a shell call, launch it independently and follow
the log in later `shell` calls:

```bash
mkdir -p exports
nohup yt-dlp --js-runtimes node -o 'exports/%(title).150B [%(id)s].%(ext)s' 'VIDEO_URL' < /dev/null > exports/download.log 2>&1 &
```

Select formats, audio extraction, subtitles, resolution, and output size to match
the user's request. The installed yt-dlp includes curl-cffi support; use its
impersonation options only when the source requires them.

Use `ffprobe` to inspect duration, streams, codecs, and dimensions. Prefer stream
copy for a lossless extraction or trim when the requested format and cut points
allow it; re-encode when needed for accurate cuts, filters, or compatibility.
Inspect the resulting file and confirm its streams and duration before delivery.

Use the audio-transcription Skill for speech transcription after extracting or
downloading the audio. Processing and playback tools do not themselves establish
what was said in a recording.

Attach completed media or subtitle files with `attach_file` and a relative path
such as `exports/clip.mp4`. Keep logs separate from user-facing outputs.
