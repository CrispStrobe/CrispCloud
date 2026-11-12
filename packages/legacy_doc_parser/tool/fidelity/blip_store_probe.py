#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reimport the retained constant-one BStore failure through three DOC cycles."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

from run import command, digest, office_convert, render, render_comparison

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'test/fixtures/word_native/word16-page-origin-lo-blip-count.doc'


def image_hashes(path):
    with zipfile.ZipFile(path) as package:
        return sorted(hashlib.sha256(package.read(name)).hexdigest()
                      for name in package.namelist()
                      if name.startswith('word/media/'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True, type=Path)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    original_hash = digest(SOURCE)
    report = {'sourceSha256': original_hash,
              'officeVersion': command([args.office, '--version']).strip(),
              'implementationBaseCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
              'workingTreeChanges': command(['git', 'status', '--short'], cwd=ROOT).splitlines(),
              'scope': 'Successful bounded reimport and image retention; rendering differences remain explicit.',
              'cycles': []}
    previous = None
    first_images = None
    for index in range(4):
        stage = output / f'cycle-{index:02}'
        stage.mkdir()
        if previous is None:
            binary = stage / 'source.doc'
            shutil.copyfile(SOURCE, binary)
        else:
            binary = office_convert(args.office, previous, stage / 'native-doc', 'doc')
        before = digest(binary)
        converted = stage / 'converted.docx'
        result = json.loads(command([args.dart, 'run', ROOT / 'tool/fidelity/convert.dart',
                                     binary, converted], cwd=ROOT))
        assert result['counts']['images'] == 2
        assert result['counts']['drawingReferences'] == 2
        hashes = image_hashes(converted)
        if first_images is None:
            first_images = hashes
        assert hashes == first_images
        binary_render = render(args.office, binary, stage / 'binary-render', 72)
        converted_render = render(args.office, converted, stage / 'converted-render', 72)
        cycle = {'index': index, 'binarySha256': before,
                 'convertedSha256': digest(converted), 'conversion': result,
                 'imageSha256': hashes,
                 'binaryRender': binary_render, 'convertedRender': converted_render,
                 'renderComparison': render_comparison(binary_render, converted_render),
                 'binaryUnchanged': before == digest(binary)}
        assert cycle['binaryUnchanged']
        report['cycles'].append(cycle)
        print(f'cycle {index}: two images and two drawing references retained', flush=True)
        previous = converted
    report['sourceUnchanged'] = original_hash == digest(SOURCE)
    assert report['sourceUnchanged']
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
