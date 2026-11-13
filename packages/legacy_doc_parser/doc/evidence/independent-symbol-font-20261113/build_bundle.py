#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Seal retained probe bytes. This does not run a converter or native renderer."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def sha(value):
    return hashlib.sha256(value).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / 'observations.zip'
    records, omitted = [], []
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for path in sorted(args.inputs.rglob('*')):
            if not path.is_file():
                continue
            name = path.relative_to(args.inputs).as_posix()
            value = path.read_bytes()
            record = {'path': name, 'sha256': sha(value), 'bytes': len(value)}
            if value.startswith(b'\x7fELF') or name.endswith(('.js', '.js.deps', '.js.map')):
                omitted.append({**record, 'reason': 'reproducible compiled executable or JavaScript build output; original digest retained'})
                continue
            if '__pycache__' in path.parts:
                continue
            entry = zipfile.ZipInfo(name, (2026, 11, 13, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            output.writestr(entry, value)
            records.append(record)
    manifest = {
        'schema': 'legacy-doc-parser/independent-symbol-font-evidence', 'version': 1,
        'archive': {'path': archive.name, 'sha256': sha(archive.read_bytes()), 'bytes': archive.stat().st_size},
        'records': records, 'omittedReproducibleBuildOutputs': omitted,
        'sourceCheckpoints': {
            'baseline': '43027f9ddb626a4f8fccbef1c41c7f2ea9fccf47',
            'inlineOracle': 'c73749df59d0978c8bcd20710a2ae92184fab11a',
            'symbols': '9aa9da7c1e378d369c03ed1abcebfd70eb496b0d',
            'fontCharsets': 'd5fa58409ce4be3859b05a40132edbef3c4d54cf',
            'fontOracle': '901f85854592cdf5f27d475da27ea5431d6024d5',
            'emptyFontGuard': '927c2cb089cf2d037dc009cdcb9c11b9fe125bf9',
            'combinedRuntime': '1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1',
        },
    }
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    refresh_checksums(args.output)
    print(json.dumps({'files': len(records), 'archiveBytes': archive.stat().st_size, 'omittedDerived': len(omitted)}))


def refresh_checksums(directory):
    values = {path.name: {'sha256': sha(path.read_bytes()), 'bytes': path.stat().st_size}
              for path in sorted(directory.iterdir())
              if path.is_file() and path.name != 'checksums.json'}
    (directory / 'checksums.json').write_text(json.dumps(values, indent=2) + '\n')


if __name__ == '__main__':
    main()
