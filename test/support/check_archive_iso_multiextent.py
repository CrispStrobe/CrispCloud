#!/usr/bin/env python3
"""Verify separately authored ISO section chains using an installed 7-Zip.

First run emit_archive_iso_multiextent.dart with an output directory. This
checker never mounts an image or executes a member; it extracts into a temporary
directory and checks the complete output namespace, size and SHA-256.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--sevenzip', type=Path, required=True)
    args = parser.parse_args()
    source = args.input.resolve()
    engine = args.sevenzip.resolve()
    records = json.loads((source / 'manifest.json').read_text())
    checked = []
    for record in records:
        image = source / record['image']
        if hashlib.sha256(image.read_bytes()).hexdigest() != record['imageSha256']:
            raise ValueError('Fixture image changed before independent reading')
        with tempfile.TemporaryDirectory(prefix='iso-multiextent-') as temporary:
            output = Path(temporary)
            run = subprocess.run([str(engine), 'x', '-y', '-bd', f'-o{output}', str(image)],
                                 capture_output=True, text=True, check=False, timeout=30)
            if run.returncode:
                raise RuntimeError(f'7-Zip failed for {image.name}: {run.stdout}\n{run.stderr}')
            files = sorted(path.relative_to(output).as_posix()
                           for path in output.rglob('*') if path.is_file())
            if files != [record['memberName']]:
                raise ValueError(f'Unexpected independent namespace: {files}')
            data = (output / files[0]).read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if len(data) != record['memberBytes'] or digest != record['memberSha256']:
                raise ValueError('Independent extraction returned different bytes')
            checked.append({'image': image.name, 'member': files[0],
                            'bytes': len(data), 'sha256': digest})
    print(json.dumps({'checked': checked}, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
