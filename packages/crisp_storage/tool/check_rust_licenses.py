"""Record/check exact Cargo license evidence; refuse unreviewed expressions."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# Exact reviewed expressions. OR selects a permissive grant, not every grant.
EXPRESSIONS = {
    'MIT': 'MIT', 'MIT OR Apache-2.0': 'MIT', 'Apache-2.0 OR MIT': 'MIT',
    'Apache-2.0/MIT': 'MIT', 'MIT/Apache-2.0': 'MIT',
    '0BSD OR MIT OR Apache-2.0': 'MIT', 'BSD-3-Clause OR MIT OR Apache-2.0': 'MIT',
    'Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT': 'MIT',
    'MIT OR Apache-2.0 OR LGPL-2.1-or-later': 'MIT',
    'MIT OR Zlib OR Apache-2.0': 'MIT', 'Unlicense OR MIT': 'MIT',
    'Zlib OR Apache-2.0 OR MIT': 'MIT', '(MIT OR Apache-2.0) AND Unicode-3.0': 'MIT AND Unicode-3.0',
    'Apache-2.0': 'Apache-2.0', 'Apache-2.0 OR Apache-2.0 WITH LLVM-exception OR MIT': 'MIT',
}
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def inventory():
    metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--format-version', '1',
        '--manifest-path', str(ROOT / 'rust/Cargo.toml')]))
    result = []
    for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
        base = Path(package['manifest_path']).parent
        expression = package['license']
        if expression is None and package['name'] == 'allo-isolate' and package['version'] == '0.1.27':
            # Cargo declares license-file = LICENSE. Exact Apache text reviewed.
            if digest(base / 'LICENSE') != ALLO_LICENSE_HASH:
                raise SystemExit('allo-isolate license-file changed; review required')
            expression = 'Apache-2.0'
        if expression not in EXPRESSIONS:
            raise SystemExit(f"Unreviewed license: {package['name']} {expression}")
        files = sorted(p for p in base.rglob('*') if p.is_file()
            and 'target' not in p.parts and any(p.name.upper().startswith(n) for n in ['LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'COPYRIGHT']))
        evidence_base = base
        evidence_source = 'crate-archive'
        if not files and package['name'] in ('flutter_rust_bridge', 'flutter_rust_bridge_macros') and package['version'] == '2.11.1':
            evidence_base = ROOT
            evidence_source = 'https://github.com/fzyzcjy/flutter_rust_bridge/blob/v2.11.1/LICENSE'
            files = [ROOT / 'licensing/upstream/flutter_rust_bridge-2.11.1-LICENSE']
        if not files and package['name'] == 'r-efi' and package['version'] == '6.0.0':
            # Upstream publishes SPDX declaration + author list, no full text.
            files = [base / 'README.md', base / 'AUTHORS', base / 'Cargo.toml']
            evidence_source = 'crate-archive-declaration-and-authors'
        if not files: raise SystemExit(f"Missing license evidence: {package['name']}")
        result.append({'name': package['name'], 'version': package['version'],
            'source': package['source'] or 'project-owned', 'license_expression': expression,
            'selected_grant': EXPRESSIONS[expression],
            'evidence_source': evidence_source,
            'license_files': [{'path': str(p.relative_to(evidence_base)), 'sha256': digest(p)} for p in files]})
    return {'schema_version': 1, 'scope': 'All packages resolved by the bridge Cargo.lock, including platform/build dependencies; excludes compiler/SDK and final packaged binaries.',
        'cargo_lock_sha256': digest(ROOT / 'rust/Cargo.lock'), 'packages': result}

ALLO_LICENSE_HASH = 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--record', action='store_true'); args = parser.parse_args()
    path = ROOT / 'licensing/rust_dependencies.json'
    value = inventory()
    if args.record: path.write_text(json.dumps(value, indent=2) + '\n')
    elif json.loads(path.read_text()) != value: raise SystemExit('Rust license evidence changed; review and record it')
    print(f"Verified permissive grants and license files for {len(value['packages'])} Cargo packages")
