#!/usr/bin/env python3
"""Render the Talkink demo video (LinkedIn square cut), frame by frame.

Faithful to the real app:
- The pill replicates Overlay.swift exactly — dark capsule, NVIDIA-green
  border + glow, pulsing dot + 7-bar waveform, and the REAL labels
  ("Speak…", "Transcribing…", "Pasted").
- It anchors just above the bottom edge of the window being dictated into,
  like WindowLocator does — not at the bottom of the screen.
- The transcribed text is pasted ALL AT ONCE (no fake streaming).
- The end card uses the real app icon (site/assets/icon-256.png).

Usage:  python3 scripts/make_demo.py
Output: assets/demo-square.mp4 (1080x1080, 30 fps, ~9.5 s)
"""

import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W = H = 1080
FPS = 30
DURATION = 9.5
FRAMES = int(DURATION * FPS)
OUT_DIR = "/tmp/talkink_demo_frames"
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT_MP4 = os.path.join(ROOT, "assets", "demo-square.mp4")
ICON = os.path.join(ROOT, "site", "assets", "icon-256.png")

GREEN = (118, 185, 0)          # Color.nvidia
DARK = (16, 19, 15)

SF = "/System/Library/Fonts/SFNS.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"


def font(size, weight=None, path=SF):
    f = ImageFont.truetype(path, size)
    if weight:
        try:
            f.set_variation_by_name(weight)
        except OSError:
            pass
    return f


F_TITLE = font(34, "Semibold")
F_BODY = font(52)
F_BODY_BOLD = font(58, "Semibold")
F_EXPLAIN = font(44)
# Real pill label: 13.5pt semibold rounded → ~2.3x for video legibility.
F_PILL = font(31, "Semibold", SF_ROUNDED)
F_LOGO = font(110, "Bold")
F_TAG = font(52, "Medium")
F_SMALL = font(34)
F_CAPTION = font(36, "Medium")

SENTENCE = "Can you send me the commercial report before noon tomorrow?"
EXPLAINER = ("Push-to-talk dictation for your Mac. Hold a key, speak, release — "
             "your words appear at your cursor, in any app. 100% on-device.")

# Timeline (seconds)
T_PILL_IN = 0.7
T_RELEASE = 4.3        # key released → transcribing
T_PASTE = 5.4          # text lands, all at once
T_CARD = 7.6
T_CARD_FULL = 8.1

# Pill geometry — real proportions (padding 18/12 around content, capsule),
# scaled ~2.3x so it reads in a feed.
PILL_SCALE = 2.3


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


def background():
    img = Image.new("RGB", (W, H), DARK)
    glow = Image.new("RGB", (W, H), DARK)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((W * 0.18, H * 0.55, W * 1.05, H * 1.25), fill=(30, 44, 16))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    return Image.blend(img, glow, 0.85)


BG = background()
APP_ICON = Image.open(ICON).convert("RGBA")

# Window fills the frame; the pill will overlap its bottom edge (real anchor).
WIN = (40, 40, W - 40, 780)
PAD = 56
PILL_CY = WIN[3] - 86          # "just above the window's bottom edge"
CAPTION_Y = 960


def draw_window(img, t):
    d = ImageDraw.Draw(img)
    rounded(d, (WIN[0] + 6, WIN[1] + 14, WIN[2] + 6, WIN[3] + 14), 30, fill=(8, 10, 8))
    rounded(d, WIN, 30, fill=(247, 247, 248))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse((WIN[0] + 34 + i * 44, WIN[1] + 30, WIN[0] + 60 + i * 44, WIN[1] + 56), fill=c)
    d.text(((WIN[0] + WIN[2]) / 2, WIN[1] + 43), "Notes", font=F_TITLE,
           fill=(120, 120, 124), anchor="mm")
    d.line((WIN[0], WIN[1] + 86, WIN[2], WIN[1] + 86), fill=(228, 228, 230), width=2)

    x = WIN[0] + PAD
    y = WIN[1] + 124
    d.text((x, y), "Talkink", font=F_BODY_BOLD, fill=(28, 28, 30))
    y += 100
    # The note explains the app itself — the demo is self-contained.
    for line in wrap(d, EXPLAINER, F_EXPLAIN, WIN[2] - WIN[0] - 2 * PAD):
        d.text((x, y), line, font=F_EXPLAIN, fill=(105, 105, 110))
        y += 58
    y += 42

    pasted = t >= T_PASTE
    caret_x, caret_y = x, y
    if pasted:
        lines = wrap(d, SENTENCE, F_BODY, WIN[2] - WIN[0] - 2 * PAD)
        wash = min(1.0, (t - T_PASTE) / 0.7)
        alpha = int(70 * (1 - wash))
        if alpha > 0:
            ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
            od = ImageDraw.Draw(ov)
            for i, line in enumerate(lines):
                ly = y + i * 72
                rounded(od, (x - 10, ly - 6, x + d.textlength(line, font=F_BODY) + 10, ly + 64),
                        12, fill=GREEN + (alpha,))
            img.alpha_composite(ov)
            d = ImageDraw.Draw(img)
        for i, line in enumerate(lines):
            d.text((x, y + i * 72), line, font=F_BODY, fill=(28, 28, 30))
        caret_x = x + d.textlength(lines[-1], font=F_BODY) + 6
        caret_y = y + (len(lines) - 1) * 72
    if int(t * 2) % 2 == 0 or (T_PASTE <= t < T_PASTE + 0.7):
        d.rectangle((caret_x, caret_y - 2, caret_x + 5, caret_y + 62), fill=GREEN)


# ---------------------------------------------------------------- real pill

def pill_content_width(d, t):
    """Width of the state's content row, mirroring the SwiftUI HStack."""
    s = PILL_SCALE
    if t < T_RELEASE:      # RecordingDot + LiveWaveform(7 bars) + "Speak…"
        dot = 9 * s
        wave = (7 * 3.2 + 6 * 3) * s
        text = d.textlength("Speak…", font=F_PILL)
        return dot + wave + text + 2 * 11 * s
    if t < T_PASTE:        # BouncingDots(3) + "Transcribing…"
        dots = (3 * 6.5 + 2 * 4) * s
        text = d.textlength("Transcribing…", font=F_PILL)
        return dots + text + 11 * s
    check = 17 * s
    text = d.textlength("Pasted", font=F_PILL)
    return check + text + 11 * s


def draw_pill(img, t):
    if t < T_PILL_IN:
        return
    s = PILL_SCALE
    pop = min(1.0, (t - T_PILL_IN) / 0.22)
    # spring-ish scale-in from 0.85 with overshoot, like the real transition
    scale = 0.85 + 0.15 * (1 - (1 - pop) ** 3) + 0.04 * math.sin(pop * math.pi)
    rise = (1 - pop) * 24

    d = ImageDraw.Draw(img)
    cw = pill_content_width(d, t)
    ph = (12 * 2 + 24) * s * scale          # vertical padding 12 + content 24
    pw = (cw + 2 * 18 * s) * scale          # horizontal padding 18
    cx, cy = (WIN[0] + WIN[2]) / 2, PILL_CY + rise
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
        d.text((x, cy), "Speak…", font=F_PILL, fill=(255, 255, 255), anchor="lm")
    elif t < T_PASTE:
        # BouncingDots: 3 dots, 6.5px, bounce sin(t*6 - i*0.7)*5.
        for i in range(3):
            off = max(0.0, math.sin(t * 6 - i * 0.7)) * 5 * s
            r = 3.25 * s
            bx = x + i * (6.5 + 4) * s
            d.ellipse((bx, cy - r - off, bx + 2 * r, cy + r - off), fill=GREEN)
        x += (3 * 6.5 + 2 * 4) * s + gap
        d.text((x, cy), "Transcribing…", font=F_PILL, fill=(255, 255, 255), anchor="lm")
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
        d.text((x, cy), "Pasted", font=F_PILL, fill=(255, 255, 255), anchor="lm")


def draw_caption(img, t):
    if t >= T_CARD:
        return
    d = ImageDraw.Draw(img)
    if t < T_RELEASE:
        msg = "Hold the key and speak…"
    elif t < T_PASTE:
        msg = "Release."
    else:
        msg = "Pasted at your cursor — in any app."
    d.text((W / 2, CAPTION_Y), msg, font=F_CAPTION, fill=(168, 173, 165), anchor="mm")


def draw_endcard(img, t):
    if t < T_CARD:
        return
    a = min(1.0, (t - T_CARD) / (T_CARD_FULL - T_CARD))
    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.rectangle((0, 0, W, H), fill=DARK + (int(255 * a),))
    if a > 0.55:
        fa = int(255 * (a - 0.55) / 0.45)
        cx = W / 2
        icon = APP_ICON.resize((230, 230), Image.LANCZOS)
        if fa < 255:
            alpha = icon.getchannel("A").point(lambda p: p * fa // 255)
            icon.putalpha(alpha)
        ov.alpha_composite(icon, (int(cx - 115), 250))
        d.text((cx, 590), "Talkink", font=F_LOGO, fill=(245, 245, 245, fa), anchor="mm")
        d.text((cx, 700), "Say it. It's written.", font=F_TAG, fill=(170, 175, 168, fa), anchor="mm")
        d.text((cx, 810), "talkink.app", font=F_TAG, fill=GREEN + (fa,), anchor="mm")
        d.text((cx, 905), "100% on-device  ·  free & open source", font=F_SMALL,
               fill=(140, 145, 138, fa), anchor="mm")
    img.alpha_composite(ov)


def render():
    os.makedirs(OUT_DIR, exist_ok=True)
    for n in range(FRAMES):
        t = n / FPS
        img = BG.convert("RGBA")
        draw_window(img, t)
        draw_pill(img, t)
        draw_caption(img, t)
        draw_endcard(img, t)
        img.convert("RGB").save(f"{OUT_DIR}/f{n:04d}.png")
    subprocess.run([
        "ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{OUT_DIR}/f%04d.png",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-movflags", "+faststart",
        os.path.abspath(OUT_MP4),
    ], check=True, capture_output=True)
    print(f"OK {os.path.abspath(OUT_MP4)}")


if __name__ == "__main__":
    render()
