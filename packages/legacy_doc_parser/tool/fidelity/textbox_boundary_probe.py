#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check textbox separators against independently authored native controls."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess
from xml.sax.saxutils import escape
import zipfile

from oracle import ROOT, _xml, digest
from run import command, office_convert, parser_convert, render, render_comparison

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
CONTROLS = {
    'content': ['ALPHA'],
    'empty': [''],
    'leading-blank': ['', 'ALPHA'],
    'interior-blank': ['ALPHA', '', 'BETA'],
    'trailing-blank': ['ALPHA', ''],
    'two-trailing-blanks': ['ALPHA', '', ''],
    'two-content-paragraphs': ['ALPHA', 'BETA'],
}
WORD14_SHA = 'cab742e55b62e7a638ada283e877144a574e0412032ac5d797c1eb8cfedcfb9a'


def authored_control(path, paragraphs, header=False):
    """Write literal OOXML without using parser model or conversion code."""
    namespaces = (f'xmlns:w="{W}" xmlns:r="{REL}" '
                  'xmlns:v="urn:schemas-microsoft-com:vml" '
                  'xmlns:w10="urn:schemas-microsoft-com:office:word"')
    font = '<w:rFonts w:ascii="Liberation Serif" w:hAnsi="Liberation Serif"/><w:sz w:val="24"/>'
    content = ''.join(
        '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
        f'<w:rPr>{font}</w:rPr></w:pPr>'
        + (f'<w:r><w:rPr>{font}</w:rPr><w:t>{escape(text)}</w:t></w:r>' if text else '')
        + '</w:p>' for text in paragraphs)
    box = ('<w:p><w:r><w:pict><v:rect id="BoundaryControl" stroked="t" strokeweight="0.75pt" '
           'fillcolor="#FFFFFF" style="position:absolute;margin-left:72pt;margin-top:72pt;'
           'width:144pt;height:22pt;mso-position-horizontal-relative:page;'
           'mso-position-vertical-relative:page">'
           '<v:textbox inset="0,0,0,0" style="mso-fit-shape-to-text:t">'
           f'<w:txbxContent>{content}</w:txbxContent></v:textbox>'
           '<w10:wrap type="none"/></v:rect></w:pict></w:r></w:p>')
    section = ('<w:sectPr>' + ('<w:headerReference w:type="default" r:id="header1"/>' if header else '')
               + '<w:pgSz w:w="12240" w:h="15840"/>'
               '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
               'w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>')
    document = (f'<w:document {namespaces}><w:body>'
                + ('<w:p><w:r><w:t>Body</w:t></w:r></w:p>' if header else box)
                + section + '</w:body></w:document>')
    types = ('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Override PartName="/word/document.xml" '
             'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
             + ('<Override PartName="/word/header1.xml" '
                'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>' if header else '')
             + '</Types>')
    parts = {'[Content_Types].xml': types, 'word/document.xml': document,
             '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             f'<Relationship Id="main" Type="{REL}/officeDocument" Target="word/document.xml"/></Relationships>'}
    if header:
        parts['word/header1.xml'] = f'<w:hdr {namespaces}>{box}</w:hdr>'
        parts['word/_rels/document.xml.rels'] = (
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="header1" Type="{REL}/header" Target="header1.xml"/></Relationships>')
    with zipfile.ZipFile(path, 'x', compression=zipfile.ZIP_DEFLATED) as package:
        for name, value in sorted(parts.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            package.writestr(info, value.encode())


def boxes(path):
    records = []
    alternatives = []
    with zipfile.ZipFile(path) as package:
        for name in sorted(package.namelist()):
            if not name.startswith('word/') or not name.endswith('.xml'):
                continue
            root, selected = _xml(package.read(name))
            alternatives.extend({'part': name, **choice} for choice in selected)
            parents = {child: parent for parent in root.iter() for child in parent}
            for box in root.iter('{' + W + '}txbxContent'):
                record = {'part': name, 'paragraphs': [
                    ''.join(text.text or '' for text in paragraph.iter('{' + W + '}t'))
                    for paragraph in box.findall('{' + W + '}p')]}
                ancestor = box
                while ancestor in parents and ancestor.tag not in ('{' + WP + '}anchor', '{' + WP + '}inline'):
                    ancestor = parents[ancestor]
                extent = ancestor.find('{' + WP + '}extent')
                if extent is not None:
                    record['framePoints'] = {key: int(value) / 12700 for key, value in extent.attrib.items()}
                records.append(record)
    return {'sha256': digest(path), 'boxes': records, 'alternateContent': alternatives}


def matches_paragraphs(observation, expected):
    return [box['paragraphs'] for box in observation['boxes']] == [expected]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--before-converter', type=Path)
    parser.add_argument('--before-receipt', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    sources = sorted([*ROOT.joinpath('lib').rglob('*.dart'), ROOT / 'pubspec.lock',
                      Path(__file__).resolve(), ROOT / 'tool/fidelity/convert.dart',
                      ROOT / 'tool/fidelity/oracle.py', ROOT / 'tool/fidelity/run.py'])
    source_hashes = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    report = {'schema': 'legacy-doc-parser/textbox-boundary-probe', 'version': 1,
              'parserCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
              'parserWorktreeDirty': bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip()),
              'sourceFiles': source_hashes, 'renderer': command([args.office, '--version']).strip(),
              'compiler': command([args.dart, '--version']).strip(),
              'method': 'Literal OOXML controls use authored expected paragraphs; Word14 before/after is measured separately.',
              'controls': [], 'word14': {}, 'errors': []}
    try:
        if bool(args.before_converter) != bool(args.before_receipt):
            raise ValueError('A before converter requires its saved source receipt.')
        before_source = None
        if args.before_converter:
            before_source = json.loads(args.before_receipt.read_text())
            if digest(args.before_converter) != before_source['converterSha256']:
                raise ValueError('Before-converter hash does not match its receipt.')
        executable = output / 'convert'
        command([args.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', executable], cwd=ROOT)
        report['converterSha256'] = digest(executable)
        for header in (False, True):
            for name, expected in CONTROLS.items():
                case_id = f'{"header" if header else "main"}-{name}'
                base = output / case_id
                base.mkdir()
                original = base / 'authored.docx'
                authored_control(original, expected, header)
                record = {'id': case_id, 'expectedParagraphs': expected, 'authored': boxes(original)}
                report['controls'].append(record)
                binary = office_convert(args.office, original, base / 'bridge', 'doc')
                record['binarySha256'] = digest(binary)
                native = office_convert(args.office, binary, base / 'native', 'docx')
                converted = base / 'converted.docx'
                record['native'] = boxes(native)
                try:
                    record['converter'] = parser_convert(executable, binary, converted)
                    record['parser'] = boxes(converted)
                except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
                    record['parserError'] = str(error)
                    report['errors'].append(f'{case_id}/parser: {error}')
                    if args.before_converter:
                        try:
                            record['beforeConverter'] = parser_convert(
                                args.before_converter.resolve(), binary, base / 'before.docx')
                        except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as baseline_error:
                            record['beforeParserError'] = str(baseline_error)
                for route in ('authored', 'native', 'parser'):
                    if route not in record:
                        continue
                    values = [box['paragraphs'] for box in record[route]['boxes']]
                    record[route]['matchesAuthoredParagraphs'] = matches_paragraphs(record[route], expected)
                    if values != [expected]:
                        report['errors'].append(f'{case_id}/{route}: expected {[expected]!r}, got {values!r}')
                record['sourceUnchanged'] = digest(original) == record['authored']['sha256']
                record['binaryUnchanged'] = digest(binary) == record['binarySha256']
                if not record['sourceUnchanged'] or not record['binaryUnchanged']:
                    raise ValueError('Native control input was changed.')

        source = ROOT / 'test/fixtures/word_native/word14-margin-origin.doc'
        if digest(source) != WORD14_SHA:
            raise ValueError('Word14 source differs from its reviewed source receipt.')
        base = output / 'word14'
        base.mkdir()
        word = report['word14']
        word['sourceSha256'] = WORD14_SHA
        native = office_convert(args.office, source, base / 'native', 'docx')
        word['native'] = boxes(native)
        routes = {'source': source}
        after = base / 'after.docx'
        word['converter'] = parser_convert(executable, source, after)
        word['after'] = boxes(after)
        routes['after'] = after
        if args.before_converter:
            word['beforeSource'] = before_source
            before = base / 'before.docx'
            word['beforeConverter'] = parser_convert(args.before_converter.resolve(), source, before)
            word['before'] = boxes(before)
            routes['before'] = before
        expected = [box['paragraphs'] for box in word['native']['boxes']]
        if len(expected) != 6 or any(len(paragraphs) != 1 for paragraphs in expected):
            raise ValueError('Native Word14 no longer supplies six single-paragraph controls.')
        actual = [box['paragraphs'] for box in word['after']['boxes']]
        word['paragraphOrderMatchesNative'] = actual == expected
        # Native export can reorder independent floating shapes. Retain that
        # order above; match these six uniquely labelled paragraph controls
        # without using their unrelated document traversal order as a golden.
        word['paragraphContentsMatchNative'] = (
            Counter(map(tuple, actual)) == Counter(map(tuple, expected)))
        if not word['paragraphContentsMatchNative']:
            raise ValueError('Parser Word14 textbox paragraphs differ from native source.')
        for route, path in routes.items():
            if route == 'source':
                continue
            roundtrip = office_convert(args.office, path, base / (route + '-native'), 'docx')
            word[route + 'Native'] = boxes(roundtrip)
        renders = {route: render(args.office, path, base / ('render-' + route), 96)
                   for route, path in routes.items()}
        for route in routes:
            (base / (route + '-render.json')).write_text(json.dumps(renders[route], indent=2) + '\n')
            if route != 'source':
                word[route + 'Pagination'] = render_comparison(renders['source'], renders[route])
        word['sourceUnchanged'] = digest(source) == WORD14_SHA
        if not word['sourceUnchanged']:
            raise ValueError('Word14 source changed during native measurement.')
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        report['sourceUnchanged'] = source_hashes == {str(path.relative_to(ROOT)): digest(path) for path in sources}
        if not report['sourceUnchanged']:
            report['errors'].append('Probe source changed during measurement.')
        report['passed'] = not report['errors'] and len(report['controls']) == 14 and bool(report['word14'])
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'controls': len(report['controls']), 'errors': report['errors']}, indent=2))
    return int(not report['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
