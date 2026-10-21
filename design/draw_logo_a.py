"""Vector redraw of logo direction A: black squircle, white 口 frame, orange waveform. Writes a full-bleed 1024 square."""
import sys
from PIL import Image, ImageDraw
S = 1024 * 4
img = Image.new("RGB", (S, S), (20, 20, 19))  # #141413
# subtle top-to-bottom lift so the black isn't flat
grad = Image.linear_gradient("L").resize((S, S)).point(lambda v: int((255 - v) * 0.10))
img = Image.composite(Image.new("RGB", (S, S), (44, 42, 40)), img, grad)
d = ImageDraw.Draw(img)
# 口 frame
m, stroke, r = int(S * 0.235), int(S * 0.044), int(S * 0.125)
d.rounded_rectangle([m, m, S - m, S - m], radius=r, outline=(240, 238, 230), width=stroke)
# waveform bars with vertical orange gradient
top, bot = (236, 154, 120), (201, 100, 66)  # terracotta: #EC9A78 → #C96442
heights = [0.11, 0.21, 0.29, 0.21, 0.11]
bw, gap = int(S * 0.044), int(S * 0.036)
x = (S - (len(heights) * bw + (len(heights) - 1) * gap)) // 2
for h in heights:
    hh = int(S * h); y0 = (S - hh) // 2
    bar = Image.new("RGB", (bw, hh))
    bd = ImageDraw.Draw(bar)
    for yy in range(hh):
        t = yy / max(1, hh - 1)
        bd.line([(0, yy), (bw, yy)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    mask = Image.new("L", (bw, hh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, bw - 1, hh - 1], radius=bw // 2, fill=255)
    img.paste(bar, (x, y0), mask)
    x += bw + gap
img.resize((1024, 1024), Image.LANCZOS).save(sys.argv[1], quality=95)
