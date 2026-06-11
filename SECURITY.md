# Security & Privacy

## Privacy posture

Talkink is designed to keep your data on your machine:

- **Speech & transcripts never leave your Mac.** Transcription runs locally on Apple
  Silicon via MLX. Audio is processed in memory; transcripts are stored only in a local
  file (`~/Library/Application Support/Soyle/history.json`).
- **No telemetry, no analytics, no accounts.**
- **Network calls** are limited to two, both inspectable in the source:
  1. Model downloads (~2.5 GB for the default model; 760 MB–4.1 GB depending on your
     pick) from Hugging Face into `~/.cache/huggingface`
     (`Sources/SoyleKit/ModelDownloader.swift`).
  2. An optional [Sparkle](https://sparkle-project.org) update check against the
     EdDSA-signed appcast at `talkink.app` (`Sources/Soyle/Updater.swift`) — disable
     it in Settings. Update archives download from GitHub Releases.

## Permissions

- **Microphone** — to record while the push-to-talk key is held.
- **Input Monitoring** — to detect the push-to-talk key globally (listen-only event tap).
- **Accessibility** — optional; only used to paste at the cursor (synthetic ⌘V). Without
  it, Talkink falls back to copying to the clipboard.

## Reporting a vulnerability

Please open a GitHub issue, or for sensitive reports contact the maintainer privately via
the email on the GitHub profile. We'll acknowledge and respond as quickly as we can.
