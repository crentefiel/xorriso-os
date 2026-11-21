#!/usr/bin/env python3
"""Build 256 Latin-1 8x16 glyphs for native xorriso framebuffer UI.

This is an OFFLINE build-time conversion of the system's free DejaVu font.
No font binaries are committed to the repository.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import sys

fontpath = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
if not fontpath.exists():
    raise SystemExit("Install fonts-dejavu-core before generating the font")
out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dist/font8x16.bin")
out.parent.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(str(fontpath), 12)
data = bytearray()
for cp in range(256):
    tile = Image.new("1", (8, 16))
    if cp >= 32 and cp != 127:
        character = chr(cp)
        bbox = font.getbbox(character)
        if bbox:
            offsetx = max(-1, (8 - (bbox[2]-bbox[0]))//2 - bbox[0])
            offsety = (16 - (bbox[3]-bbox[1]))//2 - bbox[1]
            ImageDraw.Draw(tile).text((offsetx, offsety), character, 1, font=font)
    pixels = tile.load()
    for y in range(16):
        bits = 0
        for x in range(8):
            if pixels[x, y]:
                bits |= 0x80 >> x
        data.append(bits)
assert len(data) == 4096
out.write_bytes(data)
print(f"Generated {out}: {len(data)} bytes")
