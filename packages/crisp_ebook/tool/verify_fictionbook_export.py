#!/usr/bin/env python3
"""Validate generated FB2/FBZ with the format author's unmodified XSD.

Requires Python lxml (or --xmllint), and the reader package's npm dependencies
for the independent Foliate parser probe. No network access is made.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "test/schema/fictionbook"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT / "build/fictionbook")
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--node", default="node")
    parser.add_argument("--xmllint")
    parser.add_argument("--no-generate", action="store_true")
    args = parser.parse_args()
    metadata = json.loads((SCHEMA / "UPSTREAM.json").read_text())
    for name, expected in metadata["files"].items():
        actual = hashlib.sha256((SCHEMA / name).read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f"Official schema changed without review: {name}")
    directory = args.directory.resolve()
    if not args.no_generate:
        subprocess.run([args.dart, "--packages=.dart_tool/package_config.json",
                        "tool/export_fictionbook_fixture.dart", str(directory)],
                       cwd=ROOT, check=True)
    plain = (directory / "fixture.fb2").read_bytes()
    with zipfile.ZipFile(directory / "fixture.fbz") as archive:
        if archive.namelist() != ["book.fb2"] or archive.read("book.fb2") != plain:
            raise SystemExit("FBZ differs from the standalone FB2 or contains unexpected members")
    schema = None
    if not args.xmllint:
        try:
            from lxml import etree
        except ImportError:
            raise SystemExit("Install lxml for schema validation, or provide --xmllint /path/to/xmllint")
        safe_parser = etree.XMLParser(resolve_entities=False, no_network=True)
        schema = etree.XMLSchema(etree.parse(str(SCHEMA / "FictionBook.xsd"), safe_parser))
    def validate(filename: str) -> None:
        if args.xmllint:
            subprocess.run([args.xmllint, "--nonet", "--noout", "--schema",
                            str(SCHEMA / "FictionBook.xsd"), str(directory / filename)], check=True)
        else:
            schema.assertValid(etree.fromstring((directory / filename).read_bytes(), safe_parser))
    validate("fixture.fb2")
    subprocess.run([args.node, str(ROOT / "tool/verify_fictionbook_foliate.mjs"),
                    str(directory)], cwd=ROOT, check=True)
    subprocess.run([args.dart, "--packages=.dart_tool/package_config.json",
                    "tool/import_fictionbook_fixture.dart", str(directory)],
                   cwd=ROOT, check=True)
    validate("roundtrip.fb2")
    subprocess.run([args.node, str(ROOT / "tool/verify_fictionbook_foliate.mjs"),
                    str(directory), "--roundtrip"], cwd=ROOT, check=True)
    print(f"Official FictionBook XSD, FBZ contents and independent Foliate roundtrip passed ({len(plain)} bytes).")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
