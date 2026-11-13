#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify retained OLE visibility evidence, without opening an object handler.

Requires Pillow and PyMuPDF to independently decode archived PNG/PDF pixels.
Checks remain active under python -O. No archive member is extracted to disk.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile
import xml.etree.ElementTree as ET
import zipfile

import fitz
from PIL import Image

RUNTIME = 'd08627583500063f6cf67a1a1d756dae3f9594f4'
TREE = '4281243b63a2bb07655f15bfe5fe1a5e50a8dfcd'
SOURCE = '935edaa1bcd2776ebe319e238301c373bed7760c2761eb1a24d10f12579ef29f'
PAYLOAD = '084937f7a5a65cc3ceeb6c16171420643f091d93c70935049c260f36f51cbc0d'
PNG = '37db6492bd5cefedb386946d7c929c4ccacad0fdadbfaf47f53dca32df3a88fe'
PIXELS = '514ef59855e29c7da8e8e51f2a990f95e5bfb768436da12e49e0d7b70e406780'
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
O = '{urn:schemas-microsoft-com:office:office}'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def package(data):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP member')
        return {name: archive.read(name) for name in names}


def rgb(data):
    with Image.open(io.BytesIO(data)) as image:
        return list(image.size), image.convert('RGB').tobytes()


def verify(directory):
    manifest = json.loads((directory / 'artifacts.manifest.json').read_bytes())
    metadata = manifest['archive']
    require(metadata['path'] == 'artifacts.tar.xz', 'Unexpected archive path')
    archive_data = (directory / metadata['path']).read_bytes()
    require(len(archive_data) == metadata['bytes'] and sha(archive_data) == metadata['sha256'],
            'Archive bytes differ')
    expected = {entry['path']: entry for entry in manifest['files']}
    require(len(expected) == len(manifest['files']), 'Duplicate manifest path')
    records = {}
    with tarfile.open(fileobj=io.BytesIO(archive_data), mode='r:xz') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            require(member.isfile() and not path.is_absolute() and '..' not in path.parts,
                    'Unsafe or non-file member')
            require(member.name in expected and member.name not in records,
                    'Unexpected or duplicate archive member')
            raw = archive.extractfile(member).read()
            entry = expected[member.name]
            require(len(raw) == entry['bytes'] and sha(raw) == entry['sha256'],
                    'Artifact bytes differ: ' + member.name)
            records[member.name] = raw
    require(records.keys() == expected.keys(), 'Missing archive member')
    require(len(records) == manifest['fileCount'] == 110, 'File count differs')
    require(sum(map(len, records.values())) == manifest['totalBytes'], 'Total bytes differ')

    for name in ['receipt.json', 'schema-report.json']:
        require((directory / name).read_bytes() == records['final/' + name],
                'Displayed report differs: ' + name)
    receipt = json.loads(records['final/receipt.json'])
    require(receipt['sourceCommit'] == manifest['runtimeCommit'] == RUNTIME
            and receipt['sourceTree'] == TREE, 'Runtime identity differs')
    require(receipt['status'] == 'completed' and receipt['allRuntimeInputsUnchanged'] is True,
            'Runtime acceptance incomplete')
    require(receipt['sourceFilesBefore'] == receipt['sourceFilesAfter']
            and len(receipt['sourceFilesBefore']) == 909, 'Runtime input inventory differs')
    require(receipt['nativeHandlerActivationAttempted'] is False, 'Handler scope differs')
    for name, raw in records.items():
        if name.startswith('runtime/'):
            require(receipt['sourceFilesBefore'][name.removeprefix('runtime/')] == sha(raw),
                    'Captured runtime bytes differ: ' + name)
    require(sha(records['scripts/measure.py']) == receipt['measurementScriptSha256'],
            'Measurement script differs')
    require(sha(records['runtime/tool/fidelity/run.py']) == receipt['nativeHelperSha256'],
            'Native helper differs')
    require(sha(records['runtime/tool/office-validation/Program.cs'])
            == receipt['validatorSourceSha256'], 'Validator source differs')
    require([stage['name'] for stage in receipt['commands']]
            == ['generate-media-review-fixtures', 'independent-schema'], 'Stage inventory differs')
    workspace = '/workspace/scratch/c1ca2a1344e9/'
    output = workspace + 'root-gap-probes/ole/d086-native/'
    expected_commands = [
        [workspace + 'toolchains/dart-3.13.7/dart-sdk/bin/dart', 'run',
         'tool/fidelity/media_review_fixture.dart', output + 'schema/fixtures'],
        [workspace + 'toolchains/dotnet-8.0.428/dotnet',
         workspace + 'parser-schema-final/validator/OfficeValidation.dll',
         output + 'schema', output + 'schema-report.json'],
    ]
    require([stage['args'] for stage in receipt['commands']] == expected_commands,
            'Stage command differs from the measured generator or SDK invocation')
    for stage in receipt['commands']:
        require(stage['exitCode'] == 0
                and sha(records['final/' + stage['name'] + '.log']) == stage['logSha256'],
                'Stage failed or log differs')
    require(b'+36: All tests passed!' in records['logs/focused-tests.log'], 'Dart checks missing')
    require(b'No issues found!' in records['logs/analysis.log'], 'Analysis failed')
    independent = json.loads(records['logs/independent-story-review.log'])
    require(independent == {'perPartRelationships': 3, 'uniqueShapes': 3,
            'generatedImageParts': 1, 'placeholders': 3, 'sourceImageCount': None,
            'payloadBytesUnchanged': True, 'hiddenDualRevisionsRetained': True},
            'Independent story review differs')

    source = records['final/schema/fixtures/embedded-object-inserted.doc']
    require(sha(source) == receipt['originalSourceSha256'] == SOURCE, 'Source fixture differs')
    original_bytes = records['final/schema/fixtures/embedded-object-inserted.docx']
    require(sha(original_bytes) == receipt['convertedDocxSha256'], 'Converted package differs')
    original = package(original_bytes)
    require(sha(original['word/embeddings/oleObject1.bin'])
            == receipt['embeddedPayloadSha256'] == PAYLOAD, 'Original payload differs')
    image = original['word/media/embedded-object-placeholder.png']
    require(image == records['final/reference-placeholder.png']
            == records['runtime/test/fixtures/word_native/generated-ole-placeholder.png']
            == records['image-recipe/embedded-object-placeholder.png']
            and sha(image) == PNG, 'Placeholder asset differs')
    size, pixels = rgb(image)
    require(size == [288, 144] and sha(pixels) == receipt['reviewedPixelSha256'] == PIXELS,
            'Reviewed pixels differ')
    require(len(receipt['projections']) == 2, 'Projection count differs')
    for projection, retain in zip(receipt['projections'], [True, False]):
        path = 'schema/' + ('accepted' if retain else 'rejected') + '.docx'
        require(projection['path'] == path and projection['insertionRetained'] is retain,
                'Projection identity differs')
        raw = records['final/' + path]
        require(sha(raw) == projection['sha256'], 'Projection hash differs')
        projected = package(raw)
        require(projected.keys() == original.keys(), 'Projection package inventory differs')
        changed = [name for name in original if original[name] != projected[name]]
        require(changed == projection['changedMembers'] == ['word/document.xml'],
                'Projection changed non-document members')
        xml = ET.fromstring(projected['word/document.xml'])
        require(not xml.findall('.//' + W + 'ins'), 'Projection retains insertion markup')
        require(len(xml.findall('.//' + O + 'OLEObject')) == int(retain),
                'Projection object presence differs')

    schema_bytes = records['final/schema-report.json']
    require(sha(schema_bytes) == receipt['schema']['reportSha256'], 'Schema report differs')
    schema = json.loads(schema_bytes)
    require(schema['Files'] == receipt['schema']['files'] == 26
            and schema['Failures'] == receipt['schema']['failures'] == 0, 'Schema result differs')
    checked = {}
    for report in schema['Reports']:
        require('/d086-native/schema/' in report['File'], 'Unexpected schema output path')
        path = 'final/schema/' + report['File'].split('/d086-native/schema/', 1)[1]
        require(path not in checked and report['Errors'] == [], 'Repeated or failed schema result')
        require(sha(records[path]) == report['Sha256'], 'Schema input bytes differ')
        checked[path] = report
    require(checked.keys() == {name for name in records
            if name.startswith('final/schema/') and name.endswith('.docx')},
            'Schema did not cover every retained DOCX')

    require(receipt['native'].keys() == {'reviewed', 'accepted', 'rejected'}, 'Native cases differ')
    for name, item in receipt['native'].items():
        stem = 'embedded-object-inserted' if name == 'reviewed' else name
        raw = records['final/native-' + name + '/' + stem + '.pdf']
        require(sha(raw) == item['pdfSha256'], 'Native PDF differs')
        require(item['sourcePackageUnchanged'] is True, 'Native input mutated')
        with fitz.open(stream=raw, filetype='pdf') as pdf:
            require(len(pdf) == item['pageCount'] == 1, 'Native page count differs')
            page = pdf[0]
            require(page.get_text() == item['pageText'] == 'X\n', 'Native body text differs')
            images = page.get_images(full=True)
            require(len(images) == len(item['images']) == int(name != 'rejected'),
                    'Native object visibility differs')
            for native_image, saved in zip(images, item['images']):
                extracted = pdf.extract_image(native_image[0])
                actual_size, actual_pixels = rgb(extracted['image'])
                require(actual_size == saved['size'] == size
                        and actual_pixels == pixels
                        and sha(actual_pixels) == saved['pixelSha256']
                        and saved['matchesReviewedPixels'] is True, 'Native pixels differ')
                require([list(rect) for rect in page.get_image_rects(native_image[0])]
                        == saved['rectangles'], 'Native image geometry differs')
                saved_image = records['final/native-' + name + '/image-'
                                      + str(native_image[0]) + '.' + extracted['ext']]
                require(rgb(saved_image) == (actual_size, actual_pixels),
                        'Extracted image differs from native PDF')
    print('Verified 110 exact artifacts, 26 schema outputs and 3 native visibility cases; '
          'original OLE bytes and rendered placeholder pixels match.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parent)
    verify(parser.parse_args().directory)
