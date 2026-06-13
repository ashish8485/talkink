#!/usr/bin/env python3
"""Render a zoomed close-up of the Talkink pill, frame by frame.

Faithful to Overlay.swift: dark capsule, NVIDIA-green border + glow, pulsing
record dot, 7-bar LiveWaveform, real labels ("Speak...", "Transcribing...",
"Pasted"). Two things differ from make_demo.py on purpose:

  1. No window. Just the pill, big, on the brand background (for social).
  2. The waveform REACTS TO THE VOICE: the mic `level` follows a synthesized
     speech envelope (syllable bursts with dips), instead of being pinned at a
     constant 0.75 (which only looks like a steady wave). Same height formula
     as the app: amp = 5 + level*19*(0.45 + 0.55*wave).

The clip runs one full cycle and ENDS on "Pasted": pop-in -> Speak (voice) ->
Transcribing -> Pasted (held to the last frame). It also applies the real
.frame(minWidth: 150), so the pill barely changes width between states.

Usage:  python3 scripts/make_pill.py [--scale 5] [--width 1080] [--height 600]
                                      [--out pill-linkedin] [--skip-gif]
Requires: Pillow, ffmpeg.
"""

import argparse
import math
import os
import random
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")

GREEN = (118, 185, 0)          # Color.nvidia
DARK = (16, 19, 15)
SF_ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"

# Timeline (seconds).
T_IN = 0.12            # pill pops in (recording)
T_RELEASE = 3.00       # stop speaking -> transcribing
T_PASTE = 3.85         # text lands -> "Pasted"
FPS = 30
DURATION = 5.50        # "Pasted" is held to the last frame, then the GIF loops

# Synthesized speech envelope over [T_IN, T_RELEASE]: one bump per syllable,
# narrow enough that the bars visibly dip between words. (center_s, width_s, peak)
BUMPS = [
    (0.16, 0.060, 0.65), (0.34, 0.055, 0.90), (0.53, 0.050, 0.55),
    (0.74, 0.065, 1.00), (0.95, 0.055, 0.66), (1.17, 0.065, 0.92),
    (1.40, 0.055, 0.60), (1.66, 0.070, 1.00), (1.90, 0.055, 0.74),
    (2.13, 0.065, 0.95), (2.37, 0.055, 0.58), (2.60, 0.050, 0.46),
]


def smoothstep(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def voice_level(t):
    """Mic level 0..1 driven by the speech envelope (0.05 floor = silence)."""
    s = t - T_IN
    speech_len = T_RELEASE - T_IN
    if s < 0 or s > speech_len:
        return 0.05
    v = 0.05
    for c, w, h in BUMPS:
        v += h * math.exp(-(((s - c) / w) ** 2))
    v *= smoothstep(0.0, 0.16, s)                      # fade in
    v *= smoothstep(speech_len, speech_len - 0.22, s)  # fade out (a>b reverses)
    v *= 1 + 0.06 * math.sin(s * 37.0)                 # a little liveliness
    return max(0.05, min(1.0, v))


def font(size, weight=None, path=SF_ROUNDED):
    f = ImageFont.truetype(path, int(round(size)))
    if weight:
        try:
            f.set_variation_by_name(weight)
        except OSError:
            pass
    return f


class Pill:
    def __init__(self, W, H, S, out, gif_width):
        self.W, self.H, self.S = W, H, S
        self.out = out
        self.gif_width = gif_width
        self.cx, self.cy = W / 2, H / 2
        # Real label is 13.5pt semibold rounded -> scale it with the pill.
        self.F_PILL = font(13.5 * S, "Semibold")
        self.BG = self._background()
        random.seed(7)

    def _background(self):
        W, H = self.W, self.H
        img = Image.new("RGB", (W, H), DARK)
        glow = Image.new("RGB", (W, H), DARK)
        gd = ImageDraw.Draw(glow)
        gd.ellipse((W * 0.20, H * 0.05, W * 0.80, H * 1.05), fill=(30, 44, 16))
        glow = glow.filter(ImageFilter.GaussianBlur(150))
        return Image.blend(img, glow, 0.9)

    # --- geometry: content row width, mirroring the SwiftUI HStack -----------

    def content_width(self, d, t):
        S = self.S
        gap = 11 * S
        if t < T_RELEASE:                          # dot + 7-bar wave + label
            dot = 9 * S
            wave = (7 * 3.2 + 6 * 3) * S
            return dot + gap + wave + gap + d.textlength("Speak…", font=self.F_PILL)
        if t < T_PASTE:                            # 3 dots + label
            dots = (3 * 6.5 + 2 * 4) * S
            return dots + gap + d.textlength("Transcribing…", font=self.F_PILL)
        check = 17 * S                             # checkmark disc + label
        return check + gap + d.textlength("Pasted", font=self.F_PILL)

    # --- the pill ------------------------------------------------------------

    def draw_pill(self, img, t):
        if t < T_IN:
            return
        S = self.S
        pop = min(1.0, (t - T_IN) / 0.22)
        scale = 0.85 + 0.15 * (1 - (1 - pop) ** 3) + 0.04 * math.sin(pop * math.pi)
        rise = (1 - pop) * 26 * (S / 5)

        d = ImageDraw.Draw(img)
        content = self.content_width(d, t)
        pad = 18 * S
        pw = max(content + 2 * pad, 150 * S) * scale        # .frame(minWidth: 150)
        ph = (12 * 2 + 24) * S * scale                      # v-padding 12 + content 24
        cx, cy = self.cx, self.cy + rise
        box = (cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2)

        # Green glow + soft black shadow (compositingGroup + two shadows).
        glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(glow).rounded_rectangle(box, ph / 2, fill=GREEN + (95,))
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(7.5 * S))))
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            (box[0], box[1] + 4 * S, box[2], box[3] + 4 * S), ph / 2, fill=(0, 0, 0, 85))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(4.5 * S))))
        d = ImageDraw.Draw(img)

        # Capsule: black 91% over dark, nvidia-green border (1.2pt scaled).
        d.rounded_rectangle(box, ph / 2, fill=(10, 12, 10, 232),
                            outline=GREEN + (179,), width=max(2, int(1.2 * S)))
        if pop < 0.6:
            return

        # Content is centered (the minWidth frame centers its child).
        gap = 11 * S
        x = cx - content / 2
        if t < T_RELEASE:
            pulse = (math.sin(t / 0.65 * math.pi) + 1) / 2
            r = 4.5 * S
            d.ellipse((x, cy - r, x + 2 * r, cy + r), fill=GREEN + (int(102 + 153 * pulse),))
            x += 2 * r + gap
            lvl = voice_level(t)
            for i in range(7):
                wave = (math.sin(t * 8 + i * 0.8) + 1) / 2
                amp = (5 + lvl * 19 * (0.45 + 0.55 * wave)) * S
                bx = x + i * (3.2 + 3) * S
                d.rounded_rectangle((bx, cy - amp / 2, bx + 3.2 * S, cy + amp / 2),
                                    1.6 * S, fill=GREEN)
            x += (7 * 3.2 + 6 * 3) * S + gap
            d.text((x, cy), "Speak…", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")
        elif t < T_PASTE:
            for i in range(3):
                off = max(0.0, math.sin(t * 6 - i * 0.7)) * 5 * S
                r = 3.25 * S
                bx = x + i * (6.5 + 4) * S
                d.ellipse((bx, cy - r - off, bx + 2 * r, cy + r - off), fill=GREEN)
            x += (3 * 6.5 + 2 * 4) * S + gap
            d.text((x, cy), "Transcribing…", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")
        else:
            r = 8.5 * S
            d.ellipse((x, cy - r, x + 2 * r, cy + r), fill=GREEN)
            ccx, lw = x + r, max(3, int(2.2 * S))
            d.line((ccx - 0.40 * r, cy + 0.05 * r, ccx - 0.10 * r, cy + 0.38 * r),
                   fill=(10, 12, 10), width=lw)
            d.line((ccx - 0.10 * r, cy + 0.38 * r, ccx + 0.45 * r, cy - 0.30 * r),
                   fill=(10, 12, 10), width=lw)
            x += 2 * r + gap
            d.text((x, cy), "Pasted", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")

    # --- render --------------------------------------------------------------

    def render(self, skip_gif=False):
        frames_dir = f"/tmp/talkink_pill_frames_{self.out}"
        os.makedirs(frames_dir, exist_ok=True)
        n_frames = int(DURATION * FPS)
        for n in range(n_frames):
            img = self.BG.convert("RGBA")
            self.draw_pill(img, n / FPS)
            img.convert("RGB").save(f"{frames_dir}/f{n:04d}.png")

        mp4 = os.path.abspath(os.path.join(ROOT, "assets", f"{self.out}.mp4"))
        subprocess.run([
            "ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{frames_dir}/f%04d.png",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-movflags", "+faststart",
            mp4,
        ], check=True, capture_output=True)
        print(f"OK {mp4} ({os.path.getsize(mp4) / 1048576:.2f} MB)")

        if skip_gif:
            return
        gif = os.path.abspath(os.path.join(ROOT, "assets", f"{self.out}.gif"))
        filters = (
            f"fps=25,scale={self.gif_width}:-1:flags=lanczos,"
            "split[a][b];[a]palettegen=stats_mode=diff[p];"
            "[b][p]paletteuse=dither=sierra2_4a"
        )
        subprocess.run([
            "ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{frames_dir}/f%04d.png",
            "-vf", filters, "-loop", "0", gif,
        ], check=True, capture_output=True)
        print(f"OK {gif} ({os.path.getsize(gif) / 1048576:.2f} MB)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--scale", type=float, default=5.0)
    ap.add_argument("--width", type=int, default=1080)
    ap.add_argument("--height", type=int, default=600)
    ap.add_argument("--gif-width", type=int, default=960)
    ap.add_argument("--out", default="pill-linkedin")
    ap.add_argument("--skip-gif", action="store_true")
    args = ap.parse_args()
    Pill(args.width, args.height, args.scale, args.out, args.gif_width).render(skip_gif=args.skip_gif)
