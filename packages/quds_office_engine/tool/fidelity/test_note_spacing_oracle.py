"""The rich-note oracle must reject manufactured whitespace after the marker."""
import copy
import json
from pathlib import Path
import unittest
from xml.etree import ElementTree as E
from corpus import NS, W, read_zip
from notes_oracle import snapshot


class NoteSpacingOracleControl(unittest.TestCase):
    def test_added_separator_changes_authored_expectation(self):
        expected = json.loads(Path('test/fixtures/fidelity/notes_imported.json').read_text())
        parts = read_zip(Path('build/fidelity-notes/source.docx'))
        self.assertEqual(snapshot(parts), expected)
        damaged = copy.deepcopy(parts)
        root = E.fromstring(damaged['word/footnotes.xml'])
        first = root.find("w:footnote[@w:id='12']/w:p/w:r/w:t", NS)
        first.text = ' ' + first.text
        damaged['word/footnotes.xml'] = E.tostring(root)
        self.assertNotEqual(snapshot(damaged), expected)
        self.assertEqual(snapshot(damaged)['leading_whitespace'], ' ')

    def test_added_marker_formatting_changes_authored_expectation(self):
        expected = json.loads(Path('test/fixtures/fidelity/notes_imported.json').read_text())
        parts = read_zip(Path('build/fidelity-notes/source.docx'))
        self.assertEqual(snapshot(parts), expected)
        root = E.fromstring(parts['word/footnotes.xml'])
        marker = root.find("w:footnote[@w:id='12']/w:p/w:r", NS)
        properties = E.Element(f'{{{W}}}rPr')
        E.SubElement(properties, f'{{{W}}}vertAlign', {f'{{{W}}}val':'superscript'})
        marker.insert(0, properties)
        parts['word/footnotes.xml'] = E.tostring(root)
        self.assertNotEqual(snapshot(parts), expected)


if __name__ == '__main__':
    unittest.main()
