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
# Bridges: SMB keeps its original evidence file; the Filen/Internxt bridge has
# its own Cargo graph and evidence. CLOUD_EXPRESSIONS are reviewed only for it.
BRIDGES = {
    'smb': ('rust', 'licensing/rust_dependencies.json'),
    'cloud': ('rust_cloud', 'licensing/rust_cloud_dependencies.json'),
}
CLOUD_EXPRESSIONS = {
    # Vendored provider clients and their bridge (file-level copyleft, retained notices).
    'MPL-2.0': 'MPL-2.0',
    # rustls/aws-lc TLS stack, certificate data and helpers (all permissive).
    'ISC': 'ISC', 'ISC AND (Apache-2.0 OR ISC)': 'ISC', 'Apache-2.0 AND ISC': 'Apache-2.0 AND ISC',
    'ISC AND (Apache-2.0 OR ISC) AND Apache-2.0 AND MIT AND BSD-3-Clause AND (Apache-2.0 OR ISC OR MIT) AND (Apache-2.0 OR ISC OR MIT-0)':
        'ISC AND Apache-2.0 AND MIT AND BSD-3-Clause',
    'Apache-2.0 OR ISC OR MIT': 'MIT', 'CDLA-Permissive-2.0': 'CDLA-Permissive-2.0',
    'CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception': 'Apache-2.0',
    'CC0-1.0 OR MIT-0 OR Apache-2.0': 'MIT-0', 'Unicode-3.0': 'Unicode-3.0',
    'MIT OR Apache-2.0 OR Zlib': 'MIT', 'Unlicense/MIT': 'MIT', 'BSD-3-Clause': 'BSD-3-Clause',
    'BSD-2-Clause OR Apache-2.0 OR MIT': 'MIT',
}
def inventory(bridge='smb'):
    crate_dir = BRIDGES[bridge][0]
    allowed = dict(EXPRESSIONS, **(CLOUD_EXPRESSIONS if bridge == 'cloud' else {}))
    metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--format-version', '1',
        '--manifest-path', str(ROOT / crate_dir / 'Cargo.toml')]))
    result = []
    for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
        base = Path(package['manifest_path']).parent
        expression = package['license']
        if expression is None and package['name'] == 'allo-isolate' and package['version'] == '0.1.27':
            # Cargo declares license-file = LICENSE. Exact Apache text reviewed.
            if digest(base / 'LICENSE') != ALLO_LICENSE_HASH:
                raise SystemExit('allo-isolate license-file changed; review required')
            expression = 'Apache-2.0'
        if expression not in allowed:
            raise SystemExit(f"Unreviewed license: {package['name']} {expression}")
        files = sorted(p for p in base.rglob('*') if p.is_file()
            and 'target' not in p.parts and any(p.name.upper().startswith(n) for n in ['LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'COPYRIGHT']))
        evidence_base = base
        evidence_source = 'crate-archive'
        if not files and package['name'] in ('flutter_rust_bridge', 'flutter_rust_bridge_macros') and package['version'] == '2.11.1':
            evidence_base = ROOT
            evidence_source = 'https://github.com/fzyzcjy/flutter_rust_bridge/blob/v2.11.1/LICENSE'
            files = [ROOT / 'licensing/upstream/flutter_rust_bridge-2.11.1-LICENSE']
        upstream = UPSTREAM_LICENSES.get((package['name'], package['version']))
        if not files and upstream:
            # Crate archive ships no license text; pinned text from the upstream tag.
            evidence_base = ROOT
            evidence_source, files = upstream[0], [ROOT / upstream[1]]
        if not files and package['name'] == 'r-efi' and package['version'] == '6.0.0':
            # Upstream publishes SPDX declaration + author list, no full text.
            files = [base / 'README.md', base / 'AUTHORS', base / 'Cargo.toml']
            evidence_source = 'crate-archive-declaration-and-authors'
        if not files: raise SystemExit(f"Missing license evidence: {package['name']}")
        result.append({'name': package['name'], 'version': package['version'],
            'source': package['source'] or 'project-owned', 'license_expression': expression,
            'selected_grant': allowed[expression],
            'evidence_source': evidence_source,
            'license_files': [{'path': str(p.relative_to(evidence_base)), 'sha256': digest(p)} for p in files]})
    return {'schema_version': 1, 'scope': 'All packages resolved by the bridge Cargo.lock, including platform/build dependencies; excludes compiler/SDK and final packaged binaries.',
        'cargo_lock_sha256': digest(ROOT / crate_dir / 'Cargo.lock'), 'packages': result}

# (name, version) -> (upstream URL of the license text, repo copy).
UPSTREAM_LICENSES = {
    ('jni', '0.22.4'): ('https://github.com/jni-rs/jni-rs/blob/v0.22.4/LICENSE-MIT',
        'licensing/upstream/jni-rs-0.22.4-LICENSE-MIT'),
    ('jni-macros', '0.22.4'): ('https://github.com/jni-rs/jni-rs/blob/v0.22.4-macros/LICENSE-MIT',
        'licensing/upstream/jni-rs-0.22.4-LICENSE-MIT'),
    ('jni-sys-macros', '0.4.1'): ('https://github.com/jni-rs/jni-sys/blob/v0.4.1-macros/LICENSE-MIT',
        'licensing/upstream/jni-sys-0.4.1-LICENSE-MIT'),
    # Crate is the repo's android-release-support/ dir at the commit in .cargo_vcs_info.json.
    ('rustls-platform-verifier-android', '0.2.0'): (
        'https://github.com/rustls/rustls-platform-verifier/blob/252e25161a91af476cbea620e29d277592d27ec7/LICENSE-MIT',
        'licensing/upstream/rustls-platform-verifier-android-0.2.0-LICENSE-MIT'),
}
ALLO_LICENSE_HASH = 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--record', action='store_true')
    parser.add_argument('--bridge', choices=sorted(BRIDGES), default='smb'); args = parser.parse_args()
    path = ROOT / BRIDGES[args.bridge][1]
    value = inventory(args.bridge)
    if args.record: path.write_text(json.dumps(value, indent=2) + '\n')
    elif json.loads(path.read_text()) != value: raise SystemExit('Rust license evidence changed; review and record it')
    print(f"Verified permissive grants and license files for {len(value['packages'])} Cargo packages")
