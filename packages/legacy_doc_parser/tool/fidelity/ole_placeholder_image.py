#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reproduce the converter's generic OLE icon, never a source-document preview.

Requires Pillow and the exact DejaVu Sans font identified below. Writes a new
output directory; it never replaces the checked image or runtime constant.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, __version__ as pillow_version


FONT_SHA256 = "57f73e11f51999432bf7ab22ce55b6f945d5eca1bf824404cfa9ec2e3718c84e"
PNG_SHA256 = "37db6492bd5cefedb386946d7c929c4ccacad0fdadbfaf47f53dca32df3a88fe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.font.read_bytes()).hexdigest() != FONT_SHA256:
        raise ValueError("The reproduction font does not match the recorded font")
    if args.output.exists():
        raise FileExistsError(args.output)
    image = Image.new("RGB", (288, 144), "#EEEEEE")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(args.font), 26)
    draw.rectangle((1, 1, 286, 142), outline="#808080", width=2)
    for text, y in (("Embedded object", 53), ("Preview unavailable", 94)):
        draw.text((144, y), text, font=font, fill="#343434", anchor="mm")
    stream = io.BytesIO()
    image.save(stream, format="PNG", compress_level=9)
    data = stream.getvalue()
    if hashlib.sha256(data).hexdigest() != PNG_SHA256:
        raise ValueError("Rasterizer output differs from the reviewed PNG")
    args.output.mkdir(parents=True)
    (args.output / "embedded-object-placeholder.png").write_bytes(data)
    (args.output / "embedded-object-placeholder.base64").write_text(
        base64.b64encode(data).decode() + "\n"
    )
    record = {
        "generatedByConverter": True,
        "sourcePreviewRecovered": False,
        "imageBytes": len(data),
        "imageSha256": PNG_SHA256,
        "fontSha256": FONT_SHA256,
        "pillowVersion": pillow_version,
        "pixelSize": [288, 144],
        "displaySizePoints": [72, 36],
        "labels": ["Embedded object", "Preview unavailable"],
    }
    (args.output / "recipe.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record))


if __name__ == "__main__":
    main()
