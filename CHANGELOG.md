# Changelog

## v0.1.0

First release. Local push-to-talk dictation for Apple Silicon, powered by NVIDIA
Nemotron 3.5 ASR via MLX — 100% native Swift, no Python at runtime.

### Features
- **Push-to-talk** global hotkey (listen-only `CGEventTap` + Input Monitoring): hold a
  key, speak, release → transcribe → paste. Default key: Right Option ⌥; rebindable.
- **Auto-paste at the cursor** (synthetic ⌘V via Accessibility), with the transcript
  always placed on the clipboard as a fallback. Toggleable.
- **History** — every transcription is saved locally (up to 500, at
  `~/Library/Application Support/Soyle/history.json`), searchable and re-copyable in-app.
- **Native Nemotron 3.5 ASR** engine on `mlx-audio-swift`, warmed up at launch for an
  instant first transcription. ~30–40× real time on a MacBook Air M4 (8-bit).
- Menu-bar app (no Dock icon) with a floating recording overlay (live waveform, NVIDIA green).
- Settings: push-to-talk key, language (auto + 9 locales), model (**8-bit** default / **bf16**),
  auto-paste, feedback sounds, launch at login, check-for-updates.
- Update notifier: checks GitHub Releases and surfaces a "new version available" notice.
- `soyle-cli` for headless transcription/benchmarking; `--selftest` mode.

### Robustness
- In-session re-arm of the push-to-talk tap once Input Monitoring is granted (no relaunch).
- Recovers from a mid-recording microphone unplug / device or route change.
- Retries the model load on next activation if the first attempt fails (e.g. offline).
- Serialized MLX inference; guards against sub-0.1s audio.
- Stress-tested: silence, 0.15s, 44.1 kHz stereo (resample+downmix), noise, 55s (chunked).

### Distribution
- Open source (MIT). **Not notarized** — download builds need a one-time
  `xattr -dr com.apple.quarantine`, or build from source. Notarization + Sparkle
  auto-update are on the roadmap.
