"""Independent positive/negative controls for native automatic note marks."""
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import note_markers_oracle as oracle


class NoteMarkersOracleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.output = self.folder / 'mutated.docx'
        self.expected = json.loads((oracle.FIXTURES / 'note_markers_expected.json').read_text())
        with ZipFile(oracle.FIXTURES / 'note-markers.docx') as package:
            self.parts = {name: package.read(name) for name in package.namelist()}

    @staticmethod
    def note(root, identifier):
        return next(node for node in root if node.get('{' + oracle.W + '}id') == str(identifier))

    def reject(self, kind, operation):
        part = f'word/{kind}s.xml'
        root = ET.fromstring(self.parts[part])
        operation(root)
        self.parts[part] = ET.tostring(root)
        with ZipFile(self.output, 'w') as package:
            for name, data in self.parts.items():
                package.writestr(name, data)
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.output, self.expected, 'imported')

    def test_authored_fixture_is_positive_control(self):
        oracle.verify_file(oracle.FIXTURES / 'note-markers.docx', self.expected, 'imported')

    def test_absent_footnote_marker_cannot_be_manufactured(self):
        def add(root):
            run = ET.Element('{' + oracle.W + '}r')
            ET.SubElement(run, '{' + oracle.W + '}footnoteRef')
            self.note(root, 12).find('w:p', oracle.NS).insert(0, run)
        self.reject('footnote', add)

    def test_absent_endnote_marker_cannot_be_manufactured(self):
        def add(root):
            run = ET.Element('{' + oracle.W + '}r')
            ET.SubElement(run, '{' + oracle.W + '}endnoteRef')
            self.note(root, 32).find('w:p', oracle.NS).insert(0, run)
        self.reject('endnote', add)

    def test_nonleading_marker_cannot_move_before_text(self):
        def move(root):
            run = self.note(root, 13).find('w:p/w:r', oracle.NS)
            marker = run.find('w:footnoteRef', oracle.NS)
            run.remove(marker)
            run.insert(1, marker)
        self.reject('footnote', move)

    def test_later_paragraph_marker_cannot_move_to_first(self):
        def move(root):
            note = self.note(root, 14)
            mark_run = note[1][0]
            note[1].remove(mark_run)
            note[0].insert(0, mark_run)
        self.reject('footnote', move)

    def test_multiple_markers_cannot_collapse(self):
        def remove(root):
            run = self.note(root, 15).find('w:p/w:r', oracle.NS)
            run.remove(run.findall('w:footnoteRef', oracle.NS)[1])
        self.reject('footnote', remove)

    def test_endnote_kind_cannot_turn_into_footnote(self):
        self.reject('endnote', lambda root: setattr(
            self.note(root, 31).find('w:p/w:r/w:endnoteRef', oracle.NS),
            'tag', '{' + oracle.W + '}footnoteRef'))

    def test_marker_properties_cannot_be_dropped(self):
        def remove(root):
            run = self.note(root, 11).find('w:p/w:r', oracle.NS)
            run.remove(run.find('w:rPr', oracle.NS))
        self.reject('footnote', remove)

    def test_each_marker_retains_its_own_properties(self):
        self.reject('footnote', lambda root:
                    self.note(root, 15).find('w:p/w:r[2]/w:rPr/w:vertAlign', oracle.NS).set(
                        '{' + oracle.W + '}val', 'superscript'))

    def test_unformatted_marker_cannot_gain_superscript(self):
        def add(root):
            run = self.note(root, 14).findall('w:p', oracle.NS)[1].find('w:r', oracle.NS)
            props = ET.Element('{' + oracle.W + '}rPr')
            ET.SubElement(props, '{' + oracle.W + '}vertAlign', {'{' + oracle.W + '}val': 'superscript'})
            run.insert(0, props)
        self.reject('footnote', add)

    def test_table_first_note_cannot_gain_a_leading_paragraph(self):
        self.reject('footnote', lambda root: self.note(root, 16).insert(0, ET.Element('{' + oracle.W + '}p')))

    def test_text_before_same_run_marker_cannot_move_after_it(self):
        def move(root):
            run = self.note(root, 13).find('w:p/w:r', oracle.NS)
            text = run.find('w:t', oracle.NS)
            run.remove(text)
            run.append(text)
        self.reject('footnote', move)

    def test_source_baseline_cannot_be_omitted(self):
        for mode in ('imported', 'edited'):
            for cycle in (1, 2, 3):
                (self.folder / f'markers-{mode}-{cycle}.docx').write_bytes(b'placeholder')
        with self.assertRaisesRegex(AssertionError, 'missing=.*markers-source.docx'):
            oracle.verify_corpus(self.folder, self.expected)

    def test_empty_corpus_fails(self):
        with self.assertRaisesRegex(AssertionError, 'Note marker corpus inventory'):
            oracle.verify_corpus(self.folder, self.expected)


if __name__ == '__main__':
    unittest.main()
