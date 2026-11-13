#!/usr/bin/env python3
"""Read-only inventory of the exact Stet source resources pinned by CrispCloud."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, required=True)
parser.add_argument("--stet", type=Path, required=True)
args = parser.parse_args()
manifest_path = args.app / "packages/file_viewer_documents/engines/postscript/provenance/upstream.json"
manifest = json.loads(manifest_path.read_text())
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.stet, text=True).strip()
assert commit == manifest["commit"], (commit, manifest["commit"])
font_assets = []
all_verified = []
for asset in manifest["assets"]:
    content = (args.stet / asset["path"]).read_bytes()
    digest = hashlib.sha256(content).hexdigest()
    assert digest == asset["sha256"], asset["path"]
    all_verified.append(asset["path"])
    if asset["path"].endswith(".t1"):
        font_assets.append({"path": asset["path"], "bytes": len(content), "sha256": digest,
                            "gzip9_separate_bytes": len(gzip.compress(content, compresslevel=9, mtime=0))})
mapping_path = "crates/stet/resources/Init/fontmapping.ps"
mapping = (args.stet / mapping_path).read_text()
aliases = [{"requested": a, "embedded": b} for a, b in re.findall(r"^\s*/([^\s]+)\s+/([^\s]+)\s*$", mapping, re.M)]
wasm_path = args.app / "packages/file_viewer_documents/assets/runtime/stet_wasm_bg.wasm"
wasm = wasm_path.read_bytes()
source_paths = [mapping_path, "crates/stet/resources/Init/fontcategory.ps",
                "crates/stet-wasm/src/embedded_resources.rs", "crates/stet-wasm/src/lib.rs",
                "crates/stet-wasm/Cargo.toml", "crates/stet-fonts/src/lib.rs"]
print(json.dumps({
    "schema": 1,
    "scope": "Resource/source inspection, not a native rebuild or embedded-document-font conformance test.",
    "stet_repository": manifest["repository"],
    "stet_commit": commit,
    "stet_version": manifest["version"],
    "manifest_path": str(manifest_path.relative_to(args.app)),
    "verified_manifest_assets": len(all_verified),
    "font_license": "OFL-1.1, upstream's recorded election",
    "font_count": len(font_assets),
    "font_source_bytes": sum(x["bytes"] for x in font_assets),
    "font_source_gzip9_separate_bytes": sum(x["gzip9_separate_bytes"] for x in font_assets),
    "font_assets": font_assets,
    "postscript_mapping_source": mapping_path,
    "postscript_aliases": aliases,
    "missing_font_default": "Helvetica, mapped to NimbusSans-Regular",
    "resource_font_types_accepted_in_source": [0, 1, 2, 3, 42],
    "wasm": {"path": str(wasm_path.relative_to(args.app)), "bytes": len(wasm),
             "sha256": hashlib.sha256(wasm).hexdigest(),
             "gzip9_bytes": len(gzip.compress(wasm, compresslevel=9, mtime=0))},
    "source_hashes": {p: hashlib.sha256((args.stet / p).read_bytes()).hexdigest() for p in source_paths},
    "qualifications": [
        "The 35 .t1 assets are embedded in the native WASM, not 35 independent CSS downloads.",
        "The source-byte sum is not a measured savings from stripping fonts out of a rebuilt WASM.",
        "gzip is an illustrative deterministic compression measurement, not an installed-app size or deployment transfer claim.",
        "The host adapter offers no system-font or external-font loading bridge.",
        "Accepted native font types and embedded font support need representative document validation before claiming format-wide fidelity."
    ]
}, indent=2))
