"""Positive controls and intentional native content-control metadata/content loss."""
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import content_controls_oracle as oracle


class ContentControlsOracleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.target = Path(self.temporary.name) / 'control.docx'
        self.expected = json.loads((oracle.FIXTURES / 'content_controls_expected.json').read_text())
        with ZipFile(oracle.FIXTURES / 'content-controls.docx') as package:
            self.parts = {name: package.read(name) for name in package.namelist()}

    def write(self):
        with ZipFile(self.target, 'w') as package:
            for name, data in self.parts.items():
                package.writestr(name, data)

    def mutate(self, operation, mode='imported'):
        root = ET.fromstring(self.parts['word/document.xml'])
        operation(root)
        self.parts['word/document.xml'] = ET.tostring(root)
        self.write()
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.target, self.expected, mode)

    def test_authored_source_is_valid(self):
        oracle.verify_file(oracle.FIXTURES / 'content-controls.docx', self.expected)

    def test_authored_legacy_conversion_input_is_valid(self):
        oracle.verify_file(oracle.FIXTURES / 'content-controls-legacy.docx', self.expected, 'legacy')

    def test_legacy_conversion_cannot_keep_an_ordinary_flow_paragraph(self):
        with self.assertRaises(AssertionError):
            oracle.verify_file(oracle.FIXTURES / 'content-controls-legacy.docx', self.expected,
                               'legacy', converted_legacy=True)

    def test_byte_identical_renderer_baseline_is_valid(self):
        self.target.write_bytes((oracle.FIXTURES / 'content-controls.docx').read_bytes())
        oracle.verify_source_copy(self.target)

    def test_changed_source_baseline_is_rejected_even_if_zip_still_opens(self):
        self.target.write_bytes((oracle.FIXTURES / 'content-controls.docx').read_bytes() + b'\n')
        with ZipFile(self.target) as package:
            self.assertIsNone(package.testzip())
        with self.assertRaises(AssertionError):
            oracle.verify_source_copy(self.target)

    def test_independently_authored_edits_are_valid(self):
        replacements = {'Before': 'Before edited', 'Alpha': 'Omega', 'Nested Beta': 'Nested edited',
                        'In': 'Updated', 'si': '', 'de': '',
                        'Header value': 'Header edited', 'Note Delta': 'Note edited'}
        for name in ('word/document.xml', 'word/header1.xml', 'word/footnotes.xml'):
            root = ET.fromstring(self.parts[name])
            for text in root.iter('{' + oracle.W + '}t'):
                text.text = replacements.get(text.text, text.text)
            self.parts[name] = ET.tostring(root)
        self.write()
        oracle.verify_file(self.target, self.expected, 'edited')

    def authored_editor(self):
        root = ET.fromstring(self.parts['word/document.xml'])
        control = next(node for node in root.iter('{' + oracle.W + '}sdt')
                       if node.find('w:sdtPr/w:id', oracle.NS).get('{' + oracle.W + '}val') == '102')
        content = control.find('w:sdtContent', oracle.NS)
        original = content.find('w:p', oracle.NS)
        tail = ET.fromstring(ET.tostring(original))
        original.find('w:r/w:t', oracle.NS).text = 'Nested '
        tail.find('w:r/w:t', oracle.NS).text = 'Be edited ta'
        content.append(tail)
        self.parts['word/document.xml'] = ET.tostring(root)

    def test_independently_authored_editor_split_is_valid(self):
        self.authored_editor()
        self.write()
        oracle.verify_file(self.target, self.expected, 'editor')

    def test_editor_paragraph_split_cannot_merge_even_when_text_matches(self):
        self.authored_editor()
        def merge(root):
            control = next(node for node in root.iter('{' + oracle.W + '}sdt')
                           if node.find('w:sdtPr/w:id', oracle.NS).get('{' + oracle.W + '}val') == '102')
            content = control.find('w:sdtContent', oracle.NS)
            paragraphs = content.findall('w:p', oracle.NS)
            paragraphs[0].find('w:r/w:t', oracle.NS).text = 'Nested Be edited ta'
            content.remove(paragraphs[1])
        self.mutate(merge, 'editor')

    def test_wrapper_cannot_disappear_while_its_text_survives(self):
        def lose(root):
            body = root.find('w:body', oracle.NS)
            control = body.find('w:sdt', oracle.NS)
            position = list(body).index(control)
            for child in list(control.find('w:sdtContent', oracle.NS)):
                body.insert(position, child)
                position += 1
            body.remove(control)
        self.mutate(lose)

    def test_alias_tag_id_and_end_properties_are_required(self):
        for field in ('alias', 'tag', 'id'):
            with self.subTest(field=field):
                saved = self.parts.copy()
                self.mutate(lambda root: root.find('.//w:sdtPr', oracle.NS).remove(
                    root.find('.//w:sdtPr/w:' + field, oracle.NS)))
                self.parts = saved
        self.mutate(lambda root: root.find('.//w:sdt', oracle.NS).remove(
            root.find('.//w:sdtEndPr', oracle.NS)))

    def test_empty_control_cannot_be_dropped(self):
        def lose(root):
            body = root.find('w:body', oracle.NS)
            empty = next(node for node in body.findall('w:sdt', oracle.NS)
                         if node.find('w:sdtPr/w:id', oracle.NS).get('{' + oracle.W + '}val') == '104')
            body.remove(empty)
        self.mutate(lose)

    def test_absent_slot_cannot_be_invented(self):
        def add(root):
            node = next(node for node in root.iter('{' + oracle.W + '}sdt')
                        if node.find('w:sdtPr/w:id', oracle.NS).get('{' + oracle.W + '}val') == '105')
            ET.SubElement(node, '{' + oracle.W + '}sdtContent')
        self.mutate(add)

    def test_nested_control_cannot_move_outside_parent(self):
        def move(root):
            outer = root.find('.//w:sdt/w:sdtContent', oracle.NS)
            nested = outer.find('w:sdt', oracle.NS)
            outer.remove(nested)
            root.find('w:body', oracle.NS).insert(0, nested)
        self.mutate(move)

    def test_inside_text_cannot_change(self):
        self.mutate(lambda root: setattr(root.find('.//w:sdt/w:sdtContent/w:p/w:r/w:t', oracle.NS), 'text', 'Lost'))


if __name__ == '__main__':
    unittest.main()
