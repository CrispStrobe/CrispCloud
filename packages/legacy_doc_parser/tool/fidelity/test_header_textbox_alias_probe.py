# SPDX-License-Identifier: MPL-2.0
import copy
from pathlib import Path
import tempfile
import unittest
import zipfile

from header_textbox_alias_probe import check_occurrences, header_occurrences
from textbox_boundary_probe import REL, W, authored_control


class HeaderTextboxAliasOracleTest(unittest.TestCase):
    def example(self):
        return {'titlePage': False, 'unreferencedBoxes': [], 'headers': {
            kind: {'part': f'word/{kind}.xml', 'boxes': [{'paragraphs': ['ALPHA', '']}]}
            for kind in ('default', 'first')}}

    def test_two_separate_occurrences_pass_without_activating_first_header(self):
        value = self.example()
        self.assertEqual(check_occurrences(value, ['ALPHA', ''], title_page=False, require_first=True), [])
        self.assertTrue(check_occurrences(value, ['ALPHA'], title_page=False, require_first=True))

    def test_missing_first_header_is_not_hidden_by_a_duplicate_default_box(self):
        value = self.example()
        del value['headers']['first']
        value['headers']['default']['boxes'] *= 2
        errors = check_occurrences(value, ['ALPHA', ''], title_page=False, require_first=True)
        self.assertTrue(any('default' in error for error in errors))
        self.assertTrue(any('missing first' in error for error in errors))

    def test_activation_unreferenced_and_even_boxes_each_fail(self):
        for mutation in ('activation', 'orphan', 'even'):
            value = self.example()
            if mutation == 'activation':
                value['titlePage'] = True
            elif mutation == 'orphan':
                value['unreferencedBoxes'] = [{'paragraphs': ['ALPHA', '']}]
            else:
                value['headers']['even'] = copy.deepcopy(value['headers']['first'])
            with self.subTest(mutation=mutation):
                self.assertTrue(check_occurrences(value, ['ALPHA', ''], title_page=False, require_first=True))

    def test_empty_box_requires_a_real_empty_paragraph_in_each_occurrence(self):
        value = self.example()
        for header in value['headers'].values():
            header['boxes'][0]['paragraphs'] = ['']
        self.assertEqual(check_occurrences(value, [''], title_page=False, require_first=True), [])
        value['headers']['first']['boxes'][0]['paragraphs'] = []
        self.assertTrue(check_occurrences(value, [''], title_page=False, require_first=True))

    def test_relationships_identify_the_header_without_equal_text_deduplication(self):
        with tempfile.TemporaryDirectory() as temp:
            original, both = Path(temp) / 'original.docx', Path(temp) / 'both.docx'
            authored_control(original, ['ALPHA'], header=True)
            self.assertEqual(check_occurrences(header_occurrences(original), ['ALPHA'], title_page=False, require_first=False), [])
            with zipfile.ZipFile(original) as source, zipfile.ZipFile(both, 'x') as destination:
                for name in source.namelist():
                    value = source.read(name)
                    if name == 'word/document.xml':
                        value = value.replace(b'<w:sectPr>', b'<w:sectPr><w:headerReference w:type="first" r:id="header2"/>')
                    elif name == 'word/_rels/document.xml.rels':
                        value = value.replace(b'</Relationships>',
                            f'<Relationship Id="header2" Type="{REL}/header" Target="header2.xml"/></Relationships>'.encode())
                    destination.writestr(name, value)
                destination.writestr('word/header2.xml', source.read('word/header1.xml'))
            observation = header_occurrences(both)
            self.assertEqual(set(observation['headers']), {'default', 'first'})
            self.assertEqual(check_occurrences(observation, ['ALPHA'], title_page=False, require_first=True), [])

    def test_duplicate_header_references_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            original, duplicate = Path(temp) / 'original.docx', Path(temp) / 'duplicate.docx'
            authored_control(original, [''], header=True)
            with zipfile.ZipFile(original) as source, zipfile.ZipFile(duplicate, 'x') as destination:
                for name in source.namelist():
                    value = source.read(name)
                    if name == 'word/document.xml':
                        value = value.replace(b'<w:sectPr>', b'<w:sectPr><w:headerReference w:type="default" r:id="header1"/>')
                    destination.writestr(name, value)
            with self.assertRaisesRegex(ValueError, 'duplicate header'):
                header_occurrences(duplicate)


if __name__ == '__main__':
    unittest.main()
