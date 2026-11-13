#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check PICMID integer-twip scaling against independently patched native DOC.

Only the eight goal/scale bytes in one hash-pinned native source are changed.
The expected dimensions below are authored constants, never obtained from the
Dart parser or a native DOCX. Each import is measured separately. The probe
does not invent native-export crop adjustments absent from the binary source.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

from run import command, office_convert

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'test/fixtures/fidelity/image-appearance/binary/inline-horizontal.doc'
SOURCE_SHA256 = 'd7e50ad0b14d4b7d54e74c2ff86e7f9c449ddf8f1aa432f679b1d2e346ecc084'
WP = '{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}'
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
CASES = {
    # goal width/height; scale in 0.1%; expected final integer twips.
    'integral': ((1200, 600), (1200, 1200), (1440, 720)),
    'below-half': ((1001, 1001), (1499, 499), (1500, 499)),
    'half': ((1001, 1003), (1500, 500), (1501, 501)),
    'above-half': ((1001, 1001), (1501, 501), (1502, 501)),
    'one-thousandth': ((1001, 1001), (1001, 1999), (1002, 2000)),
    'retained-emf-ratio': ((9001, 5401), (960, 960), (8640, 5184)),
    'retained-wmf-ratio': ((9000, 5400), (960, 960), (8640, 5184)),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def stream_offsets(data, name):
    """Independently map a bounded v3 CFB stream to physical byte offsets."""
    def u16(at):
        return struct.unpack_from('<H', data, at)[0]

    def u32(at):
        return struct.unpack_from('<I', data, at)[0]

    require(data[:8] == bytes.fromhex('d0cf11e0a1b11ae1'), 'Not CFB.')
    require(u16(26) == 3 and u16(30) == 9 and u16(32) == 6,
            'Expected the pinned v3 CFB sector layout.')
    require(u32(56) == 4096 and u32(72) == 0, 'Unexpected CFB allocation layout.')

    def sector(index):
        at = (index + 1) * 512
        require(0 <= at <= len(data) - 512, 'Sector exceeds source.')
        return list(range(at, at + 512))

    def read(offsets):
        return bytes(data[index] for index in offsets)

    fat = []
    for index in struct.unpack_from('<109I', data, 76):
        if index < 0xfffffffa:
            fat.extend(struct.unpack('<128I', read(sector(index))))

    def chain(start, allocation, reader):
        result, seen = [], set()
        while start < 0xfffffffa:
            require(start not in seen and start < len(allocation), 'Invalid CFB chain.')
            seen.add(start)
            result.extend(reader(start))
            start = allocation[start]
        return result

    directory = read(chain(u32(48), fat, sector))
    entries = {}
    for at in range(0, len(directory), 128):
        entry = directory[at:at + 128]
        size = struct.unpack_from('<H', entry, 64)[0]
        if not size:
            continue
        require(2 <= size <= 64 and size % 2 == 0, 'Invalid CFB name.')
        key = entry[:size - 2].decode('utf-16le')
        require(key not in entries, 'Duplicate CFB directory name.')
        entries[key] = struct.unpack_from('<IQ', entry, 116)
    start, size = entries[name]
    if size >= 4096:
        offsets = chain(start, fat, sector)
    else:
        root_start, root_size = entries['Root Entry']
        mini = chain(root_start, fat, sector)[:root_size]
        raw_fat = read(chain(u32(60), fat, sector))
        mini_fat = struct.unpack('<%dI' % (len(raw_fat) // 4), raw_fat)

        def mini_sector(index):
            require(index * 64 <= len(mini) - 64, 'Mini-sector exceeds source.')
            return mini[index * 64:index * 64 + 64]

        offsets = chain(start, mini_fat, mini_sector)
    require(size <= len(offsets), 'Truncated CFB stream.')
    return offsets[:size]


def author(source, goals, scales):
    require(digest_bytes(source) == SOURCE_SHA256, 'Pinned native source changed.')
    offsets = stream_offsets(source, 'Data')
    raw = bytes(source[index] for index in offsets)
    require(len(raw) == 377 and struct.unpack_from('<IHH', raw) == (377, 68, 100),
            'Pinned PICF header changed.')
    require(raw[36:44] == bytes(8), 'Reserved PICMID fields are not zero.')
    replacement = struct.pack('<hhHH', *goals, *scales)
    result = bytearray(source)
    for index, value in zip(offsets[28:36], replacement):
        result[index] = value
    changed = {i for i, (a, b) in enumerate(zip(source, result)) if a != b}
    require(changed <= set(offsets[28:36]), 'Changed bytes outside PICMID goals/scales.')
    return bytes(result), {'goalsTwips': list(goals), 'scaleTenthsPercent': list(scales),
                           'dataStreamSize': len(raw), 'picfOffset': 0,
                           'physicalFieldOffsets': offsets[28:36],
                           'changedPhysicalOffsets': sorted(changed),
                           'picfHeaderHex': bytes(result[i] for i in offsets[:68]).hex()}


def picture_xml(path):
    with zipfile.ZipFile(path) as package:
        root = ET.fromstring(package.read('word/document.xml'))
        images = {name: digest_bytes(package.read(name)) for name in package.namelist()
                  if name.startswith('word/media/')}
    extents = root.findall('.//' + WP + 'extent')
    require(len(extents) == 1, 'Expected one inline image extent.')
    crop = root.find('.//' + A + 'srcRect')
    return {'extentEmu': [int(extents[0].attrib[x]) for x in ('cx', 'cy')],
            'crop': None if crop is None else crop.attrib, 'imagesSha256': images}


def measure_pdf(path):
    import fitz
    with fitz.open(path) as document:
        require(len(document) == 1, 'Control did not render on one page.')
        images = document[0].get_image_info()
        require(len(images) == 1, 'Control did not render one image.')
        box = list(images[0]['bbox'])
        return {'pdfSha256': digest_bytes(path.read_bytes()), 'imageBoundsPoints': box,
                'imageSizePoints': [box[2] - box[0], box[3] - box[1]]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True, type=Path)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    authored = output / 'binary'
    authored.mkdir()
    source = SOURCE.read_bytes()
    report = {'schema': 'legacy-doc-parser/picture-scaling', 'version': 1,
              'sourcePath': str(SOURCE.relative_to(ROOT)), 'sourceSha256': SOURCE_SHA256,
              'parserCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
              'parserWorktreeDirty': bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip()),
              'officeVersion': command([args.office, '--version']).strip(),
              'scope': 'Integer-twip PICMID scaling only; no renderer-only crop compensation.',
              'cases': {}, 'errors': []}
    for name, (goals, scales, expected) in CASES.items():
        payload, fields = author(source, goals, scales)
        (authored / (name + '.doc')).write_bytes(payload)
        report['cases'][name] = {'sourceSha256': digest_bytes(payload), 'sourceFields': fields,
                                 'expectedTwips': list(expected)}
    converted = output / 'converted'
    command([args.dart, 'run', ROOT / 'tool/fidelity/picture_sizing_probe.dart', authored, converted], cwd=ROOT)
    models = json.loads((converted / 'model.json').read_text())
    for name, (_, _, expected) in CASES.items():
        case = report['cases'][name]
        try:
            binary = authored / (name + '.doc')
            native = office_convert(args.office, binary, output / 'native-docx' / name, 'docx')
            case['native'] = picture_xml(native)
            case['parser'] = picture_xml(converted / (name + '.docx'))
            case['parserModel'] = models[name]
            case['expectedEmu'] = [value * 635 for value in expected]
            for kind, path in [('binary', binary), ('parser', converted / (name + '.docx'))]:
                pdf = office_convert(args.office, path, output / 'render' / name / kind, 'pdf')
                case[kind + 'Render'] = measure_pdf(pdf)
            case['nativeMatchesAuthoredTwips'] = case['native']['extentEmu'] == case['expectedEmu']
            case['parserMatchesAuthoredTwips'] = case['parser']['extentEmu'] == case['expectedEmu']
            case['parserCropUnchanged'] = models[name]['cropFixed16'] == [0, 0, 0, 0]
            case['maximumImageSizeDifferencePoints'] = max(abs(a - b) for a, b in zip(
                case['binaryRender']['imageSizePoints'], case['parserRender']['imageSizePoints']))
            case['parserMaximumSizeDriftFromAuthoredPoints'] = max(abs(a - b / 20) for a, b in zip(
                case['parserRender']['imageSizePoints'], expected))
            case['sourceUnchanged'] = digest_bytes(binary.read_bytes()) == case['sourceSha256']
            # The native importer insets even the integral control's image by
            # 0.05 pt on every side, then exports compensating negative crop.
            # Retain that measured difference separately from this probe's
            # exact PICMID frame-size contract; it is not source cropping.
            case['checksPass'] = (case['nativeMatchesAuthoredTwips'] and case['parserMatchesAuthoredTwips']
                                  and case['parserCropUnchanged'] and case['sourceUnchanged']
                                  and case['parserMaximumSizeDriftFromAuthoredPoints'] <= 0.011)
            if not case['checksPass']:
                report['errors'].append(name + ': authored sizing check differs')
            print(name + ': native=' + str(case['nativeMatchesAuthoredTwips'])
                  + ', parser=' + str(case['parserMatchesAuthoredTwips']), flush=True)
        except (ValueError, OSError, RuntimeError) as error:
            case['error'] = str(error)
            report['errors'].append(name + ': ' + str(error))
        finally:
            (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return int(bool(report['errors']))


if __name__ == '__main__':
    raise SystemExit(main())
