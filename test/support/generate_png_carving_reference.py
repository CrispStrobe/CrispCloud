#!/usr/bin/env python3
"""Produce independent PNG carving inputs with Pillow and Python zlib.

Original synthetic images only. The production Dart carver is never imported.
The versioned compressed fixtures make portable acceptance independent of disk
access; the separate manifest pins source bytes, selected ranges and pixels.
"""
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import struct
import zlib

from PIL import Image, PngImagePlugin

SIGNATURE = b'\x89PNG\r\n\x1a\n'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def chunk(kind, content):
    return struct.pack('>I', len(content)) + kind + content + struct.pack('>I', zlib.crc32(kind + content))


def authored(raw, *, width=1, height=1, color=2, depth=8, interlace=0, extra=b'', encoded=None):
    header = struct.pack('>IIBBBBB', width, height, depth, color, 0, 0, interlace)
    encoded = zlib.compress(raw) if encoded is None else encoded
    return SIGNATURE + chunk(b'IHDR', header) + extra + chunk(b'IDAT', encoded) + chunk(b'IEND', b'')


def pillow(mode, size, seed, *, metadata=False):
    image = Image.new(mode, size)
    channels = len(image.getbands())
    raw = bytes((seed + i * 17 + i // 7) % 256 for i in range(size[0] * size[1] * channels))
    image.frombytes(raw)
    output = io.BytesIO()
    info = PngImagePlugin.PngInfo()
    if metadata:
        info.add_text('Author', 'CrispCloud independent synthetic fixture')
    image.save(output, 'PNG', pnginfo=info, dpi=(96, 96) if metadata else None)
    return output.getvalue()


def pixel_receipt(png):
    with Image.open(io.BytesIO(png)) as image:
        image.verify()
    with Image.open(io.BytesIO(png)) as image:
        image.load()
        return {'mode': image.mode, 'width': image.width, 'height': image.height,
                'pixels_sha256': sha(image.tobytes())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    sources = {}
    cases = {}

    def add_case(name, pieces):
        source = bytearray()
        candidates = []
        for piece, status, reason in pieces:
            offset = len(source)
            source.extend(piece)
            if status is not None:
                row = {'offset': offset, 'status': status, 'reason': reason}
                if status == 'recoverable':
                    row.update({'endExclusive': len(source), 'bytes': len(piece), 'sha256': sha(piece),
                                'outputName': f'png-{offset:010d}.png', **pixel_receipt(piece)})
                candidates.append(row)
        sources[name] = bytes(source)
        cases[name] = {'bytes': len(source), 'sha256': sha(source), 'candidates': candidates}

    rgb = pillow('RGB', (3, 4), 5)
    rgba = pillow('RGBA', (4, 2), 27)
    gray = pillow('L', (5, 5), 91)
    graya = pillow('LA', (5, 3), 12)
    good = lambda data: (data, 'recoverable', None)
    bad = lambda data, why: (data, 'rejected', why)
    unsupported = lambda data, why: (data, 'unsupported', why)
    noise = lambda data: (data, None, None)

    add_case('read-boundary', [noise(b'\x55' * 65533), good(rgb), noise(b'garbage region\x00'), good(rgba)])
    crc = bytearray(rgb)
    crc[29] ^= 1
    add_case('damaged-regions', [good(gray), noise(b'damaged'), bad(bytes(crc), 'checksumMismatch'),
              noise(b'\x00' * 7), good(graya), bad(rgb[:41], 'truncated')])
    raw = bytes([0, 1, 2, 3])
    z = zlib.compress(raw)
    add_case('malformed-image-data', [
        bad(authored(raw, encoded=z[:-4] + b'junk' + z[-4:]), 'invalidZlib'),
        bad(authored(raw, encoded=z[:3] + z[-4:]), 'invalidZlib'),
        bad(authored(raw, encoded=z[:-1] + bytes([z[-1] ^ 1])), 'invalidZlib'),
        bad(authored(bytes([5, 1, 2, 3])), 'invalidFilter'),
        bad(authored(bytes([0, 1, 2])), 'scanlineSize'),
        good(rgb),
    ])
    add_case('unsupported-profiles', [
        unsupported(authored(bytes([0, 1]), color=3), 'indexedColor'),
        unsupported(authored(raw, interlace=1), 'interlaced'),
        unsupported(authored(bytes([0, 0, 1]), color=0, depth=16), 'bitDepth'),
        unsupported(authored(raw, extra=chunk(b'acTL', struct.pack('>II', 1, 0))), 'animation'),
        unsupported(authored(raw, extra=chunk(b'vpAg', b'unknown metadata')), 'unsupportedChunk'),
        good(rgba),
    ])
    false = SIGNATURE + struct.pack('>I', 0x7fffffff) + b'IHDR'
    add_case('false-signature', [bad(false, 'truncated'), noise(b'\x31' * 9), good(gray)])
    add_case('pillow-metadata', [good(pillow('RGB', (7, 3), 17, metadata=True))])
    inner = pillow('L', (2, 2), 9)
    outer = authored(b'\x00' + inner, width=len(inner), height=1, color=0,
                     encoded=zlib.compress(b'\x00' + inner, level=0))
    add_case('nested-signature', [good(outer)])
    at = outer.index(SIGNATURE, 8)
    cases['nested-signature']['candidates'].append({'offset': at, 'status': 'rejected', 'reason': 'overlappingCandidate'})
    large_pixels = b''.join(hashlib.sha256(struct.pack('>I', i)).digest() for i in range(1800))
    repeated = large_pixels + large_pixels[:20000]
    large = authored(b'\x00' + repeated, width=len(repeated), height=1, color=0)
    add_case('deflate-window', [good(large)])

    manifest = {'schema': 1, 'producer': 'Pillow PNG writer and Python standard library struct/zlib',
                'cases': cases}
    encoded = {name: base64.b64encode(zlib.compress(data, level=9)).decode() for name, data in sources.items()}
    dart = '// GENERATED by generate_png_carving_reference.py; original fixtures, MIT.\n'
    dart += "import 'dart:convert';\nimport 'dart:typed_data';\nimport 'package:archive/archive.dart' as codecs;\n\n"
    dart += 'const pngCarvingReferenceData = <String, String>{\n'
    for name, value in encoded.items():
        dart += f"  '{name}':\n"
        for i in range(0, len(value), 100):
            dart += f"      '{value[i:i+100]}'\n"
        dart += '      ,\n'
    dart += '};\n\n'
    dart += "Uint8List pngCarvingReferenceBytes(String name) =>\n    Uint8List.fromList(const codecs.ZLibDecoder().decodeBytes(\n      base64Decode(pngCarvingReferenceData[name]!),\n    ));\n\n"
    dart += "const pngCarvingReferenceManifestJson = r'''" + json.dumps(manifest, sort_keys=True, separators=(',', ':')) + "''';\n"
    files = {
        root / 'test/fixtures/archives/png-carving-reference-manifest.json': (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode(),
        root / 'test/support/png_carving_reference_data.dart': dart.encode(),
    }
    for path, content in files.items():
        if args.check:
            # Generated Dart may have been passed through dart format. Compare
            # fixture payloads/manifest, rather than cosmetic literal wrapping.
            if path.suffix == '.dart':
                current = path.read_text()
                for value in encoded.values():
                    compact = ''.join(line.strip().strip("',") for line in current.splitlines())
                    if value not in compact:
                        raise SystemExit(f'Fixture data differs: {path}')
                if json.dumps(manifest, sort_keys=True, separators=(',', ':')) not in current:
                    raise SystemExit(f'Fixture manifest differs: {path}')
            elif path.read_bytes() != content:
                raise SystemExit(f'Fixture differs: {path}')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    print(json.dumps({'cases': len(cases), 'sourceBytes': sum(len(s) for s in sources.values()),
                      'validImages': sum(c['status'] == 'recoverable' for row in cases.values() for c in row['candidates']),
                      'checked': args.check}))


if __name__ == '__main__':
    main()
