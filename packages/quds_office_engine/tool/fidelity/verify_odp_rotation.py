#!/usr/bin/env python3
"""Check source-generated ODP rotation against OASIS and LibreOffice/Poppler.

Generate inputs with make_odp_rotation_fixtures.dart. This consumer check reads
ZIP/XML independently of the Dart engine, validates every package XML part,
then compares color bounds to coordinates calculated from the fixture's source
geometry. RGB strips/cells distinguish clockwise from counterclockwise output.
It does not claim general font/layout or native editable-table parity.
"""

import argparse
import collections
import hashlib
import json
import math
import shutil
import subprocess
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile

import numpy as np
from lxml import etree
from PIL import Image


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rotated_bounds(degrees, left=60, top=80, width=120, height=40):
    angle = math.radians(degrees)
    cosine, sine = math.cos(angle), math.sin(angle)
    points = []
    for x, y in [(left, top), (left + width, top),
                 (left + width, top + height), (left, top + height)]:
        dx, dy = x - 120, y - 100
        points.append((120 + cosine * dx - sine * dy,
                       100 + sine * dx + cosine * dy))
    return [min(point[0] for point in points), min(point[1] for point in points),
            max(point[0] for point in points), max(point[1] for point in points)]


def color_bounds(pixels, channel):
    selected = ((pixels[:, :, channel] > 200)
                & (pixels[:, :, (channel + 1) % 3] < 50)
                & (pixels[:, :, (channel + 2) % 3] < 50))
    return mask_bounds(selected)


def mask_bounds(selected):
    y, x = np.nonzero(selected)
    if not len(x):
        return {"pixels": 0, "bounds_pt": None}
    return {"pixels": len(x), "bounds_pt":
            [float(x.min()) / 2, float(y.min()) / 2,
             float(x.max() + 1) / 2, float(y.max() + 1) / 2]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path)
    parser.add_argument("--generate", action="store_true",
                        help="Generate fixtures from this checkout in the fresh output directory")
    parser.add_argument("--schemas", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.generate == (args.fixtures is not None):
        parser.error("Choose exactly one of --generate and --fixtures")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    package = Path(__file__).resolve().parents[2]
    repository = package.parents[1]
    generator = package / "tool/fidelity/make_odp_rotation_fixtures.dart"
    writer = package / "lib/src/slide/serial/odp_presentation_writer.dart"
    report = {"commands": [], "files": [], "errors": [],
              "input_mode": "generated_by_this_run" if args.generate else "existing_artifacts"}

    def source_identity():
        identity = {"git_head": subprocess.check_output(
            ["git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip(),
            "files": {}}
        for path in [writer, generator, Path(__file__).resolve()]:
            relative = str(path.relative_to(repository))
            at_head = subprocess.run(["git", "-C", str(repository), "show",
                                      f"HEAD:{relative}"], capture_output=True)
            head_hash = hashlib.sha256(at_head.stdout).hexdigest() if not at_head.returncode else None
            current_hash = sha256(path)
            identity["files"][relative] = {"sha256": current_hash, "head_sha256": head_hash,
                                           "matches_head": current_hash == head_hash}
        return identity

    report["source_before"] = source_identity()

    def run(command, cwd=None):
        process = subprocess.run(command, capture_output=True, timeout=180, cwd=cwd)
        index = len(report["commands"])
        (args.output / f"command-{index:02d}.stdout").write_bytes(process.stdout)
        (args.output / f"command-{index:02d}.stderr").write_bytes(process.stderr)
        report["commands"].append({"argv": command, "cwd": str(cwd) if cwd else None,
                                   "exit_code": process.returncode})
        if process.returncode:
            raise RuntimeError(f"Command failed: {command}")
        return process.stdout.decode(errors="replace")

    def require(condition, message):
        if not condition:
            report["errors"].append(message)

    schema_path = args.schemas / "OpenDocument-v1.3-schema.rng"
    manifest_path = args.schemas / "OpenDocument-v1.3-manifest-schema.rng"
    schema = etree.RelaxNG(etree.parse(str(schema_path)))
    manifest_schema = etree.RelaxNG(etree.parse(str(manifest_path)))
    report["schemas_sha256"] = {path.name: sha256(path)
                                for path in [schema_path, manifest_path]}
    report["tools"] = {}
    for name in ["soffice", "pdftoppm", "pdftotext"]:
        executable = shutil.which(name)
        if not executable:
            raise RuntimeError(f"Executable not found: {name}")
        report["tools"][name] = {"path": executable, "sha256": sha256(executable)}
    report["libreoffice_version"] = run(["soffice", "--version"]).strip()
    if args.generate:
        args.fixtures = args.output / "fixtures"
        run(["dart", "run", str(generator), str(args.fixtures)], cwd=package)
    else:
        args.fixtures = args.fixtures.resolve()
        report["existing_artifact_notice"] = (
            "Input hashes are bound, but this run does not establish generation from the recorded writer.")
    cases = []
    for degrees in [90, 180, 270, -90, 45, -30]:
        cases.append((f"slide-rotation-{degrees}", {0: rotated_bounds(degrees)}, ["Rotation"]))
    cases.append(("slide-rotation-picture",
                  {color: rotated_bounds(90, 60 + color * 40, 80, 40, 40)
                   for color in range(3)}, []))
    for degrees in [90, -90, 45]:
        for rtl in [False, True]:
            cases.append((f"slide-rotation-table-{degrees}{'-rtl' if rtl else ''}",
                          {color: rotated_bounds(degrees, 60 + (2 - color if rtl else color) * 40,
                                                 80, 40, 40) for color in range(3)},
                          ["R", "G", "B"]))
    cases.append(("slide-rotation-table-empty", {}, []))
    cases.append(("slide-rotation-table-stroke",
                  {color: rotated_bounds(90, 60 + color * 40, 80, 40, 40)
                   for color in range(3)}, ["R", "G", "B"]))
    cases.append(("slide-rotation-table-ragged",
                  {color: rotated_bounds(90, 60 + (2 - color) * 40, 80, 40, 40 / 3)
                   for color in range(3)}, ["R", "G", "B", "Tail"]))
    paths = [args.fixtures / f"{name}.odp" for name, _, _ in cases]
    require(all(path.is_file() for path in paths), "Every source fixture must exist")
    if report["errors"]:
        raise RuntimeError(report["errors"])
    run(["soffice", "--headless", "--convert-to", "pdf", "--outdir", str(args.output),
         *map(str, paths)])
    for name, expected, expected_text in cases:
        path = args.fixtures / f"{name}.odp"
        entry = {"name": name, "input_sha256": sha256(path), "xml": [], "colors": {}}
        report["files"].append(entry)
        with ZipFile(path) as archive:
            require(archive.infolist()[0].filename == "mimetype", f"{name}: mimetype first")
            require(archive.getinfo("mimetype").compress_type == ZIP_STORED,
                    f"{name}: mimetype uncompressed")
            require(archive.read("mimetype") == b"application/vnd.oasis.opendocument.presentation",
                    f"{name}: presentation MIME type")
            for part in ["content.xml", "styles.xml", "meta.xml", "META-INF/manifest.xml"]:
                xml = etree.fromstring(archive.read(part))
                validator = manifest_schema if part.startswith("META-INF/") else schema
                valid = validator.validate(xml)
                entry["xml"].append({"part": part, "valid": valid,
                                     "errors": str(validator.error_log) if not valid else ""})
                require(valid, f"{name}: schema-valid {part}")
        pdf = args.output / f"{name}.pdf"
        require(pdf.is_file(), f"{name}: consumer PDF exists")
        if not pdf.is_file():
            continue
        prefix = args.output / name
        run(["pdftoppm", "-r", "144", "-singlefile", "-png", str(pdf), str(prefix)])
        text = run(["pdftotext", str(pdf), "-"])
        entry["text"] = text
        # Poppler reorders and splits glyphs at non-right-angle rotations.
        # Check retained characters independently of that reading-order policy;
        # asymmetric RGB geometry below checks the actual rotation direction.
        require(collections.Counter(character for character in text if not character.isspace())
                == collections.Counter("".join(expected_text)), f"{name}: retained text characters")
        pixels = np.asarray(Image.open(prefix.with_suffix(".png")).convert("RGB"))
        # Impress quantizes page lengths to hundredths of a millimeter; the
        # subsequent raster can therefore round up by one pixel at 144 dpi.
        entry["raster_dimensions"] = [int(pixels.shape[1]), int(pixels.shape[0])]
        require(abs(pixels.shape[0] - 810) <= 1 and abs(pixels.shape[1] - 1440) <= 1,
                f"{name}: source slide dimensions within consumer quantization")
        for color, bounds in expected.items():
            observed = color_bounds(pixels, color)
            entry["colors"]["RGB"[color]] = {**observed, "expected_bounds_pt": bounds}
            require(observed["pixels"] > 100, f"{name}: visible {'RGB'[color]} fill")
            if observed["bounds_pt"]:
                error = max(abs(actual - target)
                            for actual, target in zip(observed["bounds_pt"], bounds))
                entry["colors"]["RGB"[color]]["maximum_bound_error_pt"] = error
                require(error <= 1.5, f"{name}: {'RGB'[color]} geometry error {error:.6f}pt")
        if name == "slide-rotation-table-stroke":
            outline = mask_bounds((pixels[:, :, 0] > 200) & (pixels[:, :, 1] < 50)
                                  & (pixels[:, :, 2] > 200))
            entry["outline"] = outline
            require(outline["pixels"] > 100, f"{name}: authored magenta outline visible")
            if outline["bounds_pt"]:
                error = max(abs(actual - target) for actual, target in
                            zip(outline["bounds_pt"], [99, 39, 141, 161]))
                require(error <= 1.5, f"{name}: authored two-point outline width retained")
        entry["pdf_sha256"] = sha256(pdf)
        entry["png_sha256"] = sha256(prefix.with_suffix(".png"))
    report["source_after"] = source_identity()
    require(report["source_before"] == report["source_after"], "Source inputs unchanged during consumer checks")
    report["passed"] = not report["errors"]
    (args.output / "rotation-consumer-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "fixtures": len(report["files"]),
                      "errors": report["errors"]}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
