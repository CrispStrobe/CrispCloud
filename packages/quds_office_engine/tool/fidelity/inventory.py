#!/usr/bin/env python3
"""Require the authored Office corpus inventory and write a SHA-256 receipt.

Run ``clean`` before *all* producer tests/scripts and ``verify`` afterwards.
Cleaning removes only manifest-listed Office files and this tool's receipt;
verification rejects unlisted Office files in engine build/fidelity* scopes.
Neither action depends on the current working directory. Hashes are provenance,
not approval of the content: semantic, schema, and rendering oracles remain
independent gates.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile


PACKAGE = "quds_office_engine"
DEFAULT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = Path(__file__).with_name("output_manifest.json")
OFFICE_SUFFIXES = {".docx", ".xlsx", ".pptx"}
RECEIPT = "fidelity-inventory.json"


class InventoryError(ValueError):
    """An unsafe manifest, incorrect package, or invalid output inventory."""


@dataclass(frozen=True)
class Manifest:
    paths: tuple[str, ...]
    producers: dict[str, str]
    sha256: str
    series_count: int
    standalone_count: int


def _artifact_path(value: object) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise InventoryError(f"Invalid artifact path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or str(path) != value or ".." in path.parts:
        raise InventoryError(f"Artifact path must be normalized and relative: {value}")
    if path.suffix.lower() not in OFFICE_SUFFIXES:
        raise InventoryError(f"Manifest entries must be Office files: {value}")
    if len(path.parts) > 1:
        in_scope = re.fullmatch(r"fidelity(?:-[a-z0-9-]+)?", path.parts[0])
    else:
        in_scope = re.fullmatch(r"fidelity-[a-z0-9-]+\.(?:docx|xlsx|pptx)", value)
    if not in_scope:
        raise InventoryError(f"Artifact is outside the engine fidelity scope: {value}")
    return value


def load_manifest(path: Path = DEFAULT_MANIFEST) -> Manifest:
    raw = path.read_bytes()
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("version") != 1:
        raise InventoryError("Manifest must be a version 1 object")
    if data.get("package") != PACKAGE:
        raise InventoryError(f"Manifest package must be {PACKAGE}")
    series, standalone = data.get("series"), data.get("standalone")
    if not isinstance(series, list) or not isinstance(standalone, list):
        raise InventoryError("Manifest requires series and standalone lists")
    producers: dict[str, str] = {}

    def add(value: object, producer: object) -> None:
        name = _artifact_path(value)
        if not isinstance(producer, str) or not producer.strip():
            raise InventoryError(f"Missing producer attribution for {name}")
        if name in producers:
            raise InventoryError(f"Duplicate manifest artifact: {name}")
        producers[name] = producer

    for entry in series:
        if not isinstance(entry, dict):
            raise InventoryError("Each series must be an object")
        pattern, cycles = entry.get("pattern"), entry.get("cycles")
        if not isinstance(pattern, str) or pattern.count("{cycle}") != 1:
            raise InventoryError("A series pattern requires exactly one {cycle}")
        if (not isinstance(cycles, list) or
                any(type(cycle) is not int for cycle in cycles) or
                cycles not in ([0, 1, 2], [1, 2, 3])):
            raise InventoryError(f"Series must list exactly three cycles: {pattern}")
        for cycle in cycles:
            add(pattern.replace("{cycle}", str(cycle)), entry.get("producer"))
    for entry in standalone:
        if not isinstance(entry, dict):
            raise InventoryError("Each standalone artifact must be an object")
        add(entry.get("path"), entry.get("producer"))
    if not producers:
        raise InventoryError("Manifest must require at least one artifact")
    count = data.get("expected_file_count")
    if type(count) is not int or count != len(producers):
        raise InventoryError(
            f"Manifest count {count!r} disagrees with {len(producers)} authored paths"
        )
    return Manifest(tuple(sorted(producers)), producers, hashlib.sha256(raw).hexdigest(),
                    len(series), len(standalone))


def package_root(path: Path = DEFAULT_ROOT) -> Path:
    root = path.resolve()
    pubspec = root / "pubspec.yaml"
    if not pubspec.is_file() or not re.search(
        rf"(?m)^name:\s*['\"]?{PACKAGE}['\"]?\s*(?:#.*)?$",
        pubspec.read_text(encoding="utf-8"),
    ):
        raise InventoryError(f"Not the {PACKAGE} package root: {root}")
    if (root / "build").is_symlink():
        raise InventoryError("The package build directory must not be a symlink")
    return root


def _safe_file(build: Path, relative: str) -> Path:
    """Preflight every component before reading or deleting a managed file."""
    target = build / relative
    current = build
    for part in PurePosixPath(relative).parts:
        current = current / part
        if current.is_symlink():
            raise InventoryError(f"Refusing symlink in artifact path: {current}")
        if current != target and current.exists() and not current.is_dir():
            raise InventoryError(f"Artifact parent is not a directory: {current}")
    if target.exists() and not target.is_file():
        raise InventoryError(f"Artifact is not a regular file: {target}")
    return target


def clean(manifest: Manifest, root: Path) -> list[str]:
    build = package_root(root) / "build"
    # Validate the complete deletion plan first: an unsafe later path must not
    # leave earlier evidence deleted in a half-completed clean operation.
    targets = [_safe_file(build, name) for name in (*manifest.paths, RECEIPT)]
    removed = []
    for target in targets:
        if target.exists():
            target.unlink()
            removed.append(target.relative_to(build).as_posix())
    return removed


def _observed_files(build: Path) -> set[str]:
    observed: set[str] = set()
    if not build.exists():
        return observed
    for entry in sorted(build.iterdir()):
        if entry.name != "fidelity" and not entry.name.startswith("fidelity-"):
            continue
        if entry.is_symlink():
            raise InventoryError(f"Refusing symlink in fidelity scope: {entry}")
        if entry.is_dir():
            for parent, directories, files in os.walk(entry, followlinks=False):
                for name in sorted(directories + files):
                    child = Path(parent) / name
                    if child.is_symlink():
                        raise InventoryError(f"Refusing symlink in fidelity scope: {child}")
                for name in files:
                    path = Path(parent) / name
                    if path.suffix.lower() in OFFICE_SUFFIXES:
                        observed.add(path.relative_to(build).as_posix())
        elif entry.suffix.lower() in OFFICE_SUFFIXES:
            observed.add(entry.relative_to(build).as_posix())
    return observed


def verify(manifest: Manifest, root: Path) -> dict[str, object]:
    build = package_root(root) / "build"
    expected = set(manifest.paths)
    errors: list[str] = []
    records: list[dict[str, object]] = []
    try:
        observed = _observed_files(build)
    except InventoryError as error:
        observed = set()
        errors.append(str(error))
    for name in sorted(expected - observed):
        errors.append(f"Missing required artifact: {name}")
    for name in sorted(observed - expected):
        errors.append(f"Unexpected Office artifact: {name}")
    for name in sorted(expected & observed):
        try:
            path = _safe_file(build, name)
            size = path.stat().st_size
            if size == 0:
                raise InventoryError("empty file")
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                if len(set(names)) != len(names):
                    raise InventoryError("duplicate ZIP member names")
                required = {"[Content_Types].xml", "_rels/.rels"}
                if not required.issubset(names):
                    raise InventoryError("missing OPC content types or package relationships")
                bad_member = archive.testzip()
                if bad_member:
                    raise InventoryError(f"corrupt ZIP member: {bad_member}")
            digest = hashlib.sha256()
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            records.append({"path": name, "bytes": size, "sha256": digest.hexdigest(),
                            "producer": manifest.producers[name]})
        except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
            errors.append(f"Invalid artifact {name}: {error}")
    return {
        "version": 1,
        "ok": not errors,
        "package": PACKAGE,
        "artifact_root": "build",
        "manifest_sha256": manifest.sha256,
        "expected_files": len(expected),
        "observed_files": len(observed),
        "verified_files": len(records),
        "three_cycle_series": manifest.series_count,
        "standalone_files": manifest.standalone_count,
        "files": records,
        "errors": errors,
    }


def write_receipt(report: dict[str, object], root: Path) -> Path:
    build = package_root(root) / "build"
    target = _safe_file(build, RECEIPT)
    build.mkdir(parents=True, exist_ok=True)
    # A failed verification replaces any earlier successful receipt too.
    target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("clean", "verify"))
    parser.add_argument("--package-root", type=Path, default=DEFAULT_ROOT,
                        help="engine root containing pubspec.yaml; defaults to this script's package")
    args = parser.parse_args(argv)
    try:
        root = package_root(args.package_root)
        manifest = load_manifest()
        if args.action == "clean":
            removed = clean(manifest, root)
            print(f"Removed {len(removed)} manifest artifacts/receipts from {root / 'build'}")
            return 0
        report = verify(manifest, root)
        receipt = write_receipt(report, root)
        print(f"Inventory: {report['verified_files']}/{report['expected_files']} verified; "
              f"{len(report['errors'])} failures; receipt {receipt}")
        for error in report["errors"]:
            print(error, file=sys.stderr)
        return 0 if report["ok"] else 1
    except (OSError, ValueError) as error:
        print(f"Inventory failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
