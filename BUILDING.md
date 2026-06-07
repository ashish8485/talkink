# Building Söyle

Söyle is a SwiftPM package. The GUI app is assembled into `Söyle.app` by a build
script. **You must build with `xcodebuild` (not `swift build`)** because MLX's Metal
shader library (`default.metallib`) is only compiled by Xcode's build system — a bare
`swift build` produces a binary that fails at runtime with *"Failed to load the default
metallib."*

## Requirements

- Apple Silicon Mac (M-series), macOS 14+
- Xcode 16+ (full Xcode, not just Command Line Tools — needed for the Metal compiler)
- ~2 GB free disk for the build + model weights

## Build the app

```bash
scripts/build_app.sh Release      # or: Debug
```

This:
1. runs `xcodebuild -scheme Soyle` (compiles Swift + MLX C++ + Metal shaders),
2. assembles `dist/Söyle.app`,
3. copies `mlx-swift_Cmlx.bundle` (containing `default.metallib`) into
   `Contents/Resources/` — **required**, else the app can't run MLX,
4. ad-hoc code-signs the bundle.

Output: `dist/Söyle.app`. First launch downloads the model (~756 MB, 8-bit) from
Hugging Face into `~/.cache/huggingface`.

## Headless self-test (no GUI / mic / permissions)

Verifies the bundled Metal library + model + transcription:

```bash
"dist/Söyle.app/Contents/MacOS/Soyle" --selftest path/to/audio.wav
```

## CLI / benchmarking

```bash
xcodebuild -scheme soyle-cli -configuration Release -derivedDataPath ./DerivedData \
  -destination 'platform=macOS,arch=arm64' build
"DerivedData/Build/Products/Release/soyle-cli" audio.wav --lang fr-FR
```

## App icon

```bash
scripts/make_icns.sh        # regenerates packaging/AppIcon.icns
```

## Notes

- The `mlx-audio-swift` dependency is pinned to a specific commit in `Package.swift`
  (it tracks `main` with no release tag). Bump deliberately.
- Distribution is **ad-hoc signed** (no Apple Developer account). On first launch macOS
  Gatekeeper will warn; the user approves via System Settings → Privacy & Security →
  *Open Anyway*. A notarized build (for warning-free distribution) requires a Developer
  ID certificate + `notarytool`; see `scripts/notarize.sh` (TODO) when an account is available.
- Permissions used: **Microphone** + **Input Monitoring** (for the global push-to-talk
  tap). No Accessibility permission — Söyle copies to the clipboard rather than auto-pasting.
