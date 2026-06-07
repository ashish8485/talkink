# Changelog

## v0.1.0 — 2026-06-07

First release. Local push-to-talk dictation for Apple Silicon, powered by NVIDIA
Nemotron 3.5 ASR via MLX — 100 % native Swift, no Python at runtime.

### Added
- **Push-to-talk** global hotkey (listen-only `CGEventTap`, Input Monitoring): hold a
  key, speak, release → transcribe → copy to clipboard. Default key: Right Option ⌥.
- **Native Nemotron 3.5 ASR** engine (`SoyleKit`) on `mlx-audio-swift`, with model
  warm-up at launch for instant first transcription.
- **Menu-bar app** (no Dock icon) with live state, plus an **onboarding/settings window**
  (NVIDIA green): permission status, push-to-talk key, language (auto + 9 locales),
  model (**8-bit** default / **bf16**), feedback sounds, launch-at-login.
- **Floating recording overlay** with a live waveform meter.
- 16 kHz mono capture via `AVAudioEngine` + `AVAudioConverter` (resample + downmix).
- Clipboard-only output (no Accessibility permission required).
- `soyle-cli` for headless transcription/benchmarking and `--selftest` mode.
- `scripts/build_app.sh` (xcodebuild → `.app` + bundled Metal library → ad-hoc sign),
  `scripts/make_icns.sh` (app icon).

### Verified
- Native inference on MacBook Air M4: ~30–40× real time (8-bit), JFK sample transcribed
  verbatim; FR near-verbatim.
- Stress-tested (no crashes): silence, 0.15 s clip, 44.1 kHz stereo (resample+downmix),
  pink noise, 55 s clip (chunked).

### Known limitations
- Ad-hoc signed (no notarization yet) → first launch may need *Open Anyway* if downloaded.
- Live test of the global hotkey + mic requires granting Microphone + Input Monitoring.
- Streaming live-text (`generateStream`) not yet wired into the UI.
