#!/usr/bin/env python3
"""Verify committed offline renderer bytes, overlays, notices and MPL source."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'packages/file_viewer_documents'


def verify(package=PACKAGE, *, tracked=False):
    manifest = json.loads((package / 'RUNTIME_MANIFEST.json').read_text())
    if (manifest['schema'] != 1 or manifest['upstream']['commit'] !=
            'd264009ca6efb3daed79a39d1ae63133e0f25558' or
            set(manifest['engines']) !=
            {'wordperfect', 'chm', 'spreadsheet', 'ppt', 'postscript', 'xml'}):
        raise ValueError('Unexpected document runtime source or engine set')
    records = [(package / 'assets/runtime' / r['path'], r)
               for r in manifest['assets']]
    records += [(package / 'assets/licenses' / r['file'], r)
                for r in manifest['notices']]
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
            (package / 'corresponding-source',
             {r['path'].removeprefix('corresponding-source/')
              for r in manifest['correspondingSource']})):
        actual = {p.relative_to(directory).as_posix()
                  for p in directory.rglob('*') if p.is_file()}
        if actual != expected:
            raise ValueError(f'Document runtime inventory mismatch: {directory}')
    if (package / 'assets/runtime/manifest.json').read_bytes() != (package / 'RUNTIME_MANIFEST.json').read_bytes():
        raise ValueError('Bundled and source runtime manifests differ')
    if not (package / 'assets/licenses/THIRD_PARTY.txt').is_file():
        raise ValueError('Missing aggregate third-party grants')
    if tracked:
        paths = [p.relative_to(ROOT).as_posix() for p, _ in records]
        paths += ['packages/file_viewer_documents/RUNTIME_MANIFEST.json',
                  'packages/file_viewer_documents/assets/licenses/THIRD_PARTY.txt']
        from verify_office_fidelity import verify_git_index
        failures = verify_git_index(ROOT, paths)
        if failures:
            raise ValueError('Document runtime is not retained exactly in Git: ' + '\n'.join(failures))
    return len(records)


if __name__ == '__main__':
    import sys
    print(f'Verified {verify(tracked="--require-tracked" in sys.argv)} '
          'document runtime, notice, overlay and corresponding-source files.')
