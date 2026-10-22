"""Comparison sheet for icon concepts: large + Dock/menu sizes, on light and dark grounds."""
import sys
from PIL import Image, ImageDraw, ImageFont

def squircle(path, size):
    art = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.225), fill=255)
    art.putalpha(m.resize((size, size), Image.LANCZOS))
    return art

items = [("concepts/B_voice_nib.png", "B 声音笔尖 · 墨黑"), ("concepts/B2_voice_nib_paper.png", "B 声音笔尖 · 纸白"),
         ("concepts/A_quill_wave.png", "A 声波羽毛 · 纸白"), ("concepts/A2_quill_wave_dark.png", "A 声波羽毛 · 墨黑")]
font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 24)
W, H = 1600, 800
sheet = Image.new("RGBA", (W, H), (250, 249, 245, 255))
d = ImageDraw.Draw(sheet)
d.rectangle([0, H // 2 + 30, W, H], fill=(28, 27, 26))
for i, (path, label) in enumerate(items):
    cx = 200 + i * 400
    sheet.alpha_composite(squircle(path, 230), (cx - 115, 24))
    d.text((cx, 284), label, fill=(70, 66, 60), font=font, anchor="mm")
    for j, s in enumerate((64, 32, 16)):
        sheet.alpha_composite(squircle(path, s), (cx - 85 + j * 72, 316 + (64 - s) // 2))
    sheet.alpha_composite(squircle(path, 170), (cx - 85, H // 2 + 60))
    for j, s in enumerate((64, 32)):
        sheet.alpha_composite(squircle(path, s), (cx - 52 + j * 80, H // 2 + 254 + (64 - s) // 2))
sheet.convert("RGB").save("concept_compare.png")
