<div align="center">

<img src="assets/icon.png" width="120" alt="Söyle"/>

# Söyle

**Say it. It's written.**

Push-to-talk dictation for macOS that runs **100% on your Mac**.
Hold a key, speak, release — your speech is transcribed locally and pasted at your
cursor (and copied to the clipboard). Powered by **NVIDIA Nemotron 3.5 ASR** via **MLX**.

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black)
![License](https://img.shields.io/badge/license-MIT-76B900)

</div>

---

## Why Söyle

- 🔒 **Local & private** — your voice and text never leave your Mac. No cloud, no subscription.
- ⚡ **Fast** — ~30–40× faster than real time on a MacBook Air M4 (8-bit model).
- 🌍 **Multilingual** — auto-detects across the model's ~40 locales; 9 fixed locales selectable (EN/FR/DE/ES/IT/PT/TR/AR/NL). Punctuation & capitalization included.
- ⌨️ **Paste anywhere** — auto-pastes at the cursor; always on the clipboard as a fallback.
- 📜 **History** — every transcription is kept locally and is searchable / re-copyable in-app.
- 🟢 **Open source** (MIT), 100% native Swift — no Python at runtime.

## How it works

1. Söyle lives in the menu bar (no Dock icon).
2. **Hold** the push-to-talk key (Right Option ⌥ by default) → recording starts.
3. **Speak.**
4. **Release** → local transcription in a fraction of a second → text is **pasted at your cursor** (if Accessibility is granted) and **copied to the clipboard**.
5. It's also saved to **History** in case you need it again.

A floating pill (NVIDIA green) shows the state: recording → transcribing → done.

## Install

> **Honest note on distribution.** Söyle is open source and **not notarized by Apple** (yet).
> On macOS Sequoia, a *downloaded* unsigned app is blocked by Gatekeeper on first launch.
> Two options below — the one-time `xattr` command clears the quarantine flag.

### Option 1 — Download (quickest)

1. Grab the latest `Soyle.zip` from [**Releases**](https://github.com/hasso5703/soyle/releases/latest).
2. Unzip and move **Söyle.app** to `/Applications`.
3. Clear the quarantine flag (one time), then open it:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Söyle.app
   open /Applications/Söyle.app
   ```

### Option 2 — Build from source (for developers)

```bash
git clone https://github.com/hasso5703/soyle.git
cd soyle
scripts/build_app.sh Release
open dist/Söyle.app
```

Requires **Xcode 16+** (the Metal compiler is needed — see [BUILDING.md](BUILDING.md)).
The model (~756 MB, 8-bit) downloads on first launch.

## Permissions

| Permission | Why | Required? |
|---|---|---|
| **Microphone** | Record your voice | Yes |
| **Input Monitoring** | Detect the push-to-talk key globally | Yes (relaunch Söyle after granting) |
| **Accessibility** | Auto-paste at the cursor (synthetic ⌘V) | Optional — without it, text stays on the clipboard (paste with ⌘V) |

The onboarding window walks you through these on first launch.

## Settings

Menu bar → **Open Söyle** → *Settings* tab:

- **Push-to-talk key** — Right Option (default), Left Option, Right Control, or Fn / 🌐.
- **Language** — Auto (detect) or a fixed locale.
- **Model** — **8-bit** (default, fast) or **bf16** (max accuracy).
- **Auto-paste at cursor**, feedback sounds, launch at login, check for updates.

## Network activity

Söyle's transcription is 100% on-device. The only network calls are:

1. **First-run model download** (~756 MB) from Hugging Face into `~/.cache/huggingface`.
2. **Update check** (optional, toggle in Settings) — a request to the GitHub Releases API at launch. No usage telemetry is sent.

## Troubleshooting

- **Push-to-talk does nothing** → grant **Input Monitoring** (System Settings → Privacy & Security → Input Monitoring), then **relaunch** Söyle (the grant only applies after relaunch).
- **It stopped working after rebuilding from source** → ad-hoc signatures change each build; run `scripts/dev_sign_setup.sh` once to create a stable local signing identity so grants persist.
- **Using Fn / 🌐 as the key** → set System Settings → Keyboard → "Press 🌐 to" = **Do Nothing**.
- **Model download stalls** → check your connection and `~/.cache/huggingface`.

## Tech stack & credits

| Component | Role | License |
|---|---|---|
| [NVIDIA Nemotron 3.5 ASR](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) | The model (cache-aware FastConformer-RNNT, 600M, ~40 locales) | NVIDIA model license (OpenMDW-1.1) — see model card |
| [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | Native Swift/MLX implementation of Nemotron (Prince Canuma) | MIT |
| [mlx-community](https://huggingface.co/mlx-community) | MLX-converted weights (8-bit / bf16) | per model license |
| [MLX](https://github.com/ml-explore/mlx-swift) | Compute on Apple Silicon (Apple) | MIT |

**The downloaded model is governed by NVIDIA's model license, not MIT.** By using Söyle you agree to it.

## Roadmap

- [ ] Live text while you speak (streaming `generateStream`)
- [ ] Notarized DMG + [Sparkle](https://sparkle-project.org) auto-update + Homebrew cask
- [ ] Custom dictionary (proper nouns, jargon)
- [ ] Hands-free toggle mode

## License

Söyle's code is [MIT](LICENSE). See the table above for component and model licenses.
