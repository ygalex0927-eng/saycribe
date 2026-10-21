"""Side-by-side comparison of icon candidates at large and small sizes, on light and dark backgrounds."""
import sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, ".")
def squircle(path, size):
    B = size; art = Image.open(path).convert("RGBA").resize((B, B), Image.LANCZOS)
    mask = Image.new("L", (B * 4, B * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, B * 4 - 1, B * 4 - 1], radius=int(B * 4 * 0.225), fill=255)
    art.putalpha(mask.resize((B, B), Image.LANCZOS)); return art
names = [("A2", "A 精修（推荐）"), ("A", "A 原图"), ("B", "B 声音变光标"), ("C", "C 暖橙")]
font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 26)
W, H = 1600, 760
sheet = Image.new("RGBA", (W, H), (255, 255, 255, 255))
d = ImageDraw.Draw(sheet)
d.rectangle([0, H // 2 + 20, W, H], fill=(30, 30, 32))
for i, (k, label) in enumerate(names):
    cx = 200 + i * 400
    sheet.alpha_composite(squircle(f"logo_{k}.jpg", 220), (cx - 110, 30))
    d.text((cx, 275), label, fill=(60, 60, 60), font=font, anchor="mm")
    for j, s in enumerate((64, 32, 16)):
        x = cx - 80 + j * 70
        sheet.alpha_composite(squircle(f"logo_{k}.jpg", s), (x, 310 + (64 - s) // 2))
    sheet.alpha_composite(squircle(f"logo_{k}.jpg", 160), (cx - 80, H // 2 + 60))
    for j, s in enumerate((64, 32)):
        sheet.alpha_composite(squircle(f"logo_{k}.jpg", s), (cx - 50 + j * 80, H // 2 + 250 + (64 - s) // 2))
sheet.convert("RGB").save("logo_compare.png")
