#!/usr/bin/env python3
"""Independently check the authored restart scenario in exported DOCX ZIP/XML."""
import argparse
import io
import json
from pathlib import Path
import zipfile
import xml.etree.ElementTree as ET

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
R = '{http://schemas.openxmlformats.org/package/2006/relationships}'


def snapshot(data: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        assert len(archive.namelist()) == len(set(archive.namelist())), 'duplicate ZIP part'
        body = ET.fromstring(archive.read('word/document.xml')).find(W + 'body')
        numbering = ET.fromstring(archive.read('word/numbering.xml'))
        rels = ET.fromstring(archive.read('word/_rels/document.xml.rels'))
    assert any(rel.get('Type', '').endswith('/numbering') and
               rel.get('Target') == 'numbering.xml' and
               rel.get('TargetMode') != 'External' for rel in rels.findall(R + 'Relationship')), 'numbering relationship'
    assert body is not None, 'document body'
    paragraphs = body.findall(W + 'p')
    assert [''.join(p.itertext()).strip() for p in paragraphs] == [
        'One', 'Two', 'Three', 'Four', 'Five', 'Six'
    ], 'paragraph text'
    ids = []
    for paragraph in paragraphs:
        props = paragraph.find(W + 'pPr/' + W + 'numPr')
        assert props is not None, 'missing paragraph numbering'
        number = props.find(W + 'numId')
        level = props.find(W + 'ilvl')
        assert number is not None and level is not None, 'missing numbering id/level'
        assert level.get(W + 'val') == '0', 'unexpected level'
        ids.append(number.get(W + 'val'))
    assert ids[0] == ids[1] and ids[2] == ids[3] and ids[4] == ids[5], 'continuation lost'
    assert len({ids[0], ids[2], ids[4]}) == 3, 'restart instances collapsed'
    instances = {node.get(W + 'numId'): node for node in numbering.findall(W + 'num')}
    assert len(instances) == len(numbering.findall(W + 'num')), 'duplicate numbering id'
    definitions = {node.get(W + 'abstractNumId'): node for node in numbering.findall(W + 'abstractNum')}
    starts = {}
    abstract_ids = []
    for index, number_id in enumerate([ids[0], ids[2], ids[4]]):
        assert number_id in instances, 'undefined numbering instance'
        instance = instances[number_id]
        abstract = instance.find(W + 'abstractNumId')
        assert abstract is not None, 'missing abstract definition reference'
        abstract_id = abstract.get(W + 'val')
        abstract_ids.append(abstract_id)
        assert abstract_id in definitions, 'undefined abstract definition'
        level = definitions[abstract_id].find(W + 'lvl')
        assert level is not None, 'missing abstract level'
        assert level.find(W + 'numFmt').get(W + 'val') == 'decimal', 'number format changed'
        if index == 0:
            assert instance.find(W + 'lvlOverride') is None, 'original list was restarted'
            starts[number_id] = int(level.find(W + 'start').get(W + 'val'))
        else:
            overrides = instance.findall(W + 'lvlOverride')
            assert len(overrides) == 1 and overrides[0].get(W + 'ilvl') == '0', 'restart override level'
            start = overrides[0].find(W + 'startOverride')
            assert start is not None and start.get(W + 'val') == '5', 'restart override value'
            starts[number_id] = 5
    assert len(set(abstract_ids)) == 1, 'restart changed the list definition'
    counters = dict(starts)
    labels = []
    for number_id in ids:
        labels.append(counters[number_id])
        counters[number_id] += 1
    assert labels == [1, 2, 5, 6, 5, 6], 'effective list numbers'
    return {'labels': labels, 'paragraph_count': len(paragraphs), 'restart_count': 2}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    report = {}
    for cycle in range(3):
        path = args.directory / f'restarted-{cycle}.docx'
        report[path.name] = snapshot(path.read_bytes())
    (args.directory / 'list-oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Verified {len(report)} independent list restart exports.')


if __name__ == '__main__':
    main()
