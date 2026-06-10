# Changelog

## v0.4.0 — Söyle becomes **Talkink**

Talk. Ink. New name, new home — same app, same privacy.

### Changed
- **Renamed to Talkink** (talk → ink: you speak, it writes). Website:
  **[talkink.app](https://talkink.app)**. Your settings, history and
  permissions carry over (the internal identifiers are unchanged).
- Update feed now served from talkink.app (legacy feed kept for old installs).
- Release assets are now `Talkink.dmg` / `Talkink.zip`.

### For existing users
- The app file becomes `Talkink.app` after the update. If push-to-talk stops
  responding, remove the old *Söyle* entries in System Settings → Privacy &
  Security (*Input Monitoring*, *Accessibility*) and add **Talkink** — one time.

## v0.3.3

First-real-user release — every change below comes from watching a
non-technical person install and use Söyle.

### Changed
- **First launch now asks which language you'll speak** (changeable anytime):
  an explicit language transcribes noticeably better than auto-detect.
- **bf16 model is the default** (best quality; ~1.2 GB one-time download) —
  8-bit stays available in Settings for maximum speed.
- **The DMG teaches the install**: branded background, "Drag into
  Applications" with the icons positioned around an arrow.
- Input Monitoring onboarding now leads with the “+” instruction (macOS 26
  never lists apps by itself).

## v0.3.2

### Fixed
- The app now reliably relaunches after an in-app update. Sparkle's installer
  agent proved flaky at relaunching an app updated in place (verified on
  macOS 26; upstream Sparkle #273/#1717): Söyle now spawns its own detached
  relauncher that waits for the old instance to exit and opens the updated
  app. Updater errors are also logged for diagnosis.

## v0.3.1

### Fixed
- Worked around a macOS 26 (Tahoe) issue — also hitting Karabiner-Elements and
  others — where answering the Input Monitoring prompt does not add the app to
  the list: Söyle now opens the right Settings pane **and** reveals Söyle.app
  in the Finder so you can drag it straight into the list; onboarding hints
  explain the manual add.

### Changed
- Downloads now ship as a **drag-to-Applications DMG** (notarized + stapled),
  alongside the zip used by the in-app updater.

## v0.3.0

### Distribution
- **Signed & notarized by Apple** (Developer ID, hardened runtime) — download,
  drag to Applications, open. No Gatekeeper warning, no `xattr`, no "Open
  Anyway". One-time permission re-grant when coming from v0.1.0/v0.2.0 (the
  signing identity changed — it is stable from now on).
- **In-app auto-updates via Sparkle 2.9.3** (replaces the GitHub release
  notifier): "Check for Updates…" in the menu, automatic-checks toggle in
  Settings, EdDSA-signed update feed.
- Release tooling: `scripts/notarize.sh` (submit → staple → Gatekeeper-assess
  → package) and `scripts/make_appcast.sh`; `build_app.sh` prefers a
  Developer ID identity, signs nested code individually (no `--deep`).

### Changed
- First run shows "Downloading model (~756 MB, one-time)…" in the menu and the
  pill while the weights download, instead of a silent wait.
- New `--mictest` headless mode (capture pipeline + entitlement check).

## v0.2.0

### Fixed
- The recording pill now appears attached to the window you're dictating into
  (focused window via Accessibility, window-list fallback — no new permission)
  instead of a fixed spot at the bottom of the primary screen. It used to land
  on whatever window sat behind when the active window was small, and on the
  wrong display on multi-screen setups. Fullscreen Spaces verified unaffected.
- The microphone can no longer be left recording: switching models mid-hold
  orphaned the recorder (mic stayed hot, the next dictation shipped minutes of
  background audio to the model). Every exit path now stops it.
- The end of the last word is no longer clipped — capture continues 0.25s
  after the key is released and the resampler's buffered tail is drained.
- Releasing the push-to-talk key while the other key of the same modifier was
  also held (e.g. both Options) no longer leaves the recording stuck on.
- Switching models while a load is in flight can no longer install stale
  weights or show Ready with the wrong model; stale transcription completions
  can't clobber a newer dictation's UI.

### Privacy
- Text dictated into a secure (password) field stays out of the on-disk
  history — clipboard only.

### Changed
- The pill says "Pasted" when auto-paste actually inserted at the cursor,
  "Copied" otherwise.
- Permission status is polled only while the Söyle window is open.
- Input Monitoring guidance reflects the in-session re-arm (relaunch is a
  fallback); README documents the permission re-grant needed after updating
  a non-notarized build.
- `soyle-cli` accepts multiple audio files in a single run (one model load).

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
