---
name: audio-transcription
description: "Transcribe audio files and estimate transcription time. Use when the user asks to transcribe, summarize, inspect, translate, or quote speech from an audio file."
license: MIT
metadata:
  hermes:
    tags: [Audio, Transcription, STT]
---

# Audio Transcription

Transcribe speech from an existing audio file such as `.wav`, `.mp3`, `.m4a`,
`.ogg`, `.webm`, `.flac`, or `.aac`.

The audio must be available at a file path accessible to the terminal. This
skill is not needed for live microphone voice mode or messaging voice notes
that Hermes has already converted into text.

Always run transcription as a Hermes background terminal task. Do not run the
transcription command in the foreground.

## Command

Start the transcription:

```bash
transcribe-audio \
  --language zh \
  /absolute/path/to/audio.m4a \
  > /tmp/hermes-transcript.json
```

Use `terminal(background=true, notify_on_complete=true)` for that command. After
the background task starts, use `process(action="poll")` or
`process(action="wait")` to check status. A `process(action="wait")` timeout only
means the wait call reached the Hermes wait limit; it does not mean the
transcription failed. Poll again later instead of restarting the transcription.

Default language:

```text
zh
```

Measured baseline on the preferred transcription service:

```text
speed_ratio = audio_duration_seconds / transcription_elapsed_seconds = 49.04
```

For example, a 2720.8 second recording is expected to take about 55.5 seconds
with this baseline. Use the estimate script below before long transcriptions.

## Workflow

1. Confirm the user supplied an accessible audio path, or locate the audio file
   path from the current task context.
2. Estimate the transcription time with `estimate-transcription-time`.
3. Start one background transcription command for the whole file.
4. Poll the background process until it exits.
5. Read the JSON output file and use the returned `text` field as the
   transcript.
6. Report the actual `speed_ratio` if it is present in the JSON output.
7. If the user asked for a summary, translation, timestamps, or extraction,
   perform that work from the transcript.

## Estimate

```bash
estimate-transcription-time \
  /absolute/path/to/audio.m4a
```

The estimate script prints JSON with `audio_duration_seconds`, `speed_ratio`,
and `estimated_transcription_seconds`.

## Options

```bash
transcribe-audio \
  --language en \
  /absolute/path/to/audio.wav
```

## Output

On success, the script prints JSON:

```json
{
  "ok": true,
  "language": "zh",
  "detected_language": "chinese",
  "elapsed_seconds": 0.612,
  "audio_duration_seconds": 30.0,
  "speed_ratio": 49.02,
  "text": "...",
  "segments": [
    {"id": 0, "start": 0.0, "end": 4.92, "text": "..."}
  ]
}
```

On failure, it exits non-zero and prints JSON with `ok: false` and `error`.

## Notes

- Do not install or run a speech model inside the Hermes VM. Use the
  provisioned `transcribe-audio` command.
- Do not split audio files for this skill. Use one whole-file request.
- Do not make parallel transcription API calls. Parallel calls increase
  per-request latency and do not improve observed throughput on either
  transcription service.
- Keep timestamps when transcribing. If the user only wants plain text, strip
  timestamps after reading the returned `segments`.
