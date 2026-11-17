#!/usr/bin/env python3
"""Verify the emitted alias PDFs with Poppler, independently of Quds readers.

Example:
  python3 verify_pdf_rendering.py --input engine/render --output poppler-check

Run the emitting Dart tests first. This script never runs Dart/Flutter tests or
accesses CI. The output directory must be empty so a rerun cannot erase evidence.
The identity PDF is a raster control only: its legacy ToUnicode loses aliases.
"""

import argparse
import datetime
import hashlib
import importlib.metadata
import json
import platform
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
INPUT_NAMES = (
    "encoded-aliases.pdf",
    "identity-glyph-reference.pdf",
    "word-unicode-aliases.pdf",
    "authored-text.txt",
)
SOURCE_PATHS = (
    "packages/quds_office_engine/lib/src/pdf/pdf_font.dart",
    "packages/quds_office_engine/lib/src/pdf/pdf_document.dart",
    "packages/quds_office_engine/lib/src/pdf/pdf_canvas.dart",
    "packages/quds_office_engine/lib/src/pdf/pdf_stream.dart",
    "packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart",
    "packages/quds_office_engine/lib/src/fonts/font_subsetter.dart",
    "packages/quds_office_engine/lib/src/fonts/sfnt_parser.dart",
    "packages/quds_office_engine/test/pdf_cid_encoding_test.dart",
    "packages/quds_office_engine/test/pdf_unicode_alias_export_test.dart",
    "packages/quds_office_engine/test/support/pdf_alias_fixture.dart",
    "packages/quds_office_editor/fonts/LiberationSans-Regular.ttf",
    "pubspec.lock",
)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_record(path):
    data = path.read_bytes()
    return {"path": str(path), "bytes": len(data), "sha256": sha(data)}


def source_snapshot():
    return {
        name: sha((REPO / name).read_bytes())
        for name in SOURCE_PATHS
        if (REPO / name).is_file()
    }


def code_points(text):
    return [f"U+{ord(char):04X}" for char in text]


def save_receipt(output, receipt):
    temporary = output / "receipt.json.tmp"
    temporary.write_text(
        json.dumps(receipt, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(output / "receipt.json")


def run_command(name, command, output, receipt, timeout=60):
    started = now()
    clock = time.monotonic()
    error = None
    try:
        result = subprocess.run(
            command, cwd=output, capture_output=True, timeout=timeout, check=False
        )
        stdout, stderr, exit_code = result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as exc:
        stdout, stderr, exit_code = exc.stdout or b"", exc.stderr or b"", None
        error = f"Command exceeded {timeout} seconds"
    except OSError as exc:
        stdout, stderr, exit_code = b"", b"", None
        error = f"{type(exc).__name__}: {exc}"
    stdout_path, stderr_path = f"{name}.stdout.txt", f"{name}.stderr.txt"
    (output / stdout_path).write_bytes(stdout)
    (output / stderr_path).write_bytes(stderr)
    item = {
        "name": name,
        "command": command,
        "cwd": str(output),
        "started_utc": started,
        "duration_seconds": time.monotonic() - clock,
        "exit_code": exit_code,
        "stdout": stdout_path,
        "stderr": stderr_path,
        "stdout_sha256": sha(stdout),
        "stderr_sha256": sha(stderr),
        "passed": exit_code == 0,
    }
    if error is not None:
        item["error"] = error
    receipt["commands"].append(item)
    save_receipt(output, receipt)
    return item, stdout, stderr


def compare_rasters(output):
    from PIL import Image, ImageChops

    names = ("encoded-aliases", "identity-glyph-reference")
    images = []
    samples = {}
    try:
        for name in names:
            path = output / f"{name}.png"
            with Image.open(path) as source:
                mode = source.mode
                image = source.convert("RGB")
            images.append(image)
            rgb = image.tobytes()
            samples[name] = {
                "png": path.name,
                "png_sha256": sha(path.read_bytes()),
                "original_mode": mode,
                "width": image.width,
                "height": image.height,
                "pixel_count": image.width * image.height,
                "nonwhite_ink_pixels": sum(
                    rgb[index:index + 3] != b"\xff\xff\xff"
                    for index in range(0, len(rgb), 3)
                ),
                "rgb_sha256": sha(rgb),
            }
        same_dimensions = images[0].size == images[1].size
        expected_dimensions = all(image.size == (320, 112) for image in images)
        rgb_mode = all(sample["original_mode"] == "RGB" for sample in samples.values())
        differing_pixels = None
        difference_bbox = None
        if same_dimensions:
            difference = ImageChops.difference(images[0], images[1])
            try:
                difference.save(output / "raster-difference.png")
                pixels = difference.tobytes()
                differing_pixels = sum(
                    pixels[index:index + 3] != b"\x00\x00\x00"
                    for index in range(0, len(pixels), 3)
                )
                difference_bbox = difference.getbbox()
            finally:
                difference.close()
        nonempty = all(sample["nonwhite_ink_pixels"] > 0 for sample in samples.values())
        return {
            "dpi": 72,
            "page": 1,
            "comparison": "Exact RGB pixels; no tolerance, rescaling, or alignment",
            "expected_fixture_dimensions": [320, 112],
            "samples": samples,
            "same_dimensions": same_dimensions,
            "expected_dimensions": expected_dimensions,
            "rgb_mode": rgb_mode,
            "both_have_ink": nonempty,
            "differing_pixels": differing_pixels,
            "difference_bbox": difference_bbox,
            "passed": same_dimensions and expected_dimensions and rgb_mode
            and nonempty and differing_pixels == 0,
        }
    finally:
        for image in images:
            image.close()


def compare_text(output, authored):
    results = {}
    for name in ("encoded-aliases", "word-unicode-aliases"):
        path = output / f"{name}.txt"
        raw = path.read_bytes()
        # Decode bytes directly: Path.read_text would also translate CRLF.
        decoded = raw.decode("utf-8", errors="strict")
        actual = decoded.rstrip("\n\f")
        results[name] = {
            "text_file": path.name,
            "raw_sha256": sha(raw),
            "raw_code_points": code_points(decoded),
            "compared_code_points": code_points(actual),
            "trimmed_trailing_code_points": code_points(decoded[len(actual):]),
            "passed": bool(authored) and actual == authored,
        }
    return {
        "expected_code_points": code_points(authored),
        "normalization": "Extracted text: remove trailing U+000A/U+000C only; authored text unchanged",
        "identity_control": "Raster only; deliberately not an extraction oracle",
        "results": results,
        "passed": all(result["passed"] for result in results.values()),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Engine render directory")
    parser.add_argument("--output", type=Path, required=True, help="New or empty evidence directory")
    parser.add_argument(
        "--producer-receipt", type=Path,
        help="Optional engine validation receipt to copy/hash alongside the artifacts",
    )
    args = parser.parse_args()
    source_dir, output = args.input.resolve(), args.output.resolve()
    if source_dir == output:
        parser.error("Use a separate output directory to preserve the emitted inputs")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        parser.error("The output directory must be new or empty; preserve earlier receipts")
    output.mkdir(parents=True, exist_ok=True)
    receipt = {
        "schema": "quds-independent-pdf-rendering-v1",
        "started_utc": now(),
        "input_directory": str(source_dir),
        "scope": "Poppler verifies CID-mapped PDF painting and Unicode extraction for synthetic Latin-outline aliases",
        "limits": "One raster fixture at 72 dpi; no emoji/CJK coverage, shaping-parity, platform-conformance, or performance claim",
        "source_provenance": "Contemporaneous checkout hashes, not proof of artifact-generation provenance; see producer receipt when supplied",
        "source_before_sha256": source_snapshot(),
        "harness_sha256": sha(Path(__file__).read_bytes()),
        "runtime": {"python": sys.version, "platform": platform.platform()},
        "commands": [],
        "checks": {},
        "passed": False,
        "github_actions": "No Actions access or waits",
    }
    save_receipt(output, receipt)
    original_paths = {name: source_dir / name for name in INPUT_NAMES}
    if args.producer_receipt is not None:
        original_paths["producer-receipt.json"] = args.producer_receipt.resolve()
    try:
        receipt["inputs_before"] = {}
        for name, path in original_paths.items():
            data = path.read_bytes()
            receipt["inputs_before"][name] = {
                "path": str(path), "bytes": len(data), "sha256": sha(data)
            }
            (output / name).write_bytes(data)
        (output / "verify-pdf-rendering-used.py").write_bytes(Path(__file__).read_bytes())
        receipt["runtime"]["pillow"] = importlib.metadata.version("Pillow")
        authored = (output / "authored-text.txt").read_bytes().decode("utf-8", errors="strict")
        executables = {}
        for tool in ("pdftoppm", "pdftotext"):
            located = shutil.which(tool)
            if located is None:
                raise FileNotFoundError(f"Required executable is unavailable: {tool}")
            executables[tool] = located
            _, stdout, stderr = run_command(f"{tool}-version", [located, "-v"], output, receipt)
            receipt["runtime"][tool] = {
                "invoked_path": located,
                "resolved_executable": file_record(Path(located).resolve()),
                "version_stdout": stdout.decode("utf-8", errors="replace"),
                "version_stderr": stderr.decode("utf-8", errors="replace"),
            }
        run_command("source-head", ["git", "-C", str(REPO), "rev-parse", "HEAD"], output, receipt)
        for name in ("encoded-aliases", "identity-glyph-reference"):
            run_command(
                f"raster-{name}",
                [executables["pdftoppm"], "-f", "1", "-l", "1", "-r", "72",
                 "-singlefile", "-png", str(output / f"{name}.pdf"), str(output / name)],
                output, receipt,
            )
        for name in ("encoded-aliases", "word-unicode-aliases"):
            run_command(
                f"text-{name}",
                [executables["pdftotext"], "-enc", "UTF-8", "-eol", "unix",
                 str(output / f"{name}.pdf"), str(output / f"{name}.txt")],
                output, receipt,
            )
        for name, check in (
            ("raster", lambda: compare_rasters(output)),
            ("text", lambda: compare_text(output, authored)),
        ):
            try:
                receipt["checks"][name] = check()
            except Exception as exc:
                receipt["checks"][name] = {"passed": False, "error": f"{type(exc).__name__}: {exc}"}
            save_receipt(output, receipt)
    except Exception as exc:
        receipt["error"] = f"{type(exc).__name__}: {exc}"
        (output / "error.txt").write_text(traceback.format_exc(), encoding="utf-8")
    finally:
        receipt["source_after_sha256"] = source_snapshot()
        receipt["source_unchanged"] = receipt["source_before_sha256"] == receipt["source_after_sha256"]
        receipt["inputs_after"] = {
            name: file_record(path) for name, path in original_paths.items() if path.is_file()
        }
        receipt["inputs_unchanged"] = receipt.get("inputs_before") == receipt["inputs_after"]
        receipt["artifacts"] = {
            path.name: {"bytes": path.stat().st_size, "sha256": sha(path.read_bytes())}
            for path in sorted(output.iterdir())
            if path.is_file() and path.name not in {"receipt.json", "receipt.json.tmp"}
        }
        receipt["finished_utc"] = now()
        receipt["passed"] = (
            "error" not in receipt and receipt["source_unchanged"] and receipt["inputs_unchanged"]
            and all(item["passed"] for item in receipt["commands"])
            and len(receipt["checks"]) == 2
            and all(item["passed"] for item in receipt["checks"].values())
        )
        save_receipt(output, receipt)
    print(json.dumps({"receipt": str(output / "receipt.json"), "passed": receipt["passed"]}))
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
