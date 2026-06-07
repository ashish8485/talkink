# Contributing to Söyle

Thanks for your interest! Söyle is a small, focused macOS app — contributions and
issues are welcome.

## Build

See [BUILDING.md](BUILDING.md). The key points:

- **Use `xcodebuild`, not `swift build`** — MLX's Metal shader library is only compiled
  by Xcode's build system. `scripts/build_app.sh Release` handles this.
- Requires **full Xcode 16+** (the Metal compiler), Apple Silicon, macOS 14+.
- Swift tools 6.0, language mode v5.

## Before opening a PR

- Build the app and run the headless self-test on a sample clip:
  ```bash
  scripts/build_app.sh Release
  "dist/Söyle.app/Contents/MacOS/Soyle" --selftest path/to/16k-mono.wav
  ```
- If you touch the engine, also smoke-test the CLI (`soyle-cli`).
- Run the app and exercise push-to-talk → transcribe → paste, plus the History tab.
- Keep the UI and all user-facing strings in **English**.

## Conventions

- Match the surrounding style; keep comments meaningful and in English.
- The `mlx-audio-swift` dependency is pinned to a commit in `Package.swift`; bump it
  deliberately in its own commit and re-test.
- Permissions model: Microphone + Input Monitoring are required; Accessibility is
  optional (auto-paste). Don't add permissions without a strong reason.
- Privacy is a feature: no telemetry, no analytics. The only network calls are the
  first-run model download and the optional update check.

## Reporting bugs

Open an issue with: macOS version, Mac model, what you did, what happened vs. expected,
and any relevant Console logs. For audio/permission issues, mention which permissions
are granted (System Settings → Privacy & Security).

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).
