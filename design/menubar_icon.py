"""Draw the menu-bar template icon: five rounded wave bars, black on transparent."""
from PIL import Image, ImageDraw
import sys
out = sys.argv[1]
for scale, suffix in ((1, ""), (2, "@2x")):
    S = 18 * scale * 8  # supersample
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    heights = [0.30, 0.62, 0.86, 0.62, 0.30]
    bar_w, gap = S * 0.105, S * 0.075
    total = len(heights) * bar_w + (len(heights) - 1) * gap
    x = (S - total) / 2
    for h in heights:
        hh = S * h
        y0 = (S - hh) / 2
        d.rounded_rectangle([x, y0, x + bar_w, y0 + hh], radius=bar_w / 2, fill=(0, 0, 0, 255))
        x += bar_w + gap
    img.resize((18 * scale, 18 * scale), Image.LANCZOS).save(f"{out}/MenuBarIcon{suffix}.png")
