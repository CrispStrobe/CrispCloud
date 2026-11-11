"""Positive controls and deliberate OOXML losses for the table border oracle."""
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import table_borders_oracle as oracle


class TableBordersOracleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.output = self.folder / 'mutated.docx'
        self.expected = json.loads((oracle.FIXTURES / 'table_borders_expected.json').read_text())
        with ZipFile(oracle.FIXTURES / 'table-borders.docx') as package:
            self.parts = {name: package.read(name) for name in package.namelist()}

    def write(self):
        with ZipFile(self.output, 'w') as package:
            for name, content in self.parts.items():
                package.writestr(name, content)

    @staticmethod
    def borders(value, color=None, size=None):
        node = ET.Element('{' + oracle.W + '}tblBorders')
        for edge in oracle.EDGES:
            attributes = {'{' + oracle.W + '}val': value}
            if color is not None:
                attributes['{' + oracle.W + '}color'] = color
            if size is not None:
                attributes['{' + oracle.W + '}sz'] = str(size)
            ET.SubElement(node, '{' + oracle.W + '}' + edge, attributes)
        return node

    def mutate(self, part, operation):
        tree = ET.fromstring(self.parts[part])
        operation(tree)
        self.parts[part] = ET.tostring(tree)

    def reject(self, part, operation, mode='imported'):
        self.mutate(part, operation)
        self.write()
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.output, self.expected, mode)

    @staticmethod
    def properties(tree, index=0):
        return list(tree.iter('{' + oracle.W + '}tbl'))[index].find('w:tblPr', oracle.NS)

    def authored_edits(self):
        def body(tree):
            self.properties(tree, 0).insert(1, self.borders('single', '224466', 12))
            self.properties(tree, 1).append(self.borders('nil'))
        self.mutate('word/document.xml', body)
        self.mutate('word/footnotes.xml', lambda tree:
                    self.properties(tree).append(self.borders('single', '996633', 6)))

    def test_authored_source_is_a_positive_control(self):
        oracle.verify_file(oracle.FIXTURES / 'table-borders.docx', self.expected, 'imported')

    def test_independently_authored_edits_are_a_positive_control(self):
        self.authored_edits()
        self.write()
        oracle.verify_file(self.output, self.expected, 'edited')

    def test_absent_borders_cannot_turn_into_default_black(self):
        self.reject('word/document.xml', lambda tree:
                    self.properties(tree).insert(1, self.borders('single', '000000', 4)))

    def test_inherited_borders_cannot_be_flattened_into_direct_formatting(self):
        self.reject('word/document.xml', lambda tree:
                    self.properties(tree, 1).append(self.borders('single', 'CC0000', 8)))

    def test_nil_override_cannot_disappear_and_reenable_style(self):
        def remove(tree):
            properties = self.properties(tree, 2)
            properties.remove(properties.find('w:tblBorders', oracle.NS))
        self.reject('word/document.xml', remove)

    def test_inherited_style_color_cannot_change(self):
        self.reject('word/styles.xml', lambda tree:
                    tree.find('w:style/w:tblPr/w:tblBorders/w:top', oracle.NS).set(
                        '{' + oracle.W + '}color', '000000'))

    def test_table_style_reference_cannot_disappear(self):
        def remove(tree):
            properties = self.properties(tree, 1)
            properties.remove(properties.find('w:tblStyle', oracle.NS))
        self.reject('word/document.xml', remove)

    def test_retained_caption_cannot_disappear(self):
        def remove(tree):
            properties = self.properties(tree)
            properties.remove(properties.find('w:tblCaption', oracle.NS))
        self.reject('word/document.xml', remove)

    def test_retained_width_cannot_change(self):
        self.reject('word/document.xml', lambda tree:
                    self.properties(tree).find('w:tblW', oracle.NS).set('{' + oracle.W + '}w', '3601'))

    def test_retained_layout_cannot_change(self):
        self.reject('word/document.xml', lambda tree:
                    self.properties(tree).find('w:tblLayout', oracle.NS).set('{' + oracle.W + '}type', 'autofit'))

    def test_retained_cell_margin_cannot_change(self):
        self.reject('word/document.xml', lambda tree:
                    self.properties(tree).find('w:tblCellMar/w:top', oracle.NS).set('{' + oracle.W + '}w', '0'))

    def test_note_table_cannot_gain_default_borders(self):
        self.reject('word/footnotes.xml', lambda tree:
                    self.properties(tree).append(self.borders('single', '000000', 4)))

    def test_edited_border_color_cannot_revert(self):
        self.authored_edits()
        self.reject('word/document.xml', lambda tree:
                    self.properties(tree).find('w:tblBorders/w:top', oracle.NS).set(
                        '{' + oracle.W + '}color', '000000'), 'edited')

    def test_edited_border_width_cannot_be_lost(self):
        self.authored_edits()
        self.reject('word/footnotes.xml', lambda tree:
                    self.properties(tree).find('w:tblBorders/w:top', oracle.NS).set(
                        '{' + oracle.W + '}sz', '4'), 'edited')

    def test_edited_off_requires_direct_nil_override(self):
        self.authored_edits()
        def remove(tree):
            properties = self.properties(tree, 1)
            properties.remove(properties.find('w:tblBorders', oracle.NS))
        self.reject('word/document.xml', remove, 'edited')

    def test_partial_border_set_cannot_pass(self):
        def remove(tree):
            borders = self.properties(tree, 2).find('w:tblBorders', oracle.NS)
            borders.remove(borders[-1])
        self.reject('word/document.xml', remove)

    def test_sparse_properties_cannot_gain_unrelated_alignment(self):
        self.reject('word/document.xml', lambda tree: self.properties(tree).insert(
            1, ET.Element('{' + oracle.W + '}jc', {'{' + oracle.W + '}val': 'left'})))

    def test_missing_whole_group_fails_before_file_checks(self):
        for cycle in (1, 2, 3):
            (self.folder / f'tables-imported-{cycle}.docx').write_bytes(b'placeholder')
        with self.assertRaisesRegex(AssertionError, 'Table corpus inventory'):
            oracle.verify_corpus(self.folder, self.expected)

    def test_empty_corpus_fails(self):
        with self.assertRaisesRegex(AssertionError, 'Table corpus inventory'):
            oracle.verify_corpus(self.folder, self.expected)


if __name__ == '__main__':
    unittest.main()
