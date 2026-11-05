#!/usr/bin/env python3
"""Build the small, deterministic Unicode font fixture (fontTools 4.61.1)."""

import argparse
import hashlib
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont


def main():
    package = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source", type=Path,
        default=package.parent / "pdf_document/test/fonts/DejaVuSans.ttf")
    args = parser.parse_args()
    font = TTFont(args.source, recalcTimestamp=False)
    options = subset.Options()
    options.recalc_timestamp = False
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.name_legacy = True
    options.name_languages = ["*"]
    subsetter = subset.Subsetter(options=options)
    text = "".join(chr(i) for i in range(32, 127)) + (
        "ÄÖÜäöüßéèÅñŽųŁ€–ЖукМоскваΑθήναשלום")
    subsetter.populate(text=text)
    subsetter.subset(font)
    for record in font["name"].names:
        if record.nameID in (1, 3, 4, 6):
            name = "CrispPdfTestSans" if record.nameID == 6 else "Crisp PDF Test Sans"
            record.string = name.encode(record.getEncoding())
    output = package / "test/fonts/CrispPdfTestSans.ttf"
    output.parent.mkdir(parents=True, exist_ok=True)
    font.save(output)
    print(f"source SHA-256 {hashlib.sha256(args.source.read_bytes()).hexdigest()}")
    print(f"fixture SHA-256 {hashlib.sha256(output.read_bytes()).hexdigest()}")
    print(f"fixture bytes {output.stat().st_size}")


if __name__ == "__main__":
    main()
