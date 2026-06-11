#!/usr/bin/env python3
"""Render the Talkink demo, frame by frame — faithful to the real app.

- The pill replicates Overlay.swift exactly: dark capsule, NVIDIA-green
  border + glow, pulsing dot + 7-bar waveform, and the REAL labels
  ("Speak…", "Transcribing…", "Pasted").
- It anchors just above the bottom edge of the window being dictated into,
  like WindowLocator does — not at the bottom of the screen.
- The transcribed text is pasted ALL AT ONCE (no fake streaming).
- The end card uses the real app icon (site/assets/icon-256.png).

Usage:  python3 scripts/make_demo.py [--format wide|square] [--skip-gif]
  wide    1920x1080 → assets/demo.mp4 + assets/demo.gif   (README + site)
  square  1080x1080 → assets/demo-square.mp4 + .gif       (social feeds)

Requires: Pillow, ffmpeg.
"""

import argparse
import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
ICON = os.path.join(ROOT, "site", "assets", "icon-256.png")

GREEN = (118, 185, 0)          # Color.nvidia
DARK = (16, 19, 15)

SF = "/System/Library/Fonts/SFNS.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"

SENTENCE = "Can you send me the commercial report before noon tomorrow?"
EXPLAINER = ("Push-to-talk dictation for your Mac. Hold a key, speak, release — "
             "your words appear at your cursor, in any app. 100% on-device.")

# Timeline (seconds) — proven pacing from the square cut.
T_PILL_IN = 0.7
T_RELEASE = 4.3        # key released → transcribing
T_PASTE = 5.4          # text lands, all at once
T_CARD = 7.6
T_CARD_FULL = 8.1
FPS = 30
DURATION = 9.5

# Per-format composition. The end card's vertical layout assumes H=1080.
#   win        — the Notes window rect (the pill overlaps its bottom edge)
#   pill_scale — real pill geometry is in points; scaled for legibility at
#                the format's typical display width
#   gif_width  — GIF downscale target (README shows 760 CSS px → 1.6x retina)
FORMATS = {
    "square": dict(
        W=1080, H=1080,
        win=(40, 40, 1040, 780),
        pill_scale=2.3,
        caption_y=960,
        body=52, body_bold=58, explain=44, pill_label=31,
        out="demo-square", gif_width=1080, gif_fps=25,
    ),
    "wide": dict(
        W=1920, H=1080,
        win=(340, 90, 1580, 830),
        pill_scale=2.5,
        caption_y=952,
        body=54, body_bold=62, explain=46, pill_label=34,
        out="demo", gif_width=1216, gif_fps=25,
    ),
}


def font(size, weight=None, path=SF):
    f = ImageFont.truetype(path, size)
    if weight:
        try:
            f.set_variation_by_name(weight)
        except OSError:
            pass
    return f


def rounded(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def wrap(draw, text, fnt, max_width):
    words, lines, cur = text.split(), [], ""
    for w_ in words:
        trial = (cur + " " + w_).strip()
        if draw.textlength(trial, font=fnt) <= max_width:
            cur = trial
        else:
            lines.append(cur)
            cur = w_
    if cur:
        lines.append(cur)
    return lines


class Demo:
    def __init__(self, fmt):
        self.W, self.H = fmt["W"], fmt["H"]
        self.WIN = fmt["win"]
        self.S = fmt["pill_scale"]
        self.CAPTION_Y = fmt["caption_y"]
        self.PAD = 56
        self.PILL_CY = self.WIN[3] - 86   # "just above the window's bottom edge"
        self.out = fmt["out"]
        self.gif_width = fmt["gif_width"]
        self.gif_fps = fmt["gif_fps"]

        self.F_TITLE = font(34, "Semibold")
        self.F_BODY = font(fmt["body"])
        self.F_BODY_BOLD = font(fmt["body_bold"], "Semibold")
        self.F_EXPLAIN = font(fmt["explain"])
        # Real pill label is 13.5pt semibold rounded → scaled for legibility.
        self.F_PILL = font(fmt["pill_label"], "Semibold", SF_ROUNDED)
        self.F_LOGO = font(110, "Bold")
        self.F_TAG = font(52, "Medium")
        self.F_SMALL = font(34)
        self.F_CAPTION = font(36, "Medium")

        self.BG = self._background()
        self.APP_ICON = Image.open(ICON).convert("RGBA")

    def _background(self):
        W, H = self.W, self.H
        img = Image.new("RGB", (W, H), DARK)
        glow = Image.new("RGB", (W, H), DARK)
        gd = ImageDraw.Draw(glow)
        gd.ellipse((W * 0.18, H * 0.55, W * 1.05, H * 1.25), fill=(30, 44, 16))
        glow = glow.filter(ImageFilter.GaussianBlur(160))
        return Image.blend(img, glow, 0.85)

    # ------------------------------------------------------------- window

    def draw_window(self, img, t):
        WIN, PAD = self.WIN, self.PAD
        d = ImageDraw.Draw(img)
        rounded(d, (WIN[0] + 6, WIN[1] + 14, WIN[2] + 6, WIN[3] + 14), 30, fill=(8, 10, 8))
        rounded(d, WIN, 30, fill=(247, 247, 248))
        for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
            d.ellipse((WIN[0] + 34 + i * 44, WIN[1] + 30, WIN[0] + 60 + i * 44, WIN[1] + 56), fill=c)
        d.text(((WIN[0] + WIN[2]) / 2, WIN[1] + 43), "Notes", font=self.F_TITLE,
               fill=(120, 120, 124), anchor="mm")
        d.line((WIN[0], WIN[1] + 86, WIN[2], WIN[1] + 86), fill=(228, 228, 230), width=2)

        x = WIN[0] + PAD
        y = WIN[1] + 124
        d.text((x, y), "Talkink", font=self.F_BODY_BOLD, fill=(28, 28, 30))
        y += 100
        # The note explains the app itself — the demo is self-contained.
        for line in wrap(d, EXPLAINER, self.F_EXPLAIN, WIN[2] - WIN[0] - 2 * PAD):
            d.text((x, y), line, font=self.F_EXPLAIN, fill=(105, 105, 110))
            y += 60
        y += 42

        pasted = t >= T_PASTE
        caret_x, caret_y = x, y
        if pasted:
            lines = wrap(d, SENTENCE, self.F_BODY, WIN[2] - WIN[0] - 2 * PAD)
            wash = min(1.0, (t - T_PASTE) / 0.7)
            alpha = int(70 * (1 - wash))
            if alpha > 0:
                ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
                od = ImageDraw.Draw(ov)
                for i, line in enumerate(lines):
                    ly = y + i * 74
                    rounded(od, (x - 10, ly - 6, x + d.textlength(line, font=self.F_BODY) + 10, ly + 66),
                            12, fill=GREEN + (alpha,))
                img.alpha_composite(ov)
                d = ImageDraw.Draw(img)
            for i, line in enumerate(lines):
                d.text((x, y + i * 74), line, font=self.F_BODY, fill=(28, 28, 30))
            caret_x = x + d.textlength(lines[-1], font=self.F_BODY) + 6
            caret_y = y + (len(lines) - 1) * 74
        if int(t * 2) % 2 == 0 or (T_PASTE <= t < T_PASTE + 0.7):
            d.rectangle((caret_x, caret_y - 2, caret_x + 5, caret_y + 64), fill=GREEN)

    # ---------------------------------------------------------- real pill

    def pill_content_width(self, d, t):
        """Width of the state's content row, mirroring the SwiftUI HStack."""
        s = self.S
        if t < T_RELEASE:      # RecordingDot + LiveWaveform(7 bars) + "Speak…"
            dot = 9 * s
            wave = (7 * 3.2 + 6 * 3) * s
            text = d.textlength("Speak…", font=self.F_PILL)
            return dot + wave + text + 2 * 11 * s
        if t < T_PASTE:        # BouncingDots(3) + "Transcribing…"
            dots = (3 * 6.5 + 2 * 4) * s
            text = d.textlength("Transcribing…", font=self.F_PILL)
            return dots + text + 11 * s
        check = 17 * s
        text = d.textlength("Pasted", font=self.F_PILL)
        return check + text + 11 * s

    def draw_pill(self, img, t):
        if t < T_PILL_IN:
            return
        s = self.S
        pop = min(1.0, (t - T_PILL_IN) / 0.22)
        # spring-ish scale-in from 0.85 with overshoot, like the real transition
        scale = 0.85 + 0.15 * (1 - (1 - pop) ** 3) + 0.04 * math.sin(pop * math.pi)
        rise = (1 - pop) * 24

        d = ImageDraw.Draw(img)
        cw = self.pill_content_width(d, t)
        ph = (12 * 2 + 24) * s * scale          # vertical padding 12 + content 24
        pw = (cw + 2 * 18 * s) * scale          # horizontal padding 18
        cx, cy = (self.WIN[0] + self.WIN[2]) / 2, self.PILL_CY + rise
        box = (cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2)

        # Green glow + soft black shadow (compositingGroup + two shadows).
        glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        rounded(ImageDraw.Draw(glow), box, ph / 2, fill=GREEN + (90,))
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18)))
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        rounded(ImageDraw.Draw(sh), (box[0], box[1] + 10, box[2], box[3] + 10), ph / 2, fill=(0, 0, 0, 80))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
        d = ImageDraw.Draw(img)

        # Capsule: black 55% over dark material, nvidia-green border (1.2pt).
        rounded(d, box, ph / 2, fill=(10, 12, 10, 232),
                outline=GREEN + (179,), width=max(2, int(1.2 * s)))
        if pop < 0.65:
            return

        pad = 18 * s
        gap = 11 * s
        x = box[0] + pad
        if t < T_RELEASE:
            # Pulsing recording dot (0.65s ease in-out cycle).
            pulse = (math.sin(t / 0.65 * math.pi) + 1) / 2
            r = 4.5 * s
            dot_a = int(102 + 153 * pulse)
            d.ellipse((x, cy - r, x + 2 * r, cy + r), fill=GREEN + (dot_a,))
            x += 2 * r + gap
            # LiveWaveform: 7 capsule bars, w 3.2, spacing 3, h 5→24.
            for i in range(7):
                wave = (math.sin(t * 8 + i * 0.8) + 1) / 2
                amp = (5 + 0.75 * 19 * (0.45 + 0.55 * wave)) * s
                bx = x + i * (3.2 + 3) * s
                d.rounded_rectangle((bx, cy - amp / 2, bx + 3.2 * s, cy + amp / 2),
                                    1.6 * s, fill=GREEN)
            x += (7 * 3.2 + 6 * 3) * s + gap
            d.text((x, cy), "Speak…", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")
        elif t < T_PASTE:
            # BouncingDots: 3 dots, 6.5px, bounce sin(t*6 - i*0.7)*5.
            for i in range(3):
                off = max(0.0, math.sin(t * 6 - i * 0.7)) * 5 * s
                r = 3.25 * s
                bx = x + i * (6.5 + 4) * s
                d.ellipse((bx, cy - r - off, bx + 2 * r, cy + r - off), fill=GREEN)
            x += (3 * 6.5 + 2 * 4) * s + gap
            d.text((x, cy), "Transcribing…", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")
        else:
            # checkmark.circle.fill tinted nvidia: green disc, knocked-out check.
            r = 8.5 * s
            d.ellipse((x, cy - r, x + 2 * r, cy + r), fill=GREEN)
            ccx, lw = x + r, max(3, int(2.2 * s))
            d.line((ccx - 0.40 * r, cy + 0.05 * r, ccx - 0.10 * r, cy + 0.38 * r),
                   fill=(10, 12, 10), width=lw)
            d.line((ccx - 0.10 * r, cy + 0.38 * r, ccx + 0.45 * r, cy - 0.30 * r),
                   fill=(10, 12, 10), width=lw)
            x += 2 * r + gap
            d.text((x, cy), "Pasted", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")

    # ------------------------------------------------------- caption/card

    def draw_caption(self, img, t):
        if t >= T_CARD:
            return
        d = ImageDraw.Draw(img)
        if t < T_RELEASE:
            msg = "Hold the key and speak…"
        elif t < T_PASTE:
            msg = "Release."
        else:
            msg = "Pasted at your cursor — in any app."
        d.text((self.W / 2, self.CAPTION_Y), msg, font=self.F_CAPTION,
               fill=(168, 173, 165), anchor="mm")

    def draw_endcard(self, img, t):
        if t < T_CARD:
            return
        a = min(1.0, (t - T_CARD) / (T_CARD_FULL - T_CARD))
        ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        d.rectangle((0, 0, self.W, self.H), fill=DARK + (int(255 * a),))
        if a > 0.55:
            fa = int(255 * (a - 0.55) / 0.45)
            cx = self.W / 2
            icon = self.APP_ICON.resize((230, 230), Image.LANCZOS)
            if fa < 255:
                alpha = icon.getchannel("A").point(lambda p: p * fa // 255)
                icon.putalpha(alpha)
            ov.alpha_composite(icon, (int(cx - 115), 250))
            d.text((cx, 590), "Talkink", font=self.F_LOGO, fill=(245, 245, 245, fa), anchor="mm")
            d.text((cx, 700), "Say it. It's written.", font=self.F_TAG, fill=(170, 175, 168, fa), anchor="mm")
            d.text((cx, 810), "talkink.app", font=self.F_TAG, fill=GREEN + (fa,), anchor="mm")
            d.text((cx, 905), "100% on-device  ·  free & open source", font=self.F_SMALL,
                   fill=(140, 145, 138, fa), anchor="mm")
        img.alpha_composite(ov)

    # ------------------------------------------------------------ render

    def render(self, skip_gif=False):
        frames_dir = f"/tmp/talkink_demo_frames_{self.out}"
        os.makedirs(frames_dir, exist_ok=True)
        n_frames = int(DURATION * FPS)
        for n in range(n_frames):
            t = n / FPS
            img = self.BG.convert("RGBA")
            self.draw_window(img, t)
            self.draw_pill(img, t)
            self.draw_caption(img, t)
            self.draw_endcard(img, t)
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
        # High-quality GIF — from the lossless PNG frames, NOT the mp4: x264
        # noise makes the dither dance over the whole static background, which
        # defeats GIF's LZW row reuse and triples the file size. Diff-based
        # palette + sierra dithering avoids banding on the dark glow.
        gif = os.path.abspath(os.path.join(ROOT, "assets", f"{self.out}.gif"))
        filters = (
            f"fps={self.gif_fps},scale={self.gif_width}:-1:flags=lanczos,"
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
    ap.add_argument("--format", choices=list(FORMATS), default="wide")
    ap.add_argument("--skip-gif", action="store_true")
    args = ap.parse_args()
    Demo(FORMATS[args.format]).render(skip_gif=args.skip_gif)
