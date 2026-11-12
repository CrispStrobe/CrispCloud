#!/usr/bin/env python3
"""Check authored Word structure-loss probes using the real modification CLI.

It authors OPC wrappers around the committed XML, performs an adjacent edit,
checks three save/reopen cycles using Python's XML parser, and exits nonzero
when any source structure is lost. The historical 692a326 report reproduces
the original data loss; the current gate requires both probes to preserve it. It never changes source fixtures or accepted goldens. Office
packages exist only in a temporary directory; the retained artifact is JSON.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile

ENGINE = Path(__file__).resolve().parents[2]
FIXTURES = ENGINE / 'test/fixtures/fidelity/loss-probes'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS = {'w': W}


def package(document_xml, path):
    """The probe input does not pass through an engine serializer."""
    with ZipFile(path, 'w', compression=ZIP_DEFLATED) as archive:
        archive.writestr('word/document.xml', document_xml)
        archive.writestr('_rels/.rels',
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/>'
            '</Relationships>')
        archive.writestr('[Content_Types].xml',
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '</Types>')


def snapshot(document_xml):
    root = ET.fromstring(document_xml)
    controls = []

    def value(node, path):
        child = node.find(path, NS)
        return child.get(f'{{{W}}}val') if child is not None else None

    for node in root.findall('.//w:sdt', NS):
        controls.append({
            'alias': value(node, 'w:sdtPr/w:alias'),
            'tag': value(node, 'w:sdtPr/w:tag'),
            'id': value(node, 'w:sdtPr/w:id'),
            'end_color': value(node, 'w:sdtEndPr/w:rPr/w:color'),
            'text': ''.join(item.text or '' for item in node.findall('.//w:t', NS)),
        })
    starts, ends = {}, {}
    for index, paragraph in enumerate(root.findall('.//w:p', NS)):
        offset = 0
        for node in paragraph.iter():
            if node.tag == f'{{{W}}}t':
                offset += len(node.text or '')
            elif node.tag == f'{{{W}}}bookmarkStart':
                starts[node.get(f'{{{W}}}id')] = {
                    'name': node.get(f'{{{W}}}name'),
                    'start': [index, offset],
                }
            elif node.tag == f'{{{W}}}bookmarkEnd':
                ends[node.get(f'{{{W}}}id')] = [index, offset]
    # Pair by package ID, then compare names and endpoints. Changing an ID alone
    # does not count as lost content; losing/expanding/moving its range does.
    bookmarks = sorted([
        {**start, 'end': ends.get(identifier)}
        for identifier, start in starts.items()
    ], key=lambda item: item['name'])
    return {'content_controls': controls, 'bookmarks': bookmarks,
            'bookmark_start_count': len(root.findall('.//w:bookmarkStart', NS)),
            'bookmark_end_count': len(root.findall('.//w:bookmarkEnd', NS)),
            'unmatched_end_ids': sorted(set(ends) - set(starts))}


def run_cli(dart, arguments):
    result = subprocess.run([dart, 'run', 'tool/fidelity/office_steps.dart', *arguments],
                            cwd=ENGINE, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError('Modification CLI failed: ' + result.stderr.strip())


def audit(dart):
    report = {'scope': 'authored Word structure preservation through adjacent edits', 'open_gaps': 0, 'probes': {}}
    with tempfile.TemporaryDirectory(prefix='quds-word-loss-') as temporary:
        folder = Path(temporary)
        steps = folder / 'adjacent-edit.json'
        steps.write_text(json.dumps([
            {'op': 'replaceText', 'paragraph': 0, 'text': 'Edited probe prefix'}]))
        for name in ('content-control', 'bookmark-ranges'):
            source_xml = (FIXTURES / f'{name}.xml').read_bytes()
            before = snapshot(source_xml)
            if name == 'content-control' and len(before['content_controls']) != 1:
                raise ValueError('The authored content-control specimen changed')
            if name == 'bookmark-ranges' and len(before['bookmarks']) != 3:
                raise ValueError('The authored bookmark specimen changed')
            source = folder / f'{name}.docx'
            package(source_xml, source)
            cycles = []
            for cycle in range(1, 4):
                output = folder / f'{name}-{cycle}.docx'
                run_cli(dart, ['modify', str(source), str(steps), str(output)] if cycle == 1
                        else ['export', str(source), str(output)])
                with ZipFile(output) as archive:
                    after = snapshot(archive.read('word/document.xml'))
                cycles.append({'cycle': cycle, 'preserved': after == before, 'observed': after})
                source = output
            lost = any(not result['preserved'] for result in cycles)
            report['open_gaps'] += int(lost)
            report['probes'][name] = {
                'status': 'data_loss_observed' if lost else 'source_structure_preserved',
                'source': before, 'cycles': cycles,
            }
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default='dart', help='Dart executable to run the modification CLI')
    parser.add_argument('--output', type=Path, default=ENGINE / 'build/fidelity-unsupported-probes/report.json')
    args = parser.parse_args()
    report = audit(args.dart)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    for name, probe in report['probes'].items():
        print(f'{name}: {probe["status"]}')
    print(f'{report["open_gaps"]} open data-loss probes; report: {args.output}')
    raise SystemExit(1 if report['open_gaps'] else 0)


if __name__ == '__main__':
    main()
