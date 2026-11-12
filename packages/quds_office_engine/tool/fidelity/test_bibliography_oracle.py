"""Native hand-authored fixtures and negative controls for bibliography checks."""

from pathlib import Path
import unittest
from xml.etree import ElementTree as ET

from bibliography_oracle import B, CT, NS, PKG, PROPS, R, UNRELATED_ITEM, UNRELATED_SOURCES, W, inspect_parts


def source():
    root = ET.fromstring((Path(__file__).resolve().parents[2] / 'test/fixtures/fidelity/bibliography_sources.xml').read_bytes())
    native = root.find('b:Source', NS)
    for name, value in [('Title', 'Edited & expanded'), ('Year', '2026'), ('Pages', '12-19')]:
        native.find('b:' + name, NS).text = value
    root.append(ET.fromstring(f'<b:Source xmlns:b="{B}"><b:Tag>Added</b:Tag><b:SourceType>Misc</b:SourceType><b:Title>Added source</b:Title><b:Year>2025</b:Year><b:Author><b:Author><b:Corporate>CrispCloud Team</b:Corporate></b:Author></b:Author></b:Source>'))
    return {
        '_rels/.rels': f'<Relationships xmlns="{PKG}"><Relationship Id="main" Type="{R}/officeDocument" Target="office/content/body.xml"/></Relationships>'.encode(),
        '[Content_Types].xml': f'<Types xmlns="{CT}"><Override PartName="/customXml/catalog42.xml" ContentType="application/xml"/></Types>'.encode(),
        'office/content/_rels/body.xml.rels': f'<Relationships xmlns="{PKG}"><Relationship Id="unrelated" Type="{R}/customXml" Target="../../customXml/item1.xml"/><Relationship Id="nativeBibliography" Type="{R}/customXml" Target="../../customXml/catalog42.xml"/></Relationships>'.encode(),
        'office/content/body.xml': f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>Before </w:t></w:r><w:fldSimple w:instr=" CITATION Native "><w:r><w:t>(Original cached source)</w:t></w:r></w:fldSimple><w:r><w:t> after</w:t></w:r></w:p></w:body></w:document>'.encode(),
        'customXml/catalog42.xml': ET.tostring(root),
        'customXml/_rels/catalog42.xml.rels': f'<Relationships xmlns="{PKG}"><Relationship Id="properties" Type="{R}/customXmlProps" Target="itemProps42.xml"/></Relationships>'.encode(),
        'customXml/itemProps42.xml': PROPS,
        'customXml/item1.xml': UNRELATED_ITEM,
        'customXml/sources.xml': UNRELATED_SOURCES,
    }


def mutate_source(parts, mutate):
    root = ET.fromstring(parts['customXml/catalog42.xml'])
    mutate(root)
    parts['customXml/catalog42.xml'] = ET.tostring(root)


class BibliographyOracleTest(unittest.TestCase):
    def test_accepts_independent_native_sources(self):
        self.assertEqual(inspect_parts(source())['editable_sources'], 2)

    def test_rejects_overwritten_unrelated_xml(self):
        parts = source()
        parts['customXml/item1.xml'] = parts['customXml/catalog42.xml']
        with self.assertRaisesRegex(AssertionError, 'item1 XML overwritten'):
            inspect_parts(parts)

    def test_rejects_missing_native_ownership(self):
        parts = source()
        parts['office/content/_rels/body.xml.rels'] = parts['office/content/_rels/body.xml.rels'].replace(b'Type="' + R.encode() + b'/customXml" Target="../../customXml/catalog42.xml"', b'Type="urn:wrong-type" Target="../../customXml/catalog42.xml"')
        with self.assertRaisesRegex(AssertionError, 'one native bibliography'):
            inspect_parts(parts)

    def test_rejects_flattened_authors(self):
        parts = source()
        def flatten(root):
            author = root.find('b:Source/b:Author/b:Author', NS)
            author.clear()
            author.text = 'Ada Byron Lovelace; Grace Hopper'
        mutate_source(parts, flatten)
        with self.assertRaisesRegex(AssertionError, 'structured author list'):
            inspect_parts(parts)

    def test_rejects_lost_unmodeled_source_metadata(self):
        parts = source()
        def remove_publisher(root):
            native = root.find('b:Source', NS)
            native.remove(native.find('b:Publisher', NS))
        mutate_source(parts, remove_publisher)
        with self.assertRaisesRegex(AssertionError, 'native Publisher'):
            inspect_parts(parts)

    def test_rejects_unapplied_scalar_edit(self):
        parts = source()
        mutate_source(parts, lambda root: setattr(root.find('b:Source/b:Title', NS), 'text', 'Original title'))
        with self.assertRaisesRegex(AssertionError, 'native Title'):
            inspect_parts(parts)

    def test_rejects_missing_source_type(self):
        parts = source()
        def remove_type(root):
            added = root.findall('b:Source', NS)[-1]
            added.remove(added.find('b:SourceType', NS))
        mutate_source(parts, remove_type)
        with self.assertRaisesRegex(AssertionError, 'new native source metadata'):
            inspect_parts(parts)

    def test_rejects_lost_properties_relationship(self):
        parts = source()
        parts['customXml/_rels/catalog42.xml.rels'] = f'<Relationships xmlns="{PKG}"/>'.encode()
        with self.assertRaisesRegex(AssertionError, 'source-properties ownership'):
            inspect_parts(parts)

    def test_rejects_changed_body_text(self):
        parts = source()
        parts['office/content/body.xml'] = parts['office/content/body.xml'].replace(b'Before ', b'')
        with self.assertRaisesRegex(AssertionError, 'surrounding body'):
            inspect_parts(parts)


if __name__ == '__main__':
    unittest.main()
