#!/usr/bin/env python3
"""Verify committed offline renderer bytes, overlays, notices and MPL source."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'packages/file_viewer_documents'


def verify(package=PACKAGE, *, tracked=False):
    manifest = json.loads((package / 'RUNTIME_MANIFEST.json').read_text())
    if (manifest['schema'] != 2 or manifest['upstream']['commit'] !=
            'd264009ca6efb3daed79a39d1ae63133e0f25558' or
            set(manifest['engines']) !=
            {'wordperfect', 'chm', 'spreadsheet', 'ppt', 'postscript', 'xml'}):
        raise ValueError('Unexpected document runtime source or engine set')
    records = [(package / 'assets/runtime' / r['path'], r)
               for r in manifest['assets']]
    records += [(package / 'notices' / r['file'], r)
                for r in manifest['notices']]
    records += [(package / r['path'], r)
                for r in manifest['distributionNotices']]
    records += [(package / r['path'], r)
                for key in ('overlays', 'correspondingSource') for r in manifest[key]]
    for path, record in records:
        if (path.is_symlink() or not path.resolve().is_relative_to(package.resolve())
                or not path.is_file()):
            raise ValueError(f'Missing or unsafe document runtime file: {path}')
        data = path.read_bytes()
        if (hashlib.sha256(data).hexdigest() != record['sha256'] or
                ('bytes' in record and len(data) != record['bytes'])):
            raise ValueError(f'Document runtime checksum mismatch: {path}')
    for directory, expected in (
            (package / 'assets/runtime', {r['path'] for r in manifest['assets']} | {'manifest.json'}),
            (package / 'notices', {r['file'] for r in manifest['notices']}),
            (package / 'assets/licenses',
             {r['path'].removeprefix('assets/licenses/')
              for r in manifest['distributionNotices']}),
            (package / 'corresponding-source',
             {r['path'].removeprefix('corresponding-source/')
              for r in manifest['correspondingSource']})):
        actual = {p.relative_to(directory).as_posix()
                  for p in directory.rglob('*') if p.is_file()}
        if actual != expected:
            raise ValueError(f'Document runtime inventory mismatch: {directory}')
    if (package / 'assets/runtime/manifest.json').read_bytes() != (package / 'RUNTIME_MANIFEST.json').read_bytes():
        raise ValueError('Bundled and source runtime manifests differ')
    required_notices = {'assets/licenses/THIRD_PARTY.txt',
                        'assets/licenses/crisperbooks-host-MIT.txt',
                        'assets/licenses/file-viewer-Apache-2.0.txt'}
    if {r['path'] for r in manifest['distributionNotices']} != required_notices:
        raise ValueError('Unexpected distributed document grants')
    bundle = (package / 'assets/licenses/THIRD_PARTY.txt').read_bytes()
    hashes, names = set(), set()
    for record in manifest['notices']:
        if record['sha256'] in hashes or record['file'] in names:
            raise ValueError('Duplicate source notice text or filename')
        hashes.add(record['sha256'])
        names.add(record['file'])
        content = (package / 'notices' / record['file']).read_bytes()
        if not content or content not in bundle:
            raise ValueError('Aggregate omits complete original notice: ' + record['file'])
        if not record.get('sources'):
            raise ValueError('Missing original notice source mapping')
        for origin in record['sources']:
            attribution = f"Source: {origin['name']} ({origin['source']})\n".encode()
            if attribution not in bundle:
                raise ValueError('Aggregate omits original notice attribution')
    if tracked:
        paths = [p.relative_to(ROOT).as_posix() for p, _ in records]
        paths += ['packages/file_viewer_documents/RUNTIME_MANIFEST.json',
                  'packages/file_viewer_documents/assets/runtime/manifest.json']
        from verify_office_fidelity import verify_git_index
        failures = verify_git_index(ROOT, paths)
        if failures:
            raise ValueError('Document runtime is not retained exactly in Git: ' + '\n'.join(failures))
    return len(records)


if __name__ == '__main__':
    import sys
    print(f'Verified {verify(tracked="--require-tracked" in sys.argv)} '
          'document runtime, notice, overlay and corresponding-source files.')
