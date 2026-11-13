#!/usr/bin/env python3
"""Compare retained lossless PPM pixels after verifying their render receipts.

Regions partition page whitespace around each named object. They are analysis
regions, not inferred source shape bounds. Bounding boxes are half-open pixels.
No native application or parser runs and no retained artifact is modified.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

REGIONS = {
    "solid_1031": [0, 0, 330, 135],
    "gradient_one_1029": [0, 135, 330, 190],
    "gradient_two_1027": [0, 190, 330, 245],
    "texture_1026": [0, 245, 330, 420],
    "pattern_1030": [330, 0, 596, 190],
    "picture_1028": [330, 190, 596, 420],
}


def require(test, label):
    if not test:
        raise ValueError(label)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(root, name, read=Path.read_bytes):
    receipt_path = root / (name + "-render.json")
    receipt_bytes = read(receipt_path)
    receipt = json.loads(receipt_bytes)
    require(receipt["rasterDpi"] == 72 and receipt["rasterColorSpace"] == "RGB", "Raster settings")
    require(len(receipt["rasterArtifacts"]) == len(receipt["rasterSha256"]) == 1, "One page")
    record = receipt["rasterArtifacts"][0]
    folder = root / ("render-" + name)
    raw_gz = read(folder / record["path"])
    raw = gzip.decompress(raw_gz)
    require(len(raw_gz) == record["sizeBytes"] and sha(raw_gz) == record["sha256"], "Compressed page receipt")
    require(len(raw) == record["uncompressedSizeBytes"] and
            sha(raw) == record["uncompressedSha256"] == receipt["rasterSha256"][0], "Decoded page receipt")
    manifest = read(folder / receipt["rasterManifest"]["path"])
    require(sha(manifest) == receipt["rasterManifest"]["sha256"], "Raster manifest receipt")
    header = b"P6\n596 420\n255\n"
    require(raw.startswith(header) and len(raw) == len(header) + 596 * 420 * 3,
            "Exact retained RGB PPM header/dimensions")
    pixels = raw[len(header):]
    return pixels, {"receiptPath": str(receipt_path), "receiptSha256": sha(receipt_bytes),
                    "rasterPath": str(folder / record["path"]), "rasterSha256": sha(raw_gz),
                    "uncompressedSha256": sha(raw), "width": 596, "height": 420}


def statistics(a, b, region):
    x0, y0, x1, y1 = region
    count = maximum = error = 0
    min_x, min_y, max_x, max_y = x1, y1, -1, -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            index = 3 * (y * 596 + x)
            dr = abs(a[index] - b[index])
            dg = abs(a[index + 1] - b[index + 1])
            db = abs(a[index + 2] - b[index + 2])
            if dr or dg or db:
                count += 1
                error += dr + dg + db
                maximum = max(maximum, dr, dg, db)
                min_x, min_y = min(min_x, x), min(min_y, y)
                max_x, max_y = max(max_x, x), max(max_y, y)
    area = (x1 - x0) * (y1 - y0)
    return {"changedPixels": count, "totalPixels": area,
            "changedPixelBounds": [min_x, min_y, max_x + 1, max_y + 1] if count else None,
            "maxChannelDelta": maximum, "absoluteChannelDeltaSum": error,
            "meanAbsoluteChannelDeltaAllPixels": error / (area * 3),
            "meanAbsoluteChannelDeltaChangedPixels": error / (count * 3) if count else 0.0}


def compare(root_a, name_a, root_b, name_b, read=Path.read_bytes):
    a, ra = load(root_a, name_a, read)
    b, rb = load(root_b, name_b, read)
    parts = {label: statistics(a, b, region) for label, region in REGIONS.items()}
    whole = statistics(a, b, [0, 0, 596, 420])
    require(sum(p["changedPixels"] for p in parts.values()) == whole["changedPixels"], "Region coverage")
    return {"reference": ra, "actual": rb, "page": whole, "regions": parts}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--before", required=True, type=Path)
    ap.add_argument("--after", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    before, after = args.before.resolve(), args.after.resolve()
    result = {"schemaVersion": 1, "method": __doc__, "dpi": 72, "regions": REGIONS,
              "helperSha256": sha(Path(__file__).read_bytes()), "comparisons": {}}
    comparisons = result["comparisons"]
    for label, root in (("before", before), ("after", after)):
        comparisons[label + "-initial-binary-vs-converted"] = compare(root, "binary", root, "converted")
        for n in range(1, 4):
            prefix = f"roundtrip-{n:02d}"
            comparisons[label + "-" + prefix + "-binary-vs-converted"] = compare(root, prefix + "-binary", root, prefix + "-converted")
    for name in ["binary", "converted"] + [f"roundtrip-{n:02d}-{kind}" for n in range(1, 4) for kind in ("binary", "converted")]:
        comparisons["before-vs-after-" + name] = compare(before, name, after, name)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({name: {"page": value["page"], "regions": {k: v for k, v in value["regions"].items() if v["changedPixels"]}}
                      for name, value in comparisons.items()}, indent=2))


if __name__ == "__main__":
    main()
