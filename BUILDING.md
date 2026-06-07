# Building Söyle

Söyle is a SwiftPM package; the GUI app is assembled into `Söyle.app` by a script.
**You must build with `xcodebuild` (not `swift build`)** — MLX's Metal shader library
(`default.metallib`) is only compiled by Xcode's build system. A bare `swift build`
produces a binary that fails at runtime with *"Failed to load the default metallib."*

## Requirements

- Apple Silicon Mac (M-series), macOS 14+
- **Full Xcode 16+** (not just Command Line Tools — the Metal compiler is required)
- ~2 GB free disk for the build + model weights

## Build the app

```bash
scripts/build_app.sh Release      # or: Debug
```

This:
1. runs `xcodebuild -scheme Soyle` (compiles Swift + MLX C++ + Metal shaders),
2. assembles `dist/Söyle.app`,
3. copies `mlx-swift_Cmlx.bundle` (which contains `default.metallib`) into
   `Contents/Resources/` — **required**, or the app can't run MLX,
4. code-signs the bundle (uses the `Soyle Dev` identity if present, else ad-hoc).

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
scripts/make_icns.sh        # regenerates packaging/AppIcon.icns from make_icon.swift
```

## Stable local signing (avoid re-granting permissions on every rebuild)

Ad-hoc signatures change on every build, which invalidates macOS permission grants
(Microphone / Input Monitoring) and forces you to re-authorize. Create a stable,
self-signed local identity once:

```bash
scripts/dev_sign_setup.sh    # asks for your Mac password to trust the local cert
```

After that, `build_app.sh` auto-signs with `Soyle Dev` and grants persist across rebuilds.
This identity is local-only; it does **not** make the app distributable to other Macs.

## Cutting a release (Path B — unsigned/unnotarized)

Releases are produced by CI (`.github/workflows/release.yml`) on a tag push:

```bash
# bump the version in packaging/Info.plist (CFBundleShortVersionString), commit, then:
git tag v0.1.0
git push origin main --tags
```

CI builds on `macos-15` with Xcode 16, runs the self-test, zips the app with `ditto`
(preserves the code signature and symlinks — plain `zip` corrupts them), and creates a
GitHub Release with the `Soyle.zip` asset. The in-app updater points at the latest release.

> **Distribution reality:** Söyle is **not notarized**. A downloaded build is quarantined
> by Gatekeeper on macOS Sequoia; users clear it with
> `xattr -dr com.apple.quarantine /Applications/Söyle.app` (documented in the README).
> Notarization (Apple Developer ID, $99/yr) would remove that friction and unlock Sparkle
> auto-update — tracked on the roadmap.

## Notes

- The `mlx-audio-swift` dependency is pinned to a specific commit in `Package.swift`
  (it tracks `main` with no release tag). Bump it deliberately.
- Permissions used: **Microphone** + **Input Monitoring** (global push-to-talk tap) +
  **Accessibility** (optional — auto-paste at the cursor). Without Accessibility, Söyle
  falls back to clipboard-only.
