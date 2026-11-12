"""Verify the bundled metadata Wasm, worker and reviewed build inputs offline."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ['assets/kindling_metadata.wasm', 'assets/metadata_runtime.js', 'assets/metadata_worker.js']
SOURCES = ['wasm/Cargo.toml', 'wasm/Cargo.lock', 'wasm/src/lib.rs',
           'tool/build_metadata_wasm.py', 'tool/check_wasm.py', 'UPSTREAM.json']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(rustc):
    return {
        'schema': 1,
        'engine': 'Kindling 0.46.2 metadata byte API',
        'abi': 1,
        'rustc': rustc,
        'wasm_bindgen_cli': '0.2.121',
        'target': 'wasm32-unknown-unknown',
        'max_memory_bytes': 402653184,
        'scope': 'Metadata fields only; no EPUB export, cover replacement or host imports.',
        'asset_sha256': {name: digest(ROOT / name) for name in ASSETS},
        'source_sha256': {name: digest(ROOT / name) for name in SOURCES},
    }


if __name__ == '__main__':
    expected = json.loads((ROOT / 'WASM.json').read_text())
    if manifest(expected['rustc']) != expected:
        raise SystemExit('Metadata Wasm or its reviewed source inputs changed; rebuild and review the asset.')
    print('Verified bundled metadata Wasm, worker and source hashes (ABI 1).')
