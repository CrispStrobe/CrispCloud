#!/usr/bin/env python3
"""Verify the reviewed MIT crate slice and independent CAF fixture; no network."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
vendor = root / "packages/crisp_catalog/native/vendor/crispcat-format"
manifest = json.loads((vendor / "UPSTREAM.json").read_text())
assert manifest["repository"] == "https://github.com/CrispStrobe/CrispSorter"
assert manifest["revision"] == "3b0b7cc3216d54bf410184acf1f233bfa29c2284"
for name, digest in manifest["reviewed_sha256"].items():
    path = vendor / name
    assert path.is_file() and not path.is_symlink(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
fixture = root / "cli/test/fixtures/catalog/catfish-v8-windows.caf"
assert hashlib.sha256(fixture.read_bytes()).hexdigest() == "b227276bebe23a180a47914de95ef95e19fbcc84b001456ba256a9970b0561eb"
assert 'license="MIT"' in (vendor / "Cargo.toml").read_text()
print("Reviewed CrispSorter MIT format slice and independent Catfish CAF verified.")
