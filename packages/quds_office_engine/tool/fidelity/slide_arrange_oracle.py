#!/usr/bin/env python3
"""Verify the native arrangement corpus without importing the Dart model.

The five card positions/text and two group memberships below are literal
authored intent. The source must be the exact committed python-pptx fixture.
Grouping may add native containers but cannot transform their child geometry.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import posixpath
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'test/fixtures/fidelity/slide-arrange.pptx'
FIXTURE_SHA256 = '6d86b24c22bdaac9d2e57167f7f506626029b4060eb793f523bfe86bfe266b50'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
NS = {'p': P, 'a': A, 'r': R}
SHAPES = [
    ('Card 1', 'Card 1', 254000, 1000000, 1400000, 1000000),
    ('Card 2', 'Card 2', 1954000, 1000000, 1400000, 1000000),
    ('Card 3', 'Card 3', 3654000, 1000000, 1400000, 1000000),
    ('Card 4', 'Card 4', 5354000, 1000000, 1400000, 1000000),
    ('Card 5', 'Card 5', 7054000, 1000000, 1400000, 1000000),
]
GROUPS = [['Card 1', 'Card 2'], ['Card 3', 'Card 4']]
EXPECTED_FILES = ['source.pptx', 'direct-1.pptx', 'direct-2.pptx', 'direct-3.pptx',
                  'isolate-1.pptx', 'isolate-2.pptx', 'isolate-3.pptx']


def equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')


def one(parent, path, label):
    matches = parent.findall(path, NS)
    equal(len(matches), 1, label + ' count')
    return matches[0]


def integer(value, label):
    if value is None or not re.fullmatch(r'[+-]?[0-9]+', value.strip()):
        raise AssertionError(f'{label}: missing or nonintegral native value {value!r}')
    return int(value)


def unsigned_id(node):
    value = integer(node.get('id'), 'cNvPr ID')
    if not 0 <= value <= 4294967295:
        raise AssertionError(f'cNvPr ID outside uint32: {value}')
    return value


def no_rotation_or_flip(transform, label):
    equal(integer(transform.get('rot', '0'), label + ' rotation'), 0, label + ' rotation')
    for name in ('flipH', 'flipV'):
        if transform.get(name, 'false') not in ('0', 'false', 'off'):
            raise AssertionError(f'{label}: unexpected {name}')


def identity_group_transform(container):
    properties = one(container, 'p:grpSpPr', 'native group properties')
    transforms = properties.findall('a:xfrm', NS)
    if not transforms:
        return  # An omitted native group transform leaves child coordinates intact.
    equal(len(transforms), 1, 'group transform count')
    transform = transforms[0]
    no_rotation_or_flip(transform, 'group')
    if not list(transform):
        return
    off = one(transform, 'a:off', 'group offset')
    child_off = one(transform, 'a:chOff', 'group child offset')
    ext = one(transform, 'a:ext', 'group extent')
    child_ext = one(transform, 'a:chExt', 'group child extent')
    for axis in ('x', 'y'):
        equal(integer(off.get(axis), 'group offset'),
              integer(child_off.get(axis), 'group child offset'), 'identity group offset')
    for axis in ('cx', 'cy'):
        value = integer(ext.get(axis), 'group extent')
        if value <= 0:
            raise AssertionError('Group scale must have a positive extent')
        equal(value, integer(child_ext.get(axis), 'group child extent'), 'identity group scale')


def shape_record(shape):
    identity = one(shape, 'p:nvSpPr/p:cNvPr', 'shape identity')
    transform = one(shape, 'p:spPr/a:xfrm', 'shape transform')
    no_rotation_or_flip(transform, identity.get('name', 'shape'))
    offset = one(transform, 'a:off', 'shape offset')
    extent = one(transform, 'a:ext', 'shape extent')
    paragraphs = shape.findall('p:txBody/a:p', NS)
    equal(len(paragraphs), 1, 'authored text paragraph count')
    if paragraphs[0].findall('.//a:br', NS):
        raise AssertionError('Authored card text acquired a line break')
    text = ''.join(node.text or '' for node in paragraphs[0].iter('{' + A + '}t'))
    return (identity.get('name'), text,
            integer(offset.get('x'), 'shape x'), integer(offset.get('y'), 'shape y'),
            integer(extent.get('cx'), 'shape width'), integer(extent.get('cy'), 'shape height'))


def read_parts(path):
    with ZipFile(path) as package:
        equal(len(package.namelist()), len(set(package.namelist())), 'unique ZIP entry count')
        equal(package.testzip(), None, 'ZIP integrity')
        return {entry: package.read(entry) for entry in package.namelist()}


def inspect_parts(parts, *, grouped):
    presentation = ET.fromstring(parts['ppt/presentation.xml'])
    equal(presentation.tag, '{' + P + '}presentation', 'native presentation root')
    size = one(presentation, 'p:sldSz', 'slide size')
    equal((integer(size.get('cx'), 'slide width'), integer(size.get('cy'), 'slide height')),
          (9144000, 6858000), 'authored slide dimensions')
    slide = one(presentation, 'p:sldIdLst/p:sldId', 'authored single slide')
    relationships = ET.fromstring(parts['ppt/_rels/presentation.xml.rels'])
    matches = [node for node in relationships.findall('{' + REL + '}Relationship')
               if node.get('Id') == slide.get('{' + R + '}id')]
    equal(len(matches), 1, 'slide relationship')
    relation = matches[0]
    equal(relation.get('Type'), R + '/slide', 'native slide relationship type')
    if relation.get('TargetMode', 'Internal') != 'Internal':
        raise AssertionError('Slide target must stay inside the package')
    target = relation.get('Target', '')
    owner = posixpath.normpath(target.lstrip('/') if target.startswith('/') else
                              posixpath.join('ppt', target))
    equal(owner, 'ppt/slides/slide1.xml', 'authored slide part ownership')
    equal(sorted(name for name in parts if re.fullmatch(r'ppt/slides/slide[0-9]+\.xml', name)),
          ['ppt/slides/slide1.xml'], 'single native slide part')
    root = ET.fromstring(parts[owner])
    equal(root.tag, '{' + P + '}sld', 'native slide root')
    tree = one(root, 'p:cSld/p:spTree', 'native shape tree')
    one(tree, 'p:nvGrpSpPr/p:cNvPr', 'root group identity')
    identities = root.findall('.//p:cNvPr', NS)
    ids = [unsigned_id(node) for node in identities]
    equal(len(ids), 8 if grouped else 6, 'root, group and shape identity count')
    equal(len(set(ids)), len(ids), 'unique numeric cNvPr IDs')
    shapes = tree.findall('.//p:sp', NS)
    equal([shape_record(shape) for shape in shapes], SHAPES, 'literal authored shape geometry and text')
    groups = tree.findall('p:grpSp', NS)
    equal(len(tree.findall('.//p:grpSp', NS)), 2 if grouped else 0, 'flat native group count')
    memberships = [[shape_record(shape)[0] for shape in group.findall('p:sp', NS)]
                   for group in groups]
    equal(memberships, GROUPS if grouped else [], 'ordered group membership')
    for container in [tree, *groups]:
        identity_group_transform(container)
        if container is not tree:
            one(container, 'p:nvGrpSpPr/p:cNvPr', 'group identity')
    visible = []
    for child in tree:
        if child.tag == '{' + P + '}grpSp':
            visible.append([shape_record(shape)[0] for shape in child.findall('p:sp', NS)])
        elif child.tag == '{' + P + '}sp':
            visible.append(shape_record(child)[0])
        elif child.tag not in ('{' + P + '}nvGrpSpPr', '{' + P + '}grpSpPr', '{' + P + '}extLst'):
            raise AssertionError('Unexpected visible shape-tree child: ' + child.tag)
    equal(visible, [*GROUPS, 'Card 5'] if grouped else [item[0] for item in SHAPES],
          'group and ungrouped drawing order')
    return {'ids': ids, 'shapes': SHAPES, 'groups': memberships, 'drawing_order': visible}


def verify_source(path):
    fixture = FIXTURE.read_bytes()
    equal(hashlib.sha256(fixture).hexdigest(), FIXTURE_SHA256, 'authored fixture fingerprint')
    equal(path.read_bytes(), fixture, 'exact authored source package bytes')
    return inspect_parts(read_parts(path), grouped=False)


def verify(root):
    paths = sorted(path.relative_to(root).as_posix() for path in root.rglob('*')
                   if path.is_file() and path.suffix.lower() == '.pptx')
    equal(paths, sorted(EXPECTED_FILES), 'exact seven-file arrangement inventory')
    verify_source(root / 'source.pptx')
    records = []
    first = None
    for name in EXPECTED_FILES:
        path = root / name
        record = inspect_parts(read_parts(path), grouped=name != 'source.pptx')
        if name != 'source.pptx':
            if first is None:
                first = record
            equal(record, first, 'stable direct/isolate native grouping and IDs over three saves')
        records.append({'name': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'native_ids': record['ids']})
    return {'status': 'passed', 'files_verified': 7, 'direct_cycles': 3, 'isolate_cycles': 3,
            'fixture_sha256': FIXTURE_SHA256, 'groups': GROUPS, 'ungrouped': ['Card 5'],
            'checks': ['exact source bytes and seven-file inventory', 'literal five-card geometry and text',
                       'two flat ordered native groups', 'unchanged ungrouped card',
                       'unique uint32 root/group/shape IDs', 'identity group coordinate transforms',
                       'stable native identities across direct and isolate saves'], 'files': records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT / 'build/fidelity-slide-arrange')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = verify(args.root)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
