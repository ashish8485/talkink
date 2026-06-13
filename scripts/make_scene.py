#!/usr/bin/env python3
"""Render the Talkink story, frame by frame — startup-grade, no desktop clutter.

Just the Claude Code window (the hero) on a clean brand background:
  1. The user clicks into the prompt of a Claude Code-style terminal.
  2. The Right Option key (⌥) is held — you SEE the keycap press and glow.
  3. The Talkink pill appears over the window and listens; the 7-bar waveform
     reacts to the voice (real Overlay.swift geometry + a speech envelope).
  4. Release → "Transcribing…" → the dictated instruction PASTES itself into
     the prompt, right where the cursor was. The pill says "Pasted".

No menu bar, no Dock — the window's traffic lights are enough to read "Mac app".

Usage:  python3 scripts/make_scene.py [--out scene-linkedin] [--skip-gif]
Requires: Pillow, ffmpeg.
"""

import argparse
import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
ICON = os.path.join(ROOT, "site", "assets", "icon-256.png")

GREEN = (118, 185, 0)            # Color.nvidia
TERRACOTTA = (217, 119, 87)      # Claude accent
DARK = (14, 16, 20)
SF = "/System/Library/Fonts/SFNS.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"

W, H = 1280, 900
FPS = 30
DURATION = 6.6

# Timeline (s)
T_CLICK = 0.60          # click ripple in the prompt
T_HOLD = 1.15           # Right Option pressed → pill appears, recording
T_RELEASE = 3.75        # released → transcribing
T_PASTE = 4.60          # text pasted → "Pasted"

WIN = (220, 78, 1060, 600)      # the Claude Code window (hero, centered)
PILL_S = 2.5

SENTENCE = "Refactor the login flow and add tests for the edge cases."

# Speech envelope (one bump per syllable; dips between words make the bars react)
BUMPS = [
    (0.14, 0.055, 0.65), (0.30, 0.050, 0.90), (0.46, 0.048, 0.55),
    (0.64, 0.060, 1.00), (0.84, 0.052, 0.66), (1.04, 0.060, 0.92),
    (1.24, 0.052, 0.60), (1.46, 0.064, 1.00), (1.68, 0.052, 0.74),
    (1.90, 0.060, 0.95), (2.12, 0.052, 0.58), (2.32, 0.050, 0.78),
]


def smoothstep(a, b, x):
    if a == b:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def voice_level(t):
    s = t - T_HOLD
    speech_len = T_RELEASE - T_HOLD
    if s < 0 or s > speech_len:
        return 0.05
    v = 0.05
    for c, w, h in BUMPS:
        v += h * math.exp(-(((s - c) / w) ** 2))
    v *= smoothstep(0.0, 0.16, s)
    v *= smoothstep(speech_len, speech_len - 0.28, s)
    v *= 1 + 0.06 * math.sin(s * 37.0)
    return max(0.05, min(1.0, v))


def font(size, weight=None, path=SF):
    f = ImageFont.truetype(path, int(round(size)))
    if weight:
        try:
            f.set_variation_by_name(weight)
        except OSError:
            pass
    return f


def rr(d, box, r, **kw):
    d.rounded_rectangle(box, radius=r, **kw)


def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


class Scene:
    def __init__(self, out):
        self.out = out
        self.F_TITLE = font(20, "Semibold")
        self.F_MONO = font(25, path=SF_MONO)
        self.F_MONO_B = font(25, "Bold", SF_MONO)
        self.F_MONO_DIM = font(21, path=SF_MONO)
        self.F_MONO_SM = font(20, path=SF_MONO)
        self.F_PILL = font(13.5 * PILL_S, "Semibold", SF_ROUNDED)
        self.F_KEY = font(48, "Medium")
        self.F_KEYLBL = font(20, "Medium")
        self.F_CAP = font(31, "Medium")
        self.F_BRAND = font(34, "Semibold")
        self.icon = Image.open(ICON).convert("RGBA")
        self.BG = self._background()

    # ----------------------------------------------------------- background

    def _background(self):
        base = Image.new("RGB", (W, H), DARK)
        glow = Image.new("RGB", (W, H), DARK)
        gd = ImageDraw.Draw(glow)
        cx = (WIN[0] + WIN[2]) / 2
        gd.ellipse((cx - W * 0.42, H * 0.02, cx + W * 0.42, H * 0.96), fill=(28, 42, 16))
        glow = glow.filter(ImageFilter.GaussianBlur(200))
        img = Image.blend(base, glow, 0.9).convert("RGBA")
        # window drop shadow (static — bake it once)
        sh = layer()
        rr(ImageDraw.Draw(sh), (WIN[0], WIN[1] + 20, WIN[2], WIN[3] + 26), 16, fill=(0, 0, 0, 150))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)))
        # subtle brand mark, bottom-right
        ic = self.icon.resize((42, 42), Image.LANCZOS)
        img.alpha_composite(ic, (W - 232, H - 62))
        ImageDraw.Draw(img).text((W - 182, H - 41), "Talkink", font=self.F_BRAND,
                                 fill=(178, 194, 160, 235), anchor="lm")
        return img

    # --------------------------------------------------------------- window

    def draw_window(self, img, t):
        d = ImageDraw.Draw(img)
        x0, y0, x1, y1 = WIN
        WHITE, DIM, DIM2 = (236, 238, 242), (120, 126, 134), (150, 156, 164)
        CYAN, RED = (86, 182, 194), (224, 108, 117)

        rr(d, (x0, y0, x1, y1), 14, fill=(21, 23, 28, 255), outline=(60, 64, 72, 255), width=1)
        rr(d, (x0, y0, x1, y0 + 40), 14, fill=(34, 37, 44, 255))
        d.rectangle((x0, y0 + 26, x1, y0 + 42), fill=(21, 23, 28, 255))
        for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
            d.ellipse((x0 + 20 + i * 24, y0 + 14, x0 + 33 + i * 24, y0 + 27), fill=c)
        d.text(((x0 + x1) / 2, y0 + 20), "hasan · claude · zsh", font=self.F_TITLE,
               fill=(150, 154, 162), anchor="mm")

        bx, right = x0 + 34, x1 - 34
        # Claude Code header: pixel avatar + version + model + cwd (real layout)
        self._claude_avatar(img, bx, y0 + 92, 74)
        d = ImageDraw.Draw(img)
        tx0 = bx + 92
        d.text((tx0, y0 + 92), "Claude Code", font=self.F_MONO_B, fill=WHITE, anchor="lm")
        d.text((tx0 + d.textlength("Claude Code ", font=self.F_MONO_B), y0 + 93),
               "v2.1.177", font=self.F_MONO_DIM, fill=DIM, anchor="lm")
        d.text((tx0, y0 + 121), "Opus 4.8 (1M context) with xhigh effort · Claude Max",
               font=self.F_MONO_SM, fill=DIM2, anchor="lm")
        d.text((tx0, y0 + 147), "/Users/hasan", font=self.F_MONO_SM, fill=DIM, anchor="lm")
        d.text((bx, y0 + 196), "│ Using Opus 4.8 (1M context) (from .claude/settings.json) · /model",
               font=self.F_MONO_SM, fill=DIM, anchor="lm")

        # input region: rule · › prompt · rule, then the status lines
        ry0 = y0 + 236
        d.line((bx, ry0, right, ry0), fill=(52, 56, 64), width=2)
        py = ry0 + 32
        d.text((bx, py), "›", font=self.F_MONO, fill=DIM2, anchor="lm")
        tx = bx + d.textlength("› ", font=self.F_MONO)
        cur_x, cur_y = tx, py
        if t >= T_PASTE:
            lines = self._wrap(d, SENTENCE, self.F_MONO, right - tx)
            for i, ln in enumerate(lines):
                d.text((tx, py + i * 30), ln, font=self.F_MONO, fill=WHITE, anchor="lm")
            cur_x = tx + d.textlength(lines[-1], font=self.F_MONO) + 2
            cur_y = py + (len(lines) - 1) * 30
        ry1 = py + 30 + 26                       # input reserves two lines (no jump on paste)
        d.line((bx, ry1, right, ry1), fill=(52, 56, 64), width=2)
        if int(t * 2) % 2 == 0 or (T_PASTE <= t < T_PASTE + 0.6):
            d.rectangle((cur_x, cur_y - 13, cur_x + 12, cur_y + 13), fill=(200, 204, 210))

        sy = ry1 + 26
        d.text((bx, sy), "Opus 4.8 (1M context)", font=self.F_MONO_SM, fill=CYAN, anchor="lm")
        seg = "▶▶ bypass permissions on"
        d.text((bx, sy + 28), seg, font=self.F_MONO_SM, fill=RED, anchor="lm")
        d.text((bx + d.textlength(seg, font=self.F_MONO_SM), sy + 28),
               " (shift+tab to cycle) · ← for agents", font=self.F_MONO_SM, fill=DIM, anchor="lm")

        if T_CLICK <= t < T_CLICK + 0.45:        # the user clicks into the prompt
            p = (t - T_CLICK) / 0.45
            r = 8 + p * 34
            ov = layer()
            ImageDraw.Draw(ov).ellipse((tx - r, py - r, tx + r, py + r),
                                       outline=(255, 255, 255, int(140 * (1 - p))), width=3)
            img.alpha_composite(ov)

    # The real Claude Code mascot, digitised pixel-for-pixel from its terminal
    # output (16×11 native grid). '#' = terracotta; holes are eyes/gaps that show
    # the dark window through, exactly like the real render.
    AVATAR = (
        ".##############.",
        ".##############.",
        "####.######.####",
        "####.######.####",
        ".##############.",
        ".##############.",
        ".##############.",
        ".##############.",
        ".##############.",
        "...#.#....#.#...",
        "...#.#....#.#...",
    )

    def _claude_avatar(self, img, x, y, tw):
        cell = tw / 16
        gap = cell * 0.5                  # feet are detached by a sub-cell gap
        d = ImageDraw.Draw(img)
        ter = (203, 124, 94)             # sampled from the real mascot
        for j, line in enumerate(self.AVATAR):
            yo = y + j * cell + (gap if j >= 9 else 0)
            for i, ch in enumerate(line):
                if ch == "#":
                    d.rectangle((x + i * cell, yo, x + (i + 1) * cell, yo + cell), fill=ter)

    def _wrap(self, d, text, fnt, maxw):
        words, lines, cur = text.split(), [], ""
        for w_ in words:
            trial = (cur + " " + w_).strip()
            if d.textlength(trial, font=fnt) <= maxw:
                cur = trial
            else:
                lines.append(cur)
                cur = w_
        if cur:
            lines.append(cur)
        return lines

    # ----------------------------------------------------------- ⌥ keycap

    def draw_keycap(self, img, t):
        cx, cy = W / 2, 802
        kw, kh = 120, 102
        held = T_HOLD <= t < T_RELEASE
        press = smoothstep(T_HOLD, T_HOLD + 0.09, t) - smoothstep(T_RELEASE, T_RELEASE + 0.09, t)
        dy = 3 * press
        box = (cx - kw / 2, cy - kh / 2 + dy, cx + kw / 2, cy + kh / 2 + dy)
        if held:
            glow = layer()
            rr(ImageDraw.Draw(glow), box, 16, fill=GREEN + (120,))
            img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(22)))
        d = ImageDraw.Draw(img)
        top = (44, 48, 56) if not held else (54, 70, 30)
        rr(d, (box[0], box[1] + 5, box[2], box[3] + 6), 16, fill=(24, 26, 32))
        rr(d, box, 16, fill=top, outline=GREEN + (235,) if held else (92, 97, 106, 255),
           width=3 if held else 2)
        col = (235, 245, 220) if held else (206, 210, 217)
        d.text(((box[0] + box[2]) / 2, box[1] + 35), "⌥", font=self.F_KEY, fill=col, anchor="mm")
        d.text(((box[0] + box[2]) / 2, box[3] - 21), "right option", font=self.F_KEYLBL,
               fill=col, anchor="mm")

    # ------------------------------------------------------------ the pill

    def _pill_content_w(self, d, t):
        S, gap = PILL_S, 11 * PILL_S
        if t < T_RELEASE:
            return 9 * S + gap + (7 * 3.2 + 6 * 3) * S + gap + d.textlength("Speak…", font=self.F_PILL)
        if t < T_PASTE:
            return (3 * 6.5 + 2 * 4) * S + gap + d.textlength("Transcribing…", font=self.F_PILL)
        return 17 * S + gap + d.textlength("Pasted", font=self.F_PILL)

    def draw_pill(self, img, t):
        if t < T_HOLD:
            return
        S = PILL_S
        pop = min(1.0, (t - T_HOLD) / 0.22)
        scale = 0.85 + 0.15 * (1 - (1 - pop) ** 3) + 0.04 * math.sin(pop * math.pi)
        rise = (1 - pop) * 16
        d = ImageDraw.Draw(img)
        content = self._pill_content_w(d, t)
        pad = 18 * S
        pw = max(content + 2 * pad, 150 * S) * scale
        ph = (12 * 2 + 24) * S * scale
        cx = (WIN[0] + WIN[2]) / 2
        cy = WIN[3] - 52 + rise            # just above the window's bottom edge
        box = (cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2)

        glow = layer()
        rr(ImageDraw.Draw(glow), box, ph / 2, fill=GREEN + (95,))
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(4 * S))))
        sh = layer()
        rr(ImageDraw.Draw(sh), (box[0], box[1] + 3 * S, box[2], box[3] + 3 * S), ph / 2, fill=(0, 0, 0, 90))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(3 * S))))
        d = ImageDraw.Draw(img)
        rr(d, box, ph / 2, fill=(10, 12, 10, 236), outline=GREEN + (185,), width=max(2, int(1.2 * S)))
        if pop < 0.6:
            return

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
                d.rounded_rectangle((bx, cy - amp / 2, bx + 3.2 * S, cy + amp / 2), 1.6 * S, fill=GREEN)
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
            d.line((ccx - 0.40 * r, cy + 0.05 * r, ccx - 0.10 * r, cy + 0.38 * r), fill=(10, 12, 10), width=lw)
            d.line((ccx - 0.10 * r, cy + 0.38 * r, ccx + 0.45 * r, cy - 0.30 * r), fill=(10, 12, 10), width=lw)
            x += 2 * r + gap
            d.text((x, cy), "Pasted", font=self.F_PILL, fill=(255, 255, 255), anchor="lm")

    # ----------------------------------------------------------- caption

    def draw_caption(self, img, t):
        if t < T_CLICK:
            return
        if t < T_HOLD:
            msg, col = "Hold the Right Option key ⌥", (225, 228, 234)
        elif t < T_RELEASE:
            msg, col = "Speak. Transcribed on-device, in real time.", (200, 230, 160)
        elif t < T_PASTE:
            msg, col = "Release.", (225, 228, 234)
        else:
            msg, col = "Pasted right where you're typing.", (200, 230, 160)
        ImageDraw.Draw(img).text((W / 2, 680), msg, font=self.F_CAP, fill=col, anchor="mm")

    # ------------------------------------------------------------- render

    def frame(self, t):
        img = self.BG.copy()
        self.draw_window(img, t)
        self.draw_pill(img, t)
        self.draw_caption(img, t)
        self.draw_keycap(img, t)
        return img.convert("RGB")

    def render(self, skip_gif=False):
        fdir = f"/tmp/talkink_scene_{self.out}"
        os.makedirs(fdir, exist_ok=True)
        n = int(DURATION * FPS)
        for i in range(n):
            self.frame(i / FPS).save(f"{fdir}/f{i:04d}.png")
        mp4 = os.path.abspath(os.path.join(ROOT, "assets", f"{self.out}.mp4"))
        subprocess.run(["ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{fdir}/f%04d.png",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "19",
                        "-movflags", "+faststart", mp4], check=True, capture_output=True)
        print(f"OK {mp4} ({os.path.getsize(mp4)/1048576:.2f} MB)")
        if skip_gif:
            return
        gif = os.path.abspath(os.path.join(ROOT, "assets", f"{self.out}.gif"))
        filt = ("fps=24,scale=1280:-1:flags=lanczos,split[a][b];"
                "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a")
        subprocess.run(["ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{fdir}/f%04d.png",
                        "-vf", filt, "-loop", "0", gif], check=True, capture_output=True)
        print(f"OK {gif} ({os.path.getsize(gif)/1048576:.2f} MB)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="demo")
    ap.add_argument("--skip-gif", action="store_true")
    args = ap.parse_args()
    Scene(args.out).render(skip_gif=args.skip_gif)
