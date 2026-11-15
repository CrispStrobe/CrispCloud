#!/usr/bin/env python3
"""Verify the supplemental notices; not a universal licence-compliance claim."""
import hashlib
import json
from pathlib import Path
from generate_storage_notices import check

ROOT = Path(__file__).resolve().parents[1]


def verify():
    check()
    pdfium = json.loads((ROOT / 'assets/licenses/pdfium/manifest.json').read_text())
    if hashlib.sha256((ROOT / 'assets/licenses/pdfium/LICENSE.txt').read_bytes()).hexdigest() != pdfium['license_sha256']:
        raise ValueError('PDFium notice changed; review the matching native archive')
    manifest = json.loads((ROOT / 'assets/licenses/office_fonts/manifest.json').read_text())
    covered = set()
    for family in manifest['families']:
        notice = (ROOT / family['notice']).read_bytes()
        if hashlib.sha256(notice).hexdigest() != family['notice_sha256']:
            raise ValueError('Office font notice changed; review required')
        if b'SIL OPEN FONT LICENSE' not in notice or len(notice) < 4000:
            raise ValueError('Missing full OFL text')
        for font in family['fonts']:
            covered.add(font['path'])
            if hashlib.sha256((ROOT / font['path']).read_bytes()).hexdigest() != font['sha256']:
                raise ValueError('Office font changed; review copyright and licence metadata')
    actual = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'packages/quds_office_editor/fonts').glob('*.ttf')}
    if actual != covered:
        raise ValueError('Unreviewed Office font assets')
    print(f'Verified full notices for all {len(covered)} bundled Office fonts')


if __name__ == '__main__':
    verify()
