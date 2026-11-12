# SPDX-License-Identifier: MPL-2.0
from pathlib import Path
import tempfile
import unittest
import zipfile

from textbox_boundary_probe import W, authored_control, boxes, matches_paragraphs


class TextboxBoundaryOracleTest(unittest.TestCase):
    def package(self, path, xml):
        with zipfile.ZipFile(path, 'x') as package:
            package.writestr('word/document.xml', xml)

    def test_authored_empty_and_trailing_blank_paragraphs_are_distinct(self):
        with tempfile.TemporaryDirectory() as temp:
            for index, expected in enumerate(([''], ['ALPHA'], ['ALPHA', ''], ['ALPHA', '', ''])):
                path = Path(temp) / f'{index}.docx'
                authored_control(path, expected)
                observation = boxes(path)
                self.assertTrue(matches_paragraphs(observation, expected))
                self.assertFalse(matches_paragraphs(observation, expected + ['']))

    def test_header_control_keeps_one_empty_paragraph(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'header.docx'
            authored_control(path, [''], header=True)
            observation = boxes(path)
            self.assertEqual(observation['boxes'][0]['part'], 'word/header1.xml')
            self.assertTrue(matches_paragraphs(observation, ['']))

    def test_alternate_content_selects_one_branch_without_deduplicating_real_boxes(self):
        content = '<w:txbxContent><w:p><w:r><w:t>ALPHA</w:t></w:r></w:p></w:txbxContent>'
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'choice.docx'
            self.package(path, f'<w:document xmlns:w="{W}" '
                         'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
                         'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
                         '<mc:AlternateContent><mc:Choice Requires="wps">' + content + '</mc:Choice>'
                         '<mc:Fallback>' + content + '</mc:Fallback></mc:AlternateContent></w:document>')
            observation = boxes(path)
            self.assertTrue(matches_paragraphs(observation, ['ALPHA']))
            self.assertEqual(observation['alternateContent'][0]['selected'], 'choice')
            path = Path(temp) / 'duplicate.docx'
            self.package(path, f'<w:document xmlns:w="{W}">{content}{content}</w:document>')
            self.assertFalse(matches_paragraphs(boxes(path), ['ALPHA']))

    def test_a_missing_textbox_or_paragraph_does_not_pass_an_empty_control(self):
        self.assertFalse(matches_paragraphs({'boxes': []}, ['']))
        self.assertFalse(matches_paragraphs({'boxes': [{'paragraphs': []}]}, ['']))


if __name__ == '__main__':
    unittest.main()
