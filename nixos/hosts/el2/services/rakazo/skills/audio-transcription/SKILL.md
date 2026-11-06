---
name: audio-transcription
description: Transcribe an existing audio file, including long recordings, and use its timestamped transcript for summaries, quotations, or translation.
---

# Audio Transcription

Use the installed `transcribe-audio` and `estimate-transcription-time` commands.
They call the provisioned external ASR services; do not install or run a speech
model in the Bot computer. This workflow handles files, independently of Rakazo
microphone dictation or voice-message transcription.

Locate the input file in the Bot workspace and estimate its processing time:

```bash
estimate-transcription-time /absolute/path/to/recording.m4a
```

The estimate uses a measured speed ratio of 49.04 audio seconds per processing
second. Treat it as an estimate and report the actual `speed_ratio` when returned.

Start one whole-file request as an independent background shell command:

```bash
mkdir -p exports
nohup transcribe-audio --language zh /absolute/path/to/recording.m4a < /dev/null > exports/transcript.json 2> exports/transcription.log &
```

Read the log/result in later `shell` calls. A shell timeout does not mean the
background transcription failed;
do not start a second request while the first is running. Use a distinct output
name when processing another recording. Keep requests sequential and do not split
the recording: both services accept a whole-file request, and parallel calls
increase latency without improving observed throughput.

The language defaults to Chinese (`zh`); use `--language en` or another language
when appropriate. Supported inputs include WAV, MP3, M4A, OGG, WebM, FLAC, and AAC.

After the command exits, parse the JSON and check `ok` before using its `text`.
Preserve the returned `segments` timestamps for quotations and time references.
If plain text is requested, derive it from this result rather than transcribing
again. On failure, read `error` and the stderr log before deciding what to do next.

Save user-facing transcripts, subtitles, or summaries under the current Bot
workspace's `exports/`. Deliver them with `attach_file` using a relative path,
such as `exports/transcript.json`.
