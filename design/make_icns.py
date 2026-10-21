"""Mask a full-bleed square artwork into a macOS icon (824px squircle on 1024 canvas + soft shadow) and write an .iconset."""
import sys, os
from PIL import Image, ImageDraw, ImageFilter
src, iconset = sys.argv[1], sys.argv[2]
os.makedirs(iconset, exist_ok=True)
C, B, R, SS = 1024, 824, 185, 4
art = Image.open(src).convert("RGBA").resize((B, B), Image.LANCZOS)
mask = Image.new("L", (B * SS, B * SS), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, B * SS - 1, B * SS - 1], radius=R * SS, fill=255)
mask = mask.resize((B, B), Image.LANCZOS)
off = (C - B) // 2
shadow = Image.new("RGBA", (C, C), (0, 0, 0, 0))
sh = Image.new("RGBA", (B, B), (0, 0, 0, 90)); sh.putalpha(mask.point(lambda a: a * 90 // 255))
shadow.paste(sh, (off, off + 10), sh)
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
icon = shadow.copy()
art.putalpha(mask)
icon.alpha_composite(art, (off, off))
icon.save("design/AppIcon_1024.png")
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        icon.resize((size * scale, size * scale), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}{'@2x' if scale == 2 else ''}.png")
