#!/usr/bin/env python3
"""Package the audited native-storage licence evidence for Flutter's collector.

Run --write after refreshing the existing Rust inventories. --check requires no
Cargo cache/network and fails when the inventories, locks or output drift.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
STORAGE = ROOT / 'packages/crisp_storage'
OUTPUT = STORAGE / 'NOTICES'
MANIFEST = STORAGE / 'licensing/bundled_notices.json'
SEPARATOR = '\n' + '-' * 80 + '\n'
BRIDGES = {'smb': ('rust', 'rust_dependencies.json'), 'cloud': ('rust_cloud', 'rust_cloud_dependencies.json')}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inputs():
    paths = ['LICENSE']
    for crate, inventory in BRIDGES.values():
        paths.extend([f'{crate}/Cargo.lock', f'licensing/{inventory}'])
    return {p: digest((STORAGE / p).read_bytes()) for p in paths}


def generate(metadata_directory=None):
    sections = ['crisp_storage\n\n' + (STORAGE / 'LICENSE').read_text().strip()]
    grouped = {}
    packages = {}
    for bridge, (crate, inventory_file) in BRIDGES.items():
        inventory = json.loads((STORAGE / 'licensing' / inventory_file).read_text())
        if inventory['cargo_lock_sha256'] != digest((STORAGE / crate / 'Cargo.lock').read_bytes()):
            raise ValueError(f'{bridge}: refresh the existing audited inventory first')
        if metadata_directory:
            metadata = json.loads((metadata_directory / f'crisp-{bridge}-cargo-metadata.json').read_text())
        else:
            metadata = json.loads(subprocess.check_output([
                str(Path.home() / '.cargo/bin/cargo'), 'metadata', '--offline', '--locked', '--format-version', '1',
                '--manifest-path', str(STORAGE / crate / 'Cargo.toml'),
            ]))
        bases = {(p['name'], p['version']): Path(p['manifest_path']).parent for p in metadata['packages']}
        for package in inventory['packages']:
            key = (package['name'], package['version'])
            if key not in bases:
                raise ValueError(f'Inventory package absent from resolved graph: {key}')
            source = (f'https://crates.io/crates/{key[0]}/{key[1]}' if package['source'].startswith('registry+')
                      else 'Corresponding source: ' + str(bases[key].relative_to(ROOT))
                      + ' in the CrispCloud source linked from About.')
            header = f'{key[0]} {key[1]}\nSPDX: {package["license_expression"]}\nSelected grant: {package["selected_grant"]}\nSource: {source}\n\n'
            texts = []
            for entry in package['license_files']:
                path = (bases[key] if package['evidence_source'].startswith('crate-archive') else STORAGE) / entry['path']
                data = path.read_bytes()
                if digest(data) != entry['sha256']:
                    raise ValueError(f'Licence evidence changed: {key} {entry["path"]}')
                # Avoid injecting the collector's component delimiter into a
                # single component: split the retained body into separate entries
                # carrying the same package label instead.
                texts.append(f'File: {entry["path"]}\n\n' + data.decode('utf-8-sig').strip())
            body = header + '\n\n'.join(texts)
            previous = packages.get(key)
            if previous is not None and previous != body:
                raise ValueError(f'Bridge licence evidence disagrees: {key}')
            packages[key] = body
    for key, body in sorted(packages.items()):
        for part in body.split(SEPARATOR):
            grouped.setdefault(part.strip(), []).append(f'{key[0]} (native storage)')
    for text, names in grouped.items():
        sections.append('\n'.join(sorted(set(names))) + '\n\n' + text)
    data = (SEPARATOR.join(sections) + '\n').encode()
    OUTPUT.write_bytes(data)
    manifest = {'schema_version': 1, 'scope': 'Union of both audited locked native-storage graphs, including platform/build dependencies; not a per-artifact reachability claim.',
                'inputs': inputs(), 'notices_sha256': digest(data), 'packages': [{'name': n, 'version': v} for n, v in sorted(packages)]}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Packaged {len(packages)} native dependency versions ({len(data)} bytes)')


def check():
    manifest = json.loads(MANIFEST.read_text())
    if manifest['inputs'] != inputs() or manifest['notices_sha256'] != digest(OUTPUT.read_bytes()):
        raise ValueError('Native notices drifted; review inventories and regenerate')
    expected = set()
    for crate, inventory_file in BRIDGES.values():
        inventory = json.loads((STORAGE / 'licensing' / inventory_file).read_text())
        if inventory['cargo_lock_sha256'] != digest((STORAGE / crate / 'Cargo.lock').read_bytes()):
            raise ValueError('Cargo lock and licence inventory disagree')
        expected.update((p['name'], p['version']) for p in inventory['packages'])
    if expected != {(p['name'], p['version']) for p in manifest['packages']}:
        raise ValueError('Missing native licence entries')
    print(f'Verified packaged notices for {len(expected)} native dependency versions')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--metadata-directory', type=Path)
    args = parser.parse_args()
    if args.write:
        generate(args.metadata_directory)
    check()
