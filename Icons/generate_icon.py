#!/usr/bin/env python3
"""Package black-and-white CD artwork into a macOS ICNS (no Pillow required).
Light and dark PNGs follow system appearance.
"""
from pathlib import Path
import subprocess
import tempfile
import shutil
import struct
root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as staging:
    iconset = Path(staging) / "AppIcon.iconset"
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            target = iconset / f"icon_{size}x{size}{suffix}.png"
            subprocess.run(["sips", "-z", str(size * scale), str(size * scale), str(root / "AppIcon-light.png"), "--out", str(target)], check=True, stdout=subprocess.DEVNULL)
    # ICNS PNG chunks avoid a dependency on the GUI-backed iconutil converter.
    chunks = []
    for tag, name in [(b"icp4", "icon_16x16.png"), (b"icp5", "icon_32x32.png"), (b"icp6", "icon_32x32@2x.png"), (b"ic07", "icon_128x128.png"), (b"ic08", "icon_256x256.png"), (b"ic09", "icon_512x512.png"), (b"ic10", "icon_512x512@2x.png")]:
        data = (iconset / name).read_bytes()
        chunks.append(tag + struct.pack(">I", len(data) + 8) + data)
    body = b"".join(chunks)
    (root / "AppIcon.icns").write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    resources = root.parent / "Resources"
    for name in ("AppIcon.icns", "AppIcon-light.png", "AppIcon-dark.png"):
        shutil.copy2(root / name, resources / name)
print("Packaged black-and-white CD icon resources")
