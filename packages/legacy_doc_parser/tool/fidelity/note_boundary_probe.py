#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Attribute note-table boundary changes across three native DOC round trips.

Requires installed LibreOffice, Dart, PyMuPDF, NumPy and an already built
independent Open XML SDK validator. No expected blank paragraphs are inferred
from converted output. Native-added paragraphs remain recorded differences.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from oracle import ROOT, _xml, digest
from run import command, office_convert, write_json
from schema import office_files, verify_report

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
SOURCE = ROOT / 'test/fixtures/fidelity/table-borders.docx'
KINDS = ('footnote', 'endnote')
# Literal authored note contents, independent of the parser and DOC bridge.
CONTROLS = {
    'plain': ('Note table follows', False, []),
    'empty': ('', False, []),
    'trailing-blank': ('Note table follows', False, ['']),
    'two-trailing-blanks': ('Note table follows', False, ['', '']),
    'table': ('Note table follows', True, []),
    'table-blank': ('Note table follows', True, ['']),
    'table-two-blanks': ('Note table follows', True, ['', '']),
    'table-text': ('Note table follows', True, ['TAIL']),
}


def expected_blocks(name):
    text, table, following = CONTROLS[name]
    blocks = [{'kind': 'p', 'text': text}]
    if table:
        blocks.append({'kind': 'tbl', 'cells': [[
            {'kind': 'p', 'text': 'Unbordered note table'}]]})
    return blocks + [{'kind': 'p', 'text': value} for value in following]


def authored_control(path, kind, name):
    """Modify only the note in the retained independently authored corpus file."""
    if kind not in KINDS or name not in CONTROLS:
        raise ValueError('Unknown independently authored note control')
    if kind == 'footnote' and name == 'table':
        # The real table-borders regression is kept byte-exact.
        with path.open('xb') as output:
            output.write(SOURCE.read_bytes())
        return
    with zipfile.ZipFile(SOURCE) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    root = ET.fromstring(parts['word/footnotes.xml'])
    note = root.find('{' + W + '}footnote')
    text, table, following = CONTROLS[name]
    if not text:
        paragraph = note.find('{' + W + '}p')
        for run in list(paragraph):
            if run.find('{' + W + '}footnoteRef') is None:
                paragraph.remove(run)
    if not table:
        note.remove(note.find('{' + W + '}tbl'))
    for value in following:
        paragraph = ET.SubElement(note, '{' + W + '}p')
        if value:
            ET.SubElement(ET.SubElement(paragraph, '{' + W + '}r'),
                          '{' + W + '}t').text = value
    parts['word/footnotes.xml'] = ET.tostring(root, encoding='UTF-8', xml_declaration=True)
    if kind == 'endnote':
        # This retained package has no binary media. Changing the literal note
        # names also changes the document reference, part path, content type
        # and relationship type/target together.
        parts = {name.replace('footnotes', 'endnotes'): data.replace(b'footnote', b'endnote')
                 for name, data in parts.items()}
    with zipfile.ZipFile(path, 'x', zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(parts.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(info, data)


def canonical_block(block):
    if block['kind'] == 'p':
        return {'kind': 'p', 'text': block['text']}
    if block['kind'] == 'tbl':
        return {'kind': 'tbl', 'cells': [[canonical_block(child) for child in cell]
                                       for cell in block['cells']]}
    raise ValueError('Unexpected note block')


def xml_block(element):
    if element.tag == '{' + W + '}p':
        return {'kind': 'p', 'text': ''.join(text.text or '' for text in element.iter('{' + W + '}t'))}
    if element.tag == '{' + W + '}tbl':
        return {'kind': 'tbl', 'cells': [
            [xml_block(child) for child in cell if child.tag in ('{' + W + '}p', '{' + W + '}tbl')]
            for row in element.findall('{' + W + '}tr')
            for cell in row.findall('{' + W + '}tc')]}
    return {'kind': element.tag}


def note_snapshot(path, kind):
    part = f'word/{kind}s.xml'
    with zipfile.ZipFile(path) as package:
        if part not in package.namelist():
            return {'sha256': digest(path), 'notes': [], 'alternateContent': []}
        root, alternatives = _xml(package.read(part))
    notes = []
    for note in root.findall('{' + W + '}' + kind):
        if note.get('{' + W + '}type', 'normal') != 'normal':
            continue
        notes.append({
            'id': note.get('{' + W + '}id'),
            'blocks': [xml_block(child) for child in note],
            'markerCount': len(list(note.iter('{' + W + '}' + kind + 'Ref'))),
            'textboxCount': len(list(note.iter('{' + W + '}txbxContent'))),
        })
    return {'sha256': digest(path), 'notes': notes, 'alternateContent': alternatives}


def content(snapshot):
    return [note['blocks'] for note in snapshot['notes']]


def writer_preserves_blocks(parsed, emitted):
    """A missing story and a missing empty paragraph must never pass together."""
    stories = parsed.get('stories', [])
    notes = emitted.get('notes', [])
    return (len(stories) == len(notes) == 1
            and bool(stories[0]['blocks'])
            and notes[0]['markerCount'] == 1
            and notes[0]['textboxCount'] == 0
            and [[canonical_block(block) for block in story['blocks']] for story in stories]
            == content(emitted))


def block_changes(before, after):
    if content(before) == content(after):
        return []
    return [{'before': content(before), 'after': content(after)}]


def native_convert(office, source, destination, kind):
    output = office_convert(office, source, destination, kind)
    # Only this invocation's completed, reproducible profile cache is removed.
    # Keep exact Office files, PDFs and conversion.log for independent review.
    shutil.rmtree(destination / 'profile')
    return output


def render(office, source, destination, dpi):
    import fitz
    pdf = native_convert(office, source, destination, 'pdf')
    pages = []
    with fitz.open(pdf) as document:
        for page in document:
            pixmap = page.get_pixmap(matrix=fitz.Matrix(dpi / 72, dpi / 72),
                                      colorspace=fitz.csRGB, alpha=False)
            words = [[*word[:4], word[4]] for word in page.get_text('words')]
            pages.append({'sizePoints': list(page.rect)[2:], 'words': words,
                          'noteMarkers': [word for word in words if 'Note' in word[4]],
                          'rgbDimensions': [pixmap.width, pixmap.height],
                          'rgbSha256': hashlib.sha256(pixmap.samples).hexdigest()})
    return {'pdfPath': str(pdf), 'pdfSha256': digest(pdf), 'dpi': dpi, 'pages': pages}


def compare_renders(before, after):
    import fitz
    import numpy as np
    pages = []
    if len(before['pages']) != len(after['pages']):
        return {'exact': False, 'pageCountChanged': True, 'pages': []}
    with fitz.open(before['pdfPath']) as left, fitz.open(after['pdfPath']) as right:
        for index, (a, b) in enumerate(zip(before['pages'], after['pages'])):
            same_words = [word[4] for word in a['words']] == [word[4] for word in b['words']]
            drift = (max((abs(x - y) for aw, bw in zip(a['words'], b['words'])
                          for x, y in zip(aw[:4], bw[:4])), default=0)
                     if same_words else None)
            dimensions_match = a['rgbDimensions'] == b['rgbDimensions']
            changed = maximum = None
            if dimensions_match:
                matrix = fitz.Matrix(before['dpi'] / 72, before['dpi'] / 72)
                aa = np.frombuffer(left[index].get_pixmap(matrix=matrix, colorspace=fitz.csRGB,
                                                         alpha=False).samples, dtype=np.uint8)
                bb = np.frombuffer(right[index].get_pixmap(matrix=matrix, colorspace=fitz.csRGB,
                                                          alpha=False).samples, dtype=np.uint8)
                delta = np.abs(aa.astype(np.int16) - bb.astype(np.int16)).reshape(-1, 3)
                changed, maximum = int(np.any(delta != 0, axis=1).sum()), int(delta.max(initial=0))
            pages.append({'textMatches': same_words, 'maximumWordRectangleDriftPoints': drift,
                          'pageSizeMatches': a['sizePoints'] == b['sizePoints'],
                          'changedRgbPixels': changed, 'maximumChannelDifference': maximum})
    return {'exact': all(page['textMatches'] and page['maximumWordRectangleDriftPoints'] == 0
                         and page['pageSizeMatches'] and page['changedRgbPixels'] == 0 for page in pages),
            'pageCountChanged': False, 'pages': pages}


def relative_render(value, output):
    return {**value, 'pdfPath': str(Path(value['pdfPath']).relative_to(output))}


def measure_case(case_id, args, executable, output):
    kind, name = case_id.split('-', 1)
    base = output / case_id
    base.mkdir()
    source = base / 'authored.docx'
    authored_control(source, kind, name)
    authored = note_snapshot(source, kind)
    if content(authored) != [expected_blocks(name)]:
        raise ValueError(f'{case_id}: authored control disagrees with literal expectation')
    record = {'id': case_id, 'expectedBlocks': expected_blocks(name), 'authored': authored,
              'cycles': [], 'errors': []}
    try:
        original_render = render(args.office, source, base / 'render-authored', args.dpi)
        record['authoredRender'] = relative_render(original_render, output)
        current, current_snapshot, previous_render = source, authored, original_render
        first_render = None
        for index in range(args.cycles + 1):
            stage = base / f'import-{index:02}'
            stage.mkdir()
            binary = native_convert(args.office, current, stage / 'bridge', 'doc')
            binary_hash = digest(binary)
            converted = stage / 'converted.docx'
            parsed = json.loads(command([executable, binary, converted]))
            write_json(stage / 'raw-notes.json', parsed)
            emitted = note_snapshot(converted, kind)
            binary_render = render(args.office, binary, stage / 'render-binary', args.dpi)
            converted_render = render(args.office, converted, stage / 'render-converted', args.dpi)
            first_render = first_render or converted_render
            cycle = {'index': index, 'inputSha256': digest(current), 'binarySha256': binary_hash,
                     'inputNotes': current_snapshot, 'parsed': parsed, 'emitted': emitted,
                     'writerPreservesSourceBlocks': writer_preserves_blocks(parsed, emitted),
                     'nativeBridgeBlockChanges': block_changes(current_snapshot, emitted),
                     'bridgeRender': compare_renders(previous_render, binary_render),
                     'parserRender': compare_renders(binary_render, converted_render),
                     'fromAuthoredRender': compare_renders(original_render, converted_render),
                     'fromFirstImportRender': compare_renders(first_render, converted_render),
                     'binaryRender': relative_render(binary_render, output),
                     'convertedRender': relative_render(converted_render, output)}
            if index == 0:
                native = native_convert(args.office, binary, stage / 'native-docx', 'docx')
                cycle['nativeProjection'] = note_snapshot(native, kind)
            cycle['sourceUnchanged'] = digest(current) == current_snapshot['sha256']
            cycle['binaryUnchanged'] = digest(binary) == binary_hash
            record['cycles'].append(cycle)
            if not all(cycle[key] for key in ('writerPreservesSourceBlocks', 'sourceUnchanged', 'binaryUnchanged')):
                raise ValueError(f'{case_id}/{index}: writer or input-integrity contract failed')
            write_json(base / 'result.json', record)
            current, current_snapshot, previous_render = converted, emitted, converted_render
        record['completed'] = True
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        record['errors'].append(f'{type(error).__name__}: {error}')
        record['completed'] = False
    write_json(base / 'result.json', record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--dotnet', default='dotnet')
    parser.add_argument('--validator', type=Path, required=True)
    parser.add_argument('--cycles', type=int, default=3, choices=range(1, 4))
    parser.add_argument('--dpi', type=int, default=144, choices=(96, 144))
    parser.add_argument('--workers', type=int, default=2, choices=(1, 2))
    all_ids = [f'{kind}-{name}' for kind in KINDS for name in CONTROLS]
    parser.add_argument('--case', action='append', choices=all_ids)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    cases = args.case or all_ids
    if len(set(cases)) != len(cases):
        raise ValueError('Duplicate case identifiers')
    sources = sorted([*ROOT.joinpath('lib').rglob('*.dart'), ROOT / 'pubspec.lock',
                      SOURCE, Path(__file__).resolve(), ROOT / 'tool/fidelity/note_boundary_inspect.dart',
                      ROOT / 'tool/fidelity/oracle.py', ROOT / 'tool/fidelity/run.py',
                      ROOT / 'tool/fidelity/schema.py'])
    hashes = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    import fitz
    import numpy as np
    report = {'schema': 'legacy-doc-parser/note-boundary-probe', 'version': 1,
              'parserCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
              'parserWorktreeDirty': bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip()),
              'sourceFiles': hashes, 'authoredSourceSha256': digest(SOURCE),
              'renderer': command([args.office, '--version']).strip(),
              'compiler': command([args.dart, '--version']).strip(),
              'pdfInspectorVersion': fitz.VersionBind, 'numpyVersion': np.__version__,
              'validatorSha256': digest(args.validator),
              'requestedCases': cases, 'roundtripCycles': args.cycles,
              'method': 'Initial independent DOCX -> native DOC -> parser DOCX, then successive native DOC/parser cycles. '
                        'Raw note PLC ranges and all intentional blanks are retained. '
                        'Writer preservation is gated separately from native bridge and renderer differences.',
              'cases': [], 'errors': []}
    executable = output / 'inspect-notes'
    try:
        command([args.dart, 'compile', 'exe', 'tool/fidelity/note_boundary_inspect.dart', '-o', executable], cwd=ROOT)
        report['inspectorSha256'] = digest(executable)
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(measure_case, case, args, executable, output): case for case in cases}
            for future in as_completed(futures):
                case = future.result()
                report['cases'].append(case)
                report['cases'].sort(key=lambda item: cases.index(item['id']))
                report['errors'].extend(f'{case["id"]}: {error}' for error in case['errors'])
                write_json(output / 'report.json', report)
                print(json.dumps({'case': case['id'], 'complete': case['completed'],
                                  'cycles': len(case['cycles']), 'errors': case['errors']}), flush=True)
        expected = office_files(output)
        validation = subprocess.run([str(args.dotnet), str(args.validator), str(output), str(output / 'schema.json')],
                                    capture_output=True, text=True, timeout=120)
        (output / 'schema.log').write_text(validation.stdout + validation.stderr)
        report['sdk'] = verify_report(json.loads((output / 'schema.json').read_text()), expected, validation.returncode)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        report['errors'].append(f'{type(error).__name__}: {error}')
    finally:
        report['sourceUnchanged'] = hashes == {str(path.relative_to(ROOT)): digest(path) for path in sources}
        if not report['sourceUnchanged']:
            report['errors'].append('Probe source changed during measurement')
        report['writerContractPassed'] = (not report['errors'] and len(report['cases']) == len(cases)
                                          and all(case['completed'] and len(case['cycles']) == args.cycles + 1
                                                  for case in report['cases']))
        report['allNativeComparisonsExact'] = (report['writerContractPassed']
            and all(not cycle['nativeBridgeBlockChanges']
                    and all(cycle[name]['exact'] for name in ('bridgeRender', 'parserRender',
                                                             'fromAuthoredRender', 'fromFirstImportRender'))
                    for case in report['cases'] for cycle in case['cycles']))
        report['artifacts'] = {str(path.relative_to(output)): digest(path) for path in sorted(output.rglob('*'))
                               if path.is_file() and path.suffix in ('.doc', '.docx', '.pdf')}
        write_json(output / 'report.json', report)
    print(json.dumps({'writerContractPassed': report['writerContractPassed'],
                      'allNativeComparisonsExact': report['allNativeComparisonsExact'],
                      'cases': len(report['cases']), 'errors': report['errors']}, indent=2))
    return int(not report['writerContractPassed'])


if __name__ == '__main__':
    raise SystemExit(main())
