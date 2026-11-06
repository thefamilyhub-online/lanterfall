"""Draws Lanternfall's UI pieces (9-slice textures and small icons) into assets/ui/.

Style: chunky outlined "game" buttons, brass lantern-frame panels with rivets,
lantern-glow tower cards (copper / silver / gold frames for tiers 1-3) and a
swallowtail ribbon. Everything is drawn 4x and scaled down for smooth edges.

    python3 art/tools/make_ui.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ui")
S = 4  # supersample
INK = (18, 14, 43, 255)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def lighten(c, f):
    return tuple(min(255, int(v + (255 - v) * f)) for v in c[:3]) + (c[3],)


def canvas(w, h):
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))


def save(img, name):
    w, h = img.size
    img = img.resize((w // S, h // S), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


def rrect(img, box, r, fill):
    """Rounded rect in logical units."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = [v * S for v in box]
    d.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=r * S, fill=fill)


def grad_rrect(img, box, r, top, bottom):
    """Vertical gradient clipped to a rounded rect."""
    x0, y0, x1, y1 = box
    w, h = (x1 - x0) * S, (y1 - y0) * S
    g = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(g)
    for y in range(h):
        t = y / max(1, h - 1)
        gd.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=r * S, fill=255)
    img.paste(g, (x0 * S, y0 * S), mask)


def flame_poly(cx, cy, r, steps=48):
    """A teardrop flame centred on (cx, cy), radius r, in pixel units."""
    pts = []
    for i in range(steps):
        t = i / steps * 2 * math.pi
        # round bottom, pointed top with a slight lick to the right
        x = math.sin(t)
        y = -math.cos(t)
        if y < 0:  # top half: pinch to a point
            k = (-y) ** 1.6
            x *= (1 - k * 0.85)
            y = y * 1.55
            x += 0.18 * k * (-y)
        pts.append((cx + x * r, cy + y * r + r * 0.25))
    return pts


def draw_flame(img, cx, cy, r, outline=True):
    d = ImageDraw.Draw(img)
    cx, cy, r = cx * S, cy * S, r * S
    if outline:
        d.polygon(flame_poly(cx, cy, r + 2.5 * S), fill=INK)
    d.polygon(flame_poly(cx, cy, r), fill=hexc("#FF8A3D"))
    d.polygon(flame_poly(cx, cy + r * 0.18, r * 0.66), fill=hexc("#FFC44D"))
    d.polygon(flame_poly(cx, cy + r * 0.36, r * 0.34), fill=hexc("#FFF3C2"))


# ------------------------------------------------------------------ buttons
BUTTONS = {
    "gold": ("#FFE58A", "#FFBE3D", "#C9711F"),
    "blue": ("#9ADDFF", "#45A3F0", "#2559B0"),
    "green": ("#A6F2A0", "#46C46A", "#237F45"),
    "purple": ("#CDB0FF", "#8B5AE8", "#5130A0"),
    "red": ("#FFAA94", "#EE5E4A", "#A2311F"),
    "gray": ("#9CA2B8", "#6E7590", "#474D66"),
}
BW, BH = 96, 80


def button(name, top, body, lip, state):
    img = canvas(BW, BH)
    top, body, lip = hexc(top), hexc(body), hexc(lip)
    if state == "hover":
        top, body = lighten(top, 0.25), lighten(body, 0.18)
    lip_h = 3 if state == "pressed" else 8
    drop = 5 if state == "pressed" else 0
    # dark outline + soft drop under the button
    rrect(img, (0, 2, BW, BH), 18, (0, 0, 0, 70))
    rrect(img, (0, drop, BW, BH - 2), 18, INK)
    rrect(img, (3, drop + 3, BW - 3, BH - 5), 15, lip)
    grad_rrect(img, (3, drop + 3, BW - 3, BH - 5 - lip_h), 15, top, body)
    # glossy top band
    gloss = canvas(BW, BH)
    rrect(gloss, (8, drop + 6, BW - 8, drop + 6 + int((BH - 16 - lip_h) * 0.42)), 10, (255, 255, 255, 70))
    # sparkle dot top-left
    rrect(gloss, (11, drop + 9, 17, drop + 13), 2, (255, 255, 255, 120))
    img.alpha_composite(gloss)
    save(img, "btn_%s_%s.png" % (name, state))


# ------------------------------------------------------------------ panels
def brass_panel():
    w = h = 96
    img = canvas(w, h)
    rrect(img, (0, 3, w, h), 20, (0, 0, 0, 90))
    rrect(img, (0, 0, w, h - 3), 20, INK)
    grad_rrect(img, (3, 3, w - 3, h - 6), 17, hexc("#FFE08A"), hexc("#B5782C"))
    rrect(img, (8, 8, w - 8, h - 11), 13, INK)
    grad_rrect(img, (10, 10, w - 10, h - 13), 11, hexc("#2A3170", 240), hexc("#161B42", 240))
    # rivets
    d = ImageDraw.Draw(img)
    for (x, y) in [(17, 5.5), (w - 17, 5.5), (17, h - 8.5), (w - 17, h - 8.5)]:
        d.ellipse([(x - 2.2) * S, (y - 2.2) * S, (x + 2.2) * S, (y + 2.2) * S], fill=hexc("#7A4E1C"))
        d.ellipse([(x - 1.5) * S, (y - 1.9) * S, (x + 0.9) * S, (y + 0.5) * S], fill=hexc("#FFF0C0"))
    save(img, "panel_brass.png")


def soft_panel():
    w = h = 48
    img = canvas(w, h)
    rrect(img, (0, 0, w, h), 12, hexc("#2E3770", 230))
    rrect(img, (2, 2, w - 2, h - 2), 10, hexc("#10153A", 225))
    save(img, "panel_soft.png")


def pill():
    w, h = 64, 44
    img = canvas(w, h)
    rrect(img, (0, 0, w, h), 22, INK)
    grad_rrect(img, (3, 3, w - 3, h - 3), 19, hexc("#F2C46B"), hexc("#A86F28"))
    grad_rrect(img, (6, 6, w - 6, h - 6), 16, hexc("#1A2050"), hexc("#0E1230"))
    save(img, "pill.png")


def ribbon():
    w, h = 360, 76
    img = canvas(w, h)
    d = ImageDraw.Draw(img)

    def poly(pts, fill):
        d.polygon([(x * S, y * S) for x, y in pts], fill=fill)

    # swallowtails behind the band
    for flip in (False, True):
        def X(x):
            return w - x if flip else x
        poly([(X(48), 20), (X(0), 20), (X(16), 44), (X(0), 70), (X(48), 70)], INK)
        poly([(X(46), 23), (X(6), 23), (X(20), 44), (X(6), 67), (X(46), 67)], hexc("#4B2F9C"))
        poly([(X(30), 58), (X(46), 67), (X(46), 58)], hexc("#2A1A63"))  # fold shadow
    # band
    rrect(img, (24, 4, w - 24, 60), 10, INK)
    grad_rrect(img, (27, 7, w - 27, 57), 8, hexc("#B49BFF"), hexc("#6B47D8"))
    # brass trims
    grad_rrect(img, (27, 7, w - 27, 12), 3, hexc("#FFE59A"), hexc("#E0A646"))
    grad_rrect(img, (27, 52, w - 27, 57), 3, hexc("#E0A646"), hexc("#A86F28"))
    gloss = canvas(w, h)
    rrect(gloss, (34, 14, w - 34, 28), 6, (255, 255, 255, 45))
    img.alpha_composite(gloss)
    save(img, "ribbon.png")


# ------------------------------------------------------------------ tower cards
CARD_METALS = {
    "copper": ("#FFC79A", "#B8652F"),
    "silver": ("#F2F8FF", "#8FA6C4"),
    "gold": ("#FFF0A0", "#D9902B"),
}
CW, CH = 108, 132


def card(name, top, bottom):
    img = canvas(CW, CH)
    rrect(img, (0, 3, CW, CH), 16, (0, 0, 0, 90))
    rrect(img, (0, 0, CW, CH - 3), 16, INK)
    grad_rrect(img, (3, 3, CW - 3, CH - 6), 13, hexc(top), hexc(bottom))
    rrect(img, (7, 7, CW - 7, CH - 10), 10, INK)
    grad_rrect(img, (9, 9, CW - 9, CH - 12), 8, hexc("#2F3478"), hexc("#171A45"))
    # warm lantern glow behind the tower picture
    glow = canvas(CW, CH)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([22 * S, 16 * S, (CW - 22) * S, 80 * S], fill=(255, 205, 100, 200))
    glow = glow.filter(ImageFilter.GaussianBlur(9 * S))
    mask = Image.new("L", glow.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([9 * S, 9 * S, (CW - 9) * S, (CH - 12) * S], radius=8 * S, fill=255)
    clipped = Image.new("RGBA", glow.size, (0, 0, 0, 0))
    clipped.paste(glow, (0, 0), mask)
    img.alpha_composite(clipped)
    # name strip
    rrect(img, (9, CH - 46, CW - 9, CH - 12), 8, hexc("#0D1030", 210))
    save(img, "card_%s.png" % name)


def card_halo():
    w, h = CW + 36, CH + 36
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([10 * S, 10 * S, (w - 10) * S, (h - 10) * S], radius=22 * S, fill=(255, 205, 90, 230))
    img = img.filter(ImageFilter.GaussianBlur(7 * S))
    save(img, "card_halo.png")


# ------------------------------------------------------------------ small pieces
def tile():
    w = h = 72
    img = canvas(w, h)
    rrect(img, (0, 3, w, h), 14, (0, 0, 0, 80))
    rrect(img, (0, 0, w, h - 3), 14, INK)
    grad_rrect(img, (3, 3, w - 3, h - 6), 11, hexc("#5C6BD6"), hexc("#2D3592"))
    gloss = canvas(w, h)
    rrect(gloss, (7, 6, w - 7, 26), 8, (255, 255, 255, 50))
    img.alpha_composite(gloss)
    save(img, "tile.png")


def bars():
    w, h = 48, 24
    img = canvas(w, h)
    rrect(img, (0, 0, w, h), 12, INK)
    rrect(img, (3, 3, w - 3, h - 3), 9, hexc("#0E1230"))
    save(img, "bar_bg.png")
    img = canvas(w, h)
    grad_rrect(img, (3, 3, w - 3, h - 3), 9, hexc("#FFE58A"), hexc("#FF9F2E"))
    gloss = canvas(w, h)
    rrect(gloss, (6, 5, w - 6, 10), 3, (255, 255, 255, 110))
    img.alpha_composite(gloss)
    save(img, "bar_fill.png")


def coin():
    w = h = 48
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, w * S - 1, h * S - 1], fill=INK)
    d.ellipse([3 * S, 3 * S, (w - 3) * S, (h - 3) * S], fill=hexc("#C9711F"))
    d.ellipse([3 * S, 2 * S, (w - 3) * S, (h - 6) * S], fill=hexc("#FFC44D"))
    d.ellipse([8 * S, 7 * S, (w - 8) * S, (h - 11) * S], fill=hexc("#F0A030"))
    d.ellipse([10 * S, 9 * S, (w - 10) * S, (h - 13) * S], fill=hexc("#FFD45E"))
    # flame stamp
    d.polygon(flame_poly(24 * S, 20 * S, 7.5 * S), fill=hexc("#E88A1E"))
    d.polygon(flame_poly(24 * S, 22 * S, 4.2 * S), fill=hexc("#FFF0B0"))
    save(img, "coin.png")


def flame():
    w = h = 64
    img = canvas(w, h)
    draw_flame(img, 32, 33, 17)
    save(img, "flame.png")


def badge():
    w = h = 30
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, w * S - 1, h * S - 1], fill=INK)
    d.ellipse([2.5 * S, 2.5 * S, (w - 2.5) * S, (h - 2.5) * S], fill=hexc("#FFC44D"))
    d.ellipse([4.5 * S, 3.5 * S, (w - 4.5) * S, (h - 6) * S], fill=hexc("#FFE08A"))
    save(img, "badge.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n, (t, b, l) in BUTTONS.items():
        for st in ("normal", "hover", "pressed"):
            button(n, t, b, l, st)
    brass_panel()
    soft_panel()
    pill()
    ribbon()
    for n, (t, b) in CARD_METALS.items():
        card(n, t, b)
    card_halo()
    tile()
    bars()
    coin()
    flame()
    badge()
