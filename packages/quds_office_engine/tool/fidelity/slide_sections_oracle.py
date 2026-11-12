"""Independently authored native section fixture and exact XML oracle.

Fixture authoring uses python-pptx, then explicit MS-PPTX section XML. Normal
verification never regenerates fixtures or expected values from Quds output.
Section schema: https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/5bb610d5-ced8-44ed-a4b6-cd3d5f938906
"""
import argparse
import io
import json
import posixpath
from pathlib import Path
from xml.etree import ElementTree as E
from zipfile import ZIP_DEFLATED, ZipFile

P = '{http://schemas.openxmlformats.org/presentationml/2006/main}'
R = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
Q = '{http://schemas.microsoft.com/office/powerpoint/2010/main}'
REL = '{http://schemas.openxmlformats.org/package/2006/relationships}'
KEPT = '{urn:quds:independent-section-properties}'
DECOY = '{urn:quds:foreign-section-decoy}'
SECTION_URI = '{521415D9-36F7-43E2-AB2F-B90AF26B5E84}'
FIXTURE = Path(__file__).resolve().parents[2] / 'test/fixtures/fidelity/slide-sections.pptx'
SLIDE_IDS = dict(zip('ABCDEF', [701, 503, 907, 509, 1201, 803]))
NAMES = ['Leading empty', 'Intro & agenda', 'Gap empty', 'Body', 'Conclusion', 'Trailing empty']
GUIDS = [f'{{A71D8B00-3E2F-4A20-9F10-{index:012X}}}' for index in range(1, 7)]
# Membership is authored explicitly, not computed by the code under test.
EXPECTED = {
    'unchanged': ('ABCDEF', ['', 'AB', '', 'CD', 'EF', '']),
    'within': ('BACDEF', ['', 'BA', '', 'CD', 'EF', '']),
    'forward': ('BCDAEF', ['', 'B', '', 'CDA', 'EF', '']),
    'backward': ('AFBCDE', ['', 'AFB', '', 'CD', 'E', '']),
    'emptied': ('CABDEF', ['', '', '', 'CABD', 'EF', '']),
}


def read_zip(path):
    with ZipFile(path) as archive:
        assert len(archive.namelist()) == len(set(archive.namelist())), 'duplicate ZIP entry'
        assert archive.testzip() is None, 'damaged ZIP entry'
        return {name: archive.read(name) for name in archive.namelist()}


def create_fixture():
    from pptx import Presentation
    deck = Presentation()
    for label in 'ABCDEF':
        slide = deck.slides.add_slide(deck.slide_layouts[1])
        slide.shapes.title.text = 'Section slide ' + label
        slide.placeholders[1].text = 'Independent body ' + label
        slide.notes_slide.notes_text_frame.text = 'Speaker note ' + label
    content = io.BytesIO()
    deck.save(content)
    parts = read_zip(io.BytesIO(content.getvalue()))
    for prefix, uri in [('p', P), ('r', R), ('a', A), ('q', Q), ('kept', KEPT), ('decoy', DECOY)]:
        E.register_namespace(prefix, uri[1:-1])
    root = E.fromstring(parts['ppt/presentation.xml'])
    references = root.find(P + 'sldIdLst')
    for reference, label in zip(references, 'ABCDEF'):
        reference.set('id', str(SLIDE_IDS[label]))
    shows = E.Element(P + 'custShowLst')
    show = E.SubElement(shows, P + 'custShow', name='Identity proof', id='17')
    listing = E.SubElement(show, P + 'sldLst')
    for index in (0, 5, 2):
        E.SubElement(listing, P + 'sld', {R + 'id': references[index].get(R + 'id')})
    root.insert(list(root).index(root.find(P + 'defaultTextStyle')), shows)
    extensions = E.SubElement(root, P + 'extLst')
    extension = E.SubElement(extensions, P + 'ext', uri=SECTION_URI)
    sections = E.SubElement(extension, Q + 'sectionLst')
    for index, (name, guid, labels) in enumerate(zip(NAMES, GUIDS, EXPECTED['unchanged'][1])):
        section = E.SubElement(sections, Q + 'section', name=name, id=guid)
        members = E.SubElement(section, Q + 'sldIdLst')
        for label in labels:
            E.SubElement(members, Q + 'sldId', id=str(SLIDE_IDS[label]))
        properties = E.SubElement(section, Q + 'extLst')
        opaque = E.SubElement(properties, P + 'ext', uri='{DDC59410-809A-4EAC-AC31-128E094C2898}')
        payload = E.SubElement(opaque, KEPT + 'property', index=str(index), token='keep-' + str(index))
        E.SubElement(payload, KEPT + 'value').text = 'Unchanged property ' + str(index)
    foreign = E.SubElement(extensions, P + 'ext', uri='{426D44A1-237D-4DA8-862F-229CD93938D4}')
    decoy = E.SubElement(foreign, DECOY + 'sectionLst')
    section = E.SubElement(decoy, DECOY + 'section', name='Foreign decoy', id='not-a-native-guid')
    E.SubElement(E.SubElement(section, DECOY + 'sldIdLst'), DECOY + 'sldId', id='701')
    parts['ppt/presentation.xml'] = E.tostring(root, encoding='utf-8', xml_declaration=True)
    parts['customXml/section-proof.xml'] = b'<proof producer="independent">retained opaque part</proof>'
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(FIXTURE, 'w', ZIP_DEFLATED) as archive:
        for name, payload in parts.items():
            archive.writestr(name, payload)
    inspect_parts(read_zip(FIXTURE), 'unchanged')
    print(FIXTURE)


def canonical(element):
    assert element is not None, 'missing retained XML element'
    return (element.tag, tuple(sorted(element.attrib.items())), element.text.strip() if element.text else '',
            tuple(canonical(child) for child in element))


def relationships(parts, owner):
    parent, name = posixpath.split(owner)
    root = E.fromstring(parts[posixpath.join(parent, '_rels', name + '.rels')])
    return {rel.get('Id'): (rel.get('Type'), posixpath.normpath(posixpath.join(parent, rel.get('Target'))))
            for rel in root.findall(REL + 'Relationship') if rel.get('TargetMode') != 'External'}


def inspect_parts(parts, scenario):
    order, memberships = EXPECTED[scenario]
    root = E.fromstring(parts['ppt/presentation.xml'])
    entries = root.find(P + 'sldIdLst')
    assert [int(node.get('id')) for node in entries] == [SLIDE_IDS[label] for label in order], 'slide ID/order drift'
    sections = root.findall(P + 'extLst/' + P + f'ext[@uri="{SECTION_URI}"]/' + Q + 'sectionLst/' + Q + 'section')
    assert [node.get('name') for node in sections] == NAMES, 'section order/names or empty section lost'
    assert [node.get('id') for node in sections] == GUIDS, 'native section GUID drift'
    assert [[int(item.get('id')) for item in node.findall(Q + 'sldIdLst/' + Q + 'sldId')] for node in sections] == [
        [SLIDE_IDS[label] for label in labels] for labels in memberships], 'section membership/order drift'
    for index, node in enumerate(sections):
        payload = node.find(Q + 'extLst/' + P + 'ext/' + KEPT + 'property')
        assert payload is not None and payload.attrib == {'index': str(index), 'token': 'keep-' + str(index)}, 'section opaque properties lost'
        assert payload.findtext(KEPT + 'value') == 'Unchanged property ' + str(index), 'section opaque value changed'
    decoy = root.find(P + 'extLst/' + P + 'ext/' + DECOY + 'sectionLst')
    expected_decoy = E.fromstring('<d:sectionLst xmlns:d="urn:quds:foreign-section-decoy"><d:section name="Foreign decoy" id="not-a-native-guid"><d:sldIdLst><d:sldId id="701"/></d:sldIdLst></d:section></d:sectionLst>')
    assert canonical(decoy) == canonical(expected_decoy), 'foreign section-like extension changed'
    rels = relationships(parts, 'ppt/presentation.xml')
    slide_parts = {}
    for entry, label in zip(entries, order):
        typ, owner = rels[entry.get(R + 'id')]
        assert typ.endswith('/slide'), 'slide relationship type changed'
        slide_parts[label] = (entry.get(R + 'id'), owner)
        slide = E.fromstring(parts[owner])
        text = [node.text for node in slide.iter(A + 't')]
        assert 'Section slide ' + label in text and 'Independent body ' + label in text, 'slide ownership changed'
        notes = [target for typ, target in relationships(parts, owner).values() if typ.endswith('/notesSlide')]
        assert len(notes) == 1 and 'Speaker note ' + label in ''.join(E.fromstring(parts[notes[0]]).itertext()), 'speaker-note ownership changed'
    custom = root.findall(P + 'custShowLst/' + P + 'custShow/' + P + 'sldLst/' + P + 'sld')
    assert [node.get(R + 'id') for node in custom] == [slide_parts[label][0] for label in 'AFC'], 'custom show identity changed'
    for label, (_, owner) in slide_parts.items():
        assert owner == f'ppt/slides/slide{"ABCDEF".index(label) + 1}.xml', 'native slide part identity changed'
    assert parts['customXml/section-proof.xml'] == b'<proof producer="independent">retained opaque part</proof>', 'opaque package part changed'


def verify_directory(directory):
    expected = {f'{mode}/{scenario}-{cycle}.pptx' for mode in ('direct', 'isolate')
                for scenario in EXPECTED for cycle in (1, 2, 3)}
    expected |= {f'{mode}/source.pptx' for mode in ('direct', 'isolate')}
    actual = {path.relative_to(directory).as_posix() for path in directory.rglob('*.pptx')}
    assert actual == expected, f'incomplete section corpus: missing={expected - actual}, unexpected={actual - expected}'
    for name in sorted(expected):
        stem = Path(name).stem
        scenario = 'unchanged' if stem == 'source' else stem.rsplit('-', 1)[0]
        inspect_parts(read_zip(directory / name), scenario)
    report = {'exports': len(expected), 'cycles': 3, 'scenarios': list(EXPECTED), 'failures': []}
    (directory / 'oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create-fixture', action='store_true')
    parser.add_argument('directory', nargs='?', type=Path, default=Path('build/fidelity-slide-sections'))
    args = parser.parse_args()
    create_fixture() if args.create_fixture else verify_directory(args.directory)
