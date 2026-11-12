#!/usr/bin/env python3
"""Erzeugt die Icon-Ebenen der V4A-Switch-App (Adaptive Icons) und die Ersatz-Icons fuer Android 7.x.

Aufruf im Projektordner:  python3 tools/make_icons.py
Benoetigt: Pillow. Schriftart wird nicht benoetigt.
"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

RES = os.path.join(os.path.dirname(__file__), '..', 'app', 'res')
SS = 4                      # Supersampling
CANVAS = 512                # Kantenlaenge der Ebenen (108 dp)
PALETTE = {                 # Start oben links, Ende unten rechts
    'fx':    ((180, 124, 255), (90, 43, 214)),
    'xhifi': ((70, 194, 255), (26, 82, 240)),
}

def rr(d, box, r, fill):
    d.rounded_rectangle(box, radius=r, fill=fill)

def glyph_music(d, s):
    """V-Shape-EQ mit fuenf runden Balken (aussen hoch, Mitte tief), innerhalb der Sicherheitszone."""
    hs = [0.66, 0.46, 0.28, 0.46, 0.66]
    gh, bw, gap = 300 * s, 34 * s, 18 * s
    total = len(hs) * bw + (len(hs) - 1) * gap
    x = (CANVAS * s - total) // 2
    cy = CANVAS * s // 2
    for h in hs:
        hh = int(gh * h)
        rr(d, (x, cy - hh // 2, x + bw, cy + hh // 2), bw // 2, 'white')
        x += bw + gap

def glyph_voice(d, s):
    """Mikrofon mit runden Enden."""
    cx = CANVAS * s // 2
    lw = 24 * s
    cap_w, cap_top, cap_bot = 62 * s, 104 * s, 290 * s
    rr(d, (cx - cap_w, cap_top, cx + cap_w, cap_bot), cap_w, 'white')
    r, cy = 100 * s, 250 * s
    d.arc((cx - r, cy - r, cx + r, cy + r), start=0, end=180, fill='white', width=lw)
    for sx in (-1, 1):                                  # Seiten der U-Form, runde Enden
        x = cx + sx * (r - lw // 2)
        d.line((x, 250 * s - 0, x, 215 * s), fill='white', width=lw)
        d.ellipse((x - lw // 2, 215 * s - lw // 2, x + lw // 2, 215 * s + lw // 2), fill='white')
    d.line((cx, cy + r - lw // 2, cx, 374 * s), fill='white', width=lw)
    rr(d, (cx - 74 * s, 366 * s, cx + 74 * s, 366 * s + lw), lw // 2, 'white')

def foreground(kind):
    big = Image.new('RGBA', (CANVAS * SS, CANVAS * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    (glyph_music if kind == 'music' else glyph_voice)(d, SS)
    k = 0.88                                    # Symbol etwas verkleinern: mehr Luft in jeder Maske
    n = int(CANVAS * SS * k)
    small = big.resize((n, n), Image.LANCZOS)
    out = Image.new('RGBA', big.size, (0, 0, 0, 0))
    out.paste(small, ((big.size[0] - n) // 2, (big.size[1] - n) // 2), small)
    return out.resize((CANVAS, CANVAS), Image.LANCZOS)

def background(engine, size=CANVAS):
    c1, c2 = PALETTE[engine]
    g = Image.new('RGB', (size, size)); px = g.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    g = g.convert('RGBA')
    # weicher Lichtfleck oben links (wie im Hintergrund-Drawable)
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0)); px = glow.load()
    cx, cy, rad = size * 0.25, size * 0.20, size * 0.85
    for y in range(size):
        for x in range(size):
            k = max(0.0, 1 - math.hypot(x - cx, y - cy) / rad)
            px[x, y] = (255, 255, 255, int(64 * k))
    return Image.alpha_composite(g, glow)

def rounded_mask(size, frac=0.22):
    m = Image.new('L', (size * SS, size * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), radius=int(size * SS * frac), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def full_icon(engine, kind, size=256):
    """Fertiges Icon (Hintergrund + Symbol), wie Adaptive Icons mit Rundquadrat-Maske, fuer Android 7.x."""
    bg = background(engine, size)
    fg = foreground(kind).resize((size, size), Image.LANCZOS)
    img = Image.alpha_composite(bg, fg)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), rounded_mask(size))
    return out

if __name__ == '__main__':
    os.makedirs(os.path.join(RES, 'drawable-nodpi'), exist_ok=True)
    os.makedirs(os.path.join(RES, 'mipmap-nodpi'), exist_ok=True)
    for engine in ('fx', 'xhifi'):
        for kind in ('music', 'voice'):
            name = f'{engine}_{kind}'
            foreground(kind).save(os.path.join(RES, 'drawable-nodpi', f'ic_{name}_fg.png'), optimize=True)
            full_icon(engine, kind).save(os.path.join(RES, 'mipmap-nodpi', f'ic_{name}.png'), optimize=True)
    print('Icons geschrieben nach', os.path.abspath(RES))
