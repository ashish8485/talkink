<div align="center">

<img src="assets/hero.png" alt="Talkink — Say it. It's written." width="880"/>

# Talkink

Push-to-talk dictation for macOS, **100% on-device**. Hold a key, speak, release —
your text is transcribed locally and pasted right at your cursor. Powered by
**NVIDIA Nemotron 3.5 ASR** via **MLX**.

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black)
![License](https://img.shields.io/badge/license-MIT-76B900)

### 🌐 **[talkink.app](https://talkink.app)** — website & one-click download

<br/>

<img src="assets/demo.gif" alt="Hold a key, speak, release — the text is pasted at the cursor" width="760"/>

</div>

---

## Why Talkink

- 🔒 **Local & private** — your voice and text never leave your Mac. No cloud, no subscription.
- ⚡ **Fast** — ~30–40× faster than real time on a MacBook Air M4 (8-bit model).
- 🌍 **Multilingual** — auto-detects across the model's ~40 locales; 9 fixed locales selectable (EN/FR/DE/ES/IT/PT/TR/AR/NL). Punctuation & capitalization included.
- ⌨️ **Paste anywhere** — auto-pastes at the cursor; always on the clipboard as a fallback.
- 📜 **History** — every transcription is kept locally and is searchable / re-copyable in-app.
- 🟢 **Open source** (MIT), 100% native Swift — no Python at runtime.

## How it works

1. Talkink lives in the menu bar (no Dock icon).
2. **Hold** the push-to-talk key (Right Option ⌥ by default) → recording starts.
3. **Speak.**
4. **Release** → local transcription in a fraction of a second → text is **pasted at your cursor** (if Accessibility is granted) and **copied to the clipboard**.
5. It's also saved to **History** in case you need it again.

A floating pill (NVIDIA green) shows the state: recording → transcribing → done.

## Screenshots

<p align="center">
  <img src="assets/screenshot-settings.png" width="380" alt="Settings & permissions"/>
  &nbsp;&nbsp;
  <img src="assets/screenshot-menu.png" width="300" alt="Menu bar"/>
</p>

<p align="center"><i>The recording pill, reacting to your voice:</i></p>
<p align="center"><img src="assets/pill.gif" width="420" alt="Recording pill"/></p>

## Install

**Requirements:** Apple Silicon Mac (M1–M5), macOS 14 or later.

### 1. Download & install

1. Download **`Talkink.dmg`** from the [**latest release**](https://github.com/hasso5703/talkink/releases/latest).
2. Open it and drag **Talkink** onto the **Applications** folder, then eject the disk image.
3. Launch Talkink from Applications. No security warning — Talkink is **signed and
   notarized by Apple** (since v0.3.0).

> <a name="is-it-safe"></a>**Is it safe?** Yes, twice over: the download is notarized by Apple
> (scanned and ticketed), *and* Talkink is fully open source — you can read every line in this
> repo and [build it yourself](BUILDING.md).

> **Coming from Söyle (Talkink's former name, ≤ v0.3.3)?** Your settings and history carry
> over automatically. If push-to-talk stops responding, remove the old **Söyle** entries from
> System Settings → Privacy & Security → *Input Monitoring* and *Accessibility* (− button),
> then add **Talkink** and enable it — one time.

### 2. Grant permissions (the onboarding window guides you)

| Permission | Why | Note |
|---|---|---|
| **Microphone** | To hear you | — |
| **Input Monitoring** | Detect the push-to-talk key everywhere | On macOS 26 you may need to add Talkink yourself: “+” or drag Talkink.app into the list (Talkink opens the pane and a Finder window for you) |
| **Accessibility** *(optional)* | Paste at the cursor | Skip it and Talkink just copies to the clipboard (paste with ⌘V) |

### 3. Use it

On the **first** transcription, Talkink downloads the model (~1.2 GB) once — you'll see
*"Loading model…"*. After that: **hold Right Option ⌥, speak, release** → your text appears at
the cursor and on the clipboard. That's it. 🎤

---

### Build from source (developers)

```bash
git clone https://github.com/hasso5703/talkink.git
cd talkink
scripts/build_app.sh Release
open dist/Talkink.app
```

Requires **full Xcode 16+** (the Metal compiler is needed — see [BUILDING.md](BUILDING.md)).
A locally built app is signed with your own (or an ad-hoc) identity and runs directly.

## Settings

Menu bar → **Open Talkink** → *Settings* tab:

- **Push-to-talk key** — Right Option (default), Left Option, Right Control, or Fn / 🌐.
- **Language** — Auto (detect) or a fixed locale.
- **Model** — **bf16** (default, best quality) or **8-bit** (fastest).
- **Auto-paste at cursor**, feedback sounds, launch at login, check for updates.

## Network activity

Talkink's transcription is 100% on-device. The only network calls are:

1. **First-run model download** (~1.2 GB bf16, or ~756 MB if you pick 8-bit) from Hugging Face into `~/.cache/huggingface`.
2. **Update check** (optional, toggle in Settings) — a request to the GitHub Releases API at launch. No usage telemetry is sent.

## Troubleshooting

- **Push-to-talk does nothing** → grant **Input Monitoring** (System Settings → Privacy & Security → Input Monitoring). Talkink re-arms itself within a few seconds; relaunch it if the key still does nothing.
- **Talkink doesn't appear in the Input Monitoring list** → a macOS 26 issue that hits many apps (Karabiner-Elements included): answering the permission prompt doesn't register the app. Click **“+”** in the list (or drag `Talkink.app` into it), then enable the toggle.
- **After updating from an old version (Söyle ≤ v0.2.0), the key/auto-paste stopped working** (toggles look on but do nothing) → macOS ties permissions to the app's code signature, and early builds were signed differently. In System Settings → Privacy & Security, **remove** the old *Söyle* entries from *Input Monitoring* and *Accessibility* (− button), then add **Talkink** and enable it. One time — the identity has been stable since v0.3.0.
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

**The downloaded model is governed by NVIDIA's model license, not MIT.** By using Talkink you agree to it.

## Roadmap

- [ ] Live text while you speak (streaming `generateStream`)
- [x] Notarized + [Sparkle](https://sparkle-project.org) in-app auto-update (v0.3.0)
- [ ] Homebrew cask
- [ ] Custom dictionary (proper nouns, jargon)
- [ ] Hands-free toggle mode

## License

Talkink's code is [MIT](LICENSE). See the table above for component and model licenses.
