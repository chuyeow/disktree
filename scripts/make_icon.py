"""Builds assets/AppIcon.icon (Icon Composer format) from the generated drive render
(assets/drive.png): a graphite background layer plus the drive layer. actool in
scripts/bundle.sh compiles it to Assets.car and a fallback .icns. Needs Pillow."""
import json
import os
from PIL import Image, ImageDraw

N = 1024
os.makedirs("assets/AppIcon.icon/Assets", exist_ok=True)

bg = Image.new("RGBA", (N, N))
d = ImageDraw.Draw(bg)
for y in range(N):
    t = y / N
    d.line([(0, y), (N, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip((58, 66, 82), (16, 19, 25))) + (255,))
bg.save("assets/AppIcon.icon/Assets/background.png")

drive = Image.open("assets/drive.png").convert("RGBA")
drive = drive.crop(drive.getbbox())
s = N * 0.80 / max(drive.size)
drive = drive.resize((round(drive.width * s), round(drive.height * s)), Image.LANCZOS)
fg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
fg.alpha_composite(drive, ((N - drive.width) // 2, (N - drive.height) // 2 + 8))
fg.save("assets/AppIcon.icon/Assets/drive.png")

json.dump({
    "groups": [
        {"layers": [{"image-name": "drive.png", "name": "drive", "glass": False}],
         "shadow": {"kind": "neutral", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0}},
        {"layers": [{"image-name": "background.png", "name": "background", "glass": False}]},
    ],
    "supported-platforms": {"squares": ["macOS"]},
}, open("assets/AppIcon.icon/icon.json", "w"), indent=2)
print("wrote assets/AppIcon.icon")
