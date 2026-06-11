# Building Talkink

Talkink is a SwiftPM package; the GUI app is assembled into `Talkink.app` by a script.
**You must build with `xcodebuild` (not `swift build`)** — MLX's Metal shader library
(`default.metallib`) is only compiled by Xcode's build system. A bare `swift build`
produces a binary that fails at runtime with *"Failed to load the default metallib."*

## Requirements

- Apple Silicon Mac (M-series), macOS 14+
- **Full Xcode 16+** (not just Command Line Tools — the Metal compiler is required)
- ~5 GB free disk for the build + the default model's weights

## Build the app

```bash
scripts/build_app.sh Release      # or: Debug
```

This:
1. runs `xcodebuild -scheme Soyle` (compiles Swift + MLX C++ + Metal shaders),
2. assembles `dist/Talkink.app`,
3. copies `mlx-swift_Cmlx.bundle` (which contains `default.metallib`) into
   `Contents/Resources/` — **required**, or the app can't run MLX,
4. embeds `Sparkle.framework` (auto-updates) and re-signs its components,
5. code-signs the bundle with hardened runtime + `packaging/Soyle.entitlements`
   (identity order: `Developer ID Application` → local `Soyle Dev` → ad-hoc).

Output: `dist/Talkink.app`. First dictation downloads the selected model (~2.5 GB
for the default Qwen3-ASR 1.7B 8-bit) from Hugging Face into `~/.cache/huggingface`.

## Headless self-test (no GUI / mic / permissions)

Verifies the bundled Metal library + model + transcription:

```bash
"dist/Talkink.app/Contents/MacOS/Soyle" --selftest path/to/audio.wav
```

And the microphone capture pipeline (incl. the hardened-runtime audio-input
entitlement; records ~1.2 s and reports sample count + RMS):

```bash
"dist/Talkink.app/Contents/MacOS/Soyle" --mictest
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

## Notes

- The `mlx-audio-swift` dependency is pinned to a specific commit in `Package.swift`
  (it tracks `main` with no release tag). Bump it deliberately.
- Permissions used: **Microphone** + **Input Monitoring** (global push-to-talk tap) +
  **Accessibility** (optional — auto-paste at the cursor). Without Accessibility, Talkink
  falls back to clipboard-only.

## Release: Developer ID + notarization + Sparkle

One-time setup (after enrolling in the Apple Developer Program):

1. Xcode → Settings → Accounts → your Apple ID → *Manage Certificates…* → "+"
   → **Developer ID Application**. `build_app.sh` prefers it automatically over
   the local "Soyle Dev" identity.
2. Notarization credentials (app-specific password from account.apple.com):
   ```bash
   xcrun notarytool store-credentials soyle-notary \
     --apple-id YOU@EXAMPLE.COM --team-id TEAMID --password app-specific-pw
   ```
3. Sparkle update-signing keys (private key stays in your login keychain):
   ```bash
   BIN=$(ls -d DerivedData/SourcePackages/artifacts/sparkle*/Sparkle/bin | head -1)
   "$BIN/generate_keys"   # paste the printed public key into packaging/Info.plist (SUPublicEDKey)
   ```

Per release:

```bash
scripts/build_app.sh Release        # Developer ID + hardened runtime + entitlements
scripts/notarize.sh                 # upload → wait → staple → dist/Talkink.zip
gh release create vX.Y.Z dist/Talkink.zip --title "Talkink vX.Y.Z" --notes "…"
scripts/make_appcast.sh vX.Y.Z dist/Talkink.zip
git add appcast.xml && git commit -m "release: appcast for vX.Y.Z" && git push
```

Sparkle-equipped installs (≥ v0.3.0) then update in-app automatically.
