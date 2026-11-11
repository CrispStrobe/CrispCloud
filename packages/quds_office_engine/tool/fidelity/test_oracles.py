import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from corpus import FIXTURES, read_zip, snapshot, validate, word_parts, write_zip

class OracleTests(unittest.TestCase):
    def setUp(self):
        self.parts = read_zip(FIXTURES/'word.docx')

    def test_fixture_is_reproducible_from_independent_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)/'word.docx'
            write_zip(word_parts(), target)
            self.assertEqual(target.read_bytes(), (FIXTURES/'word.docx').read_bytes())

    def test_input_matches_reviewed_golden(self):
        self.assertEqual(json.loads(json.dumps(snapshot(self.parts))), json.loads((FIXTURES/'imported.json').read_text()))

    def test_unresolved_relationship_is_rejected(self):
        self.parts['word/document.xml'] = self.parts['word/document.xml'].replace(b'r:id="link"', b'r:id="missing"')
        self.assertTrue(any('unresolved' in e for e in validate(self.parts)))

    def test_missing_media_is_rejected(self):
        del self.parts['word/media/source.png']
        self.assertTrue(any('dangling target' in e for e in validate(self.parts)))

    def test_missing_note_marker_is_rejected(self):
        self.parts['word/footnotes.xml'] = self.parts['word/footnotes.xml'].replace(b'<w:footnoteRef/>', b'')
        self.assertTrue(any('body reference' in e for e in validate(self.parts)))

    def test_invalid_namespace_is_rejected(self):
        self.parts['word/header1.xml'] = b'<w:hdr/>'
        with self.assertRaises(ET.ParseError): validate(self.parts)

    def test_text_and_numbering_loss_change_the_golden(self):
        expected = snapshot(self.parts)
        self.parts['word/document.xml'] = self.parts['word/document.xml'].replace(b'Imported heading', b'LOST')
        self.parts['word/numbering.xml'] = self.parts['word/numbering.xml'].replace(b'w:val="%1."', b'w:val="*"')
        actual = snapshot(self.parts)
        self.assertNotEqual(actual['text'], expected['text'])
        self.assertNotEqual(actual['numbering'], expected['numbering'])

    def test_property_order_is_checked(self):
        self.parts['word/document.xml'] = self.parts['word/document.xml'].replace(
            b'<w:pStyle w:val="Heading1"/><w:outlineLvl w:val="0"/>',
            b'<w:outlineLvl w:val="0"/><w:pStyle w:val="Heading1"/>')
        self.assertTrue(any('child order' in e for e in validate(self.parts)))

if __name__ == '__main__': unittest.main()
