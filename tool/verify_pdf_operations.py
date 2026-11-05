#!/usr/bin/env python3
"""Independently inspect actual Dart PDF operation outputs with pypdf."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from pypdf import PdfReader
from pypdf.generic import ContentStream


def image_transforms(pdf: PdfReader, page) -> list[tuple[float, ...]]:
    """Interpret q/Q/cm/Do to check emitted image geometry independently."""
    identity = (1., 0., 0., 1., 0., 0.)
    images: list[tuple[float, ...]] = []

    def multiply(left, right):
        a, b, c, d, e, f = left
        g, h, i, j, k, l = right
        return (a*g+c*h, b*g+d*h, a*i+c*j, b*i+d*j,
                a*k+c*l+e, b*k+d*l+f)

    def walk(stream, resources, transform, depth=0):
        assert depth < 20, 'unexpected recursive Form XObject'
        stack = []
        for operands, operation in ContentStream(stream, pdf).operations:
            if operation == b'q':
                stack.append(transform)
            elif operation == b'Q':
                transform = stack.pop()
            elif operation == b'cm':
                transform = multiply(transform, tuple(map(float, operands)))
            elif operation == b'Do':
                obj = resources['/XObject'][operands[0]].get_object()
                if obj.get('/Subtype') == '/Image':
                    images.append(transform)
                elif obj.get('/Subtype') == '/Form':
                    nested = multiply(transform, tuple(map(float, obj.get('/Matrix', identity))))
                    walk(obj, obj.get('/Resources', resources), nested, depth + 1)

    walk(page.get_contents(), page['/Resources'], identity)
    return images


def verify(directory: Path) -> dict:
    checks: list[str] = []

    def reader(name: str, *, password: str | None = None) -> PdfReader:
        result = PdfReader(directory / name, strict=True)
        if password is not None:
            assert result.is_encrypted, name
            assert result.decrypt(password), name
        else:
            assert not result.is_encrypted, name
        return result

    def texts(pdf: PdfReader) -> list[str]:
        return [page.extract_text().strip() for page in pdf.pages]

    def field_values(pdf: PdfReader) -> dict:
        return {name: field.get('/V') for name, field in (pdf.get_fields() or {}).items()}

    merged = reader('merge.pdf')
    assert texts(merged) == ['Source page 3', 'Source page 1', 'Source page 2',
                             'Appendix page 2', 'Appendix page 1']
    assert len([field for field in merged.get_fields().values()
                if field.get('/FT') == '/Tx']) == 4
    checks.append('ordered merge retains registered fields from both sources')

    extracted = reader('extract.pdf')
    assert texts(extracted) == ['Source page 2']
    assert set(extracted.get_fields()) == {'second'}
    assert field_values(extracted)['second'] == 'Second page field'
    assert any(getattr(item, 'title', '') == 'Source chapter 2'
               for item in extracted.outline)
    for annotation in extracted.pages[0].get('/Annots', []):
        widget = annotation.get_object()
        if widget.get('/Subtype') == '/Widget':
            assert widget['/P'].indirect_reference == extracted.pages[0].indirect_reference
    checks.append('extraction retains selected form and bookmark with remapped widget page')

    assert [page.rotation for page in reader('rotate.pdf').pages] == [90, 0, 90]
    assert texts(reader('reorder.pdf')) == ['Source page 3', 'Source page 2', 'Source page 1']
    assert texts(reader('delete.pdf')) == ['Source page 1', 'Source page 3']
    checks.append('rotation, reordering and live page deletion match selection')

    filled = reader('filled.pdf')
    values = field_values(filled)
    assert values['customer.name'] == 'Жук Αθήνα'
    assert values['agree'] != '/Off'
    assert values['color'] == '/Blue'
    assert values['delivery'] == 'express'
    assert list(values['interests']) == ['books', 'music']
    appearances = [item.get_object()['/AP']['/N'].get_object()
                   for page in filled.pages for item in page.get('/Annots', [])
                   if item.get_object().get('/T') == 'customer.name']
    assert appearances
    assert any(font.get_object().get('/Subtype') == '/Type0'
               and '/ToUnicode' in font.get_object()
               for appearance in appearances
               for font in appearance['/Resources']['/Font'].values())
    checks.append('typed fields and Unicode embedded appearance survive independent parsing')

    marked = reader('watermark.pdf')
    assert all('DRAFT' in text for text in texts(marked))
    assert field_values(marked)['customer.name'] == 'Original'
    assert any(item.get_object().get('/Contents') == 'Keep this existing comment'
               for item in marked.pages[0].get('/Annots', []))
    assert not any(str(item.get_object().get('/NM', '')).startswith('crisp-pdf-watermark-')
                   for page in marked.pages for item in page.get('/Annots', []))
    checks.append('watermark flattens only the new mark and retains forms/comments')

    unicode_marked = reader('watermark-unicode.pdf')
    assert all('Жук Αθήνα' in text for text in texts(unicode_marked))
    assert [page.rotation for page in unicode_marked.pages] == [0, 90, 180, 270]
    for name in ['watermark-logo.pdf', 'image.pdf']:
        document = reader(name)
        for page in document.pages:
            transforms = image_transforms(document, page)
            assert transforms, name
            for a, b, c, d, _, _ in transforms:
                width, height = math.hypot(a, b), math.hypot(c, d)
                assert width > 0 and height > 0, name
                # The fixture logo is 20x10, with no requested stretching.
                assert abs((a*c+b*d)/(width*height)) < 1e-7, (name, 'sheared image')
                assert abs(width/height - 2) < 1e-6, (name, 'changed aspect ratio')
    checks.append('Unicode and image watermarks preserve geometry through all four rotations')

    ocr = reader('ocr.pdf')
    assert 'Жук Αθήνα' in texts(ocr)[0]
    assert b'3 Tr' in ocr.pages[0].get_contents().get_data()
    checks.append('OCR is searchable Unicode text in invisible rendering mode')

    encrypted_rotate = reader('encrypted-rotate.pdf', password='test-password')
    assert encrypted_rotate.pages[0].rotation == 90
    encrypted_merge = reader('encrypted-merge.pdf', password='test-password')
    assert len(encrypted_merge.pages) == 4
    assert len(reader('decrypted-extract.pdf').pages) == 1
    checks.append('ordinary edits retain AES encryption and explicit extraction is plain')

    return {'status': 'passed', 'checks': checks, 'count': len(checks)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path,
                        default=Path('build/pdf_operations_verification'))
    args = parser.parse_args()
    result = verify(args.directory)
    (args.directory / 'independent-verification.json').write_text(
        json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
