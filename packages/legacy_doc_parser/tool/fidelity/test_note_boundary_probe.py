# SPDX-License-Identifier: MPL-2.0
from pathlib import Path
import tempfile
import unittest
import zipfile

from note_boundary_probe import (
    CONTROLS, KINDS, SOURCE, W, authored_control, block_changes, content,
    expected_blocks, note_snapshot, writer_preserves_blocks,
)


class NoteBoundaryProbeTest(unittest.TestCase):
    def test_authored_matrix_keeps_literal_blank_counts_and_table_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            for kind in KINDS:
                for name in CONTROLS:
                    with self.subTest(kind=kind, name=name):
                        path = Path(temporary) / f'{kind}-{name}.docx'
                        authored_control(path, kind, name)
                        observed = note_snapshot(path, kind)
                        self.assertEqual(content(observed), [expected_blocks(name)])
                        self.assertEqual(observed['notes'][0]['markerCount'], 1)
                        self.assertEqual(observed['notes'][0]['textboxCount'], 0)
            self.assertEqual((Path(temporary) / 'footnote-table.docx').read_bytes(), SOURCE.read_bytes())

    def test_endnote_control_changes_reference_relationship_and_content_type(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'endnote.docx'
            authored_control(path, 'endnote', 'table-blank')
            with zipfile.ZipFile(path) as package:
                self.assertIn('word/endnotes.xml', package.namelist())
                self.assertNotIn('word/footnotes.xml', package.namelist())
                for name in ('word/document.xml', 'word/_rels/document.xml.rels', '[Content_Types].xml'):
                    self.assertIn(b'endnote', package.read(name))
                    self.assertNotIn(b'footnote', package.read(name))

    def test_added_or_removed_source_blank_fails_writer_preservation(self):
        source = expected_blocks('table-blank')
        parsed = {'stories': [{'blocks': source}]}
        emitted = {'notes': [{'blocks': source, 'markerCount': 1, 'textboxCount': 0}]}
        self.assertTrue(writer_preserves_blocks(parsed, emitted))
        for changed in (source[:-1], source + [{'kind': 'p', 'text': ''}]):
            altered = {'notes': [{'blocks': changed, 'markerCount': 1, 'textboxCount': 0}]}
            self.assertFalse(writer_preserves_blocks(parsed, altered))
            self.assertTrue(block_changes(emitted, altered))

    def test_missing_story_marker_or_empty_paragraph_cannot_pass(self):
        parsed = {'stories': [{'blocks': expected_blocks('empty')}]}
        for emitted in ({'notes': []}, {'notes': [{'blocks': [], 'markerCount': 1, 'textboxCount': 0}]},
                        {'notes': [{'blocks': expected_blocks('empty'), 'markerCount': 0, 'textboxCount': 0}]}):
            self.assertFalse(writer_preserves_blocks(parsed, emitted))
        self.assertFalse(writer_preserves_blocks({'stories': []}, {'notes': []}))

    def test_native_interior_paragraph_is_reported_before_following_text(self):
        expected = expected_blocks('table-text')
        native = [*expected[:2], {'kind': 'p', 'text': ''}, expected[-1]]
        before = {'notes': [{'blocks': expected}]}
        after = {'notes': [{'blocks': native}]}
        difference = block_changes(before, after)
        self.assertEqual(difference[0]['before'], [expected])
        self.assertEqual(difference[0]['after'], [native])
        self.assertEqual(difference[0]['after'][0][-1]['text'], 'TAIL')

    def test_alternate_native_frame_is_selected_once_and_remains_distinct_from_table(self):
        paragraph = '<w:p><w:r><w:t>FRAME</w:t></w:r></w:p>'
        textbox = '<w:r><w:pict><w:txbxContent>' + paragraph + '</w:txbxContent></w:pict></w:r>'
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'frame.docx'
            with zipfile.ZipFile(path, 'x') as package:
                package.writestr('word/footnotes.xml', f'<w:footnotes xmlns:w="{W}" '
                    'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
                    'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
                    '<w:footnote w:id="1"><w:p><w:r><w:footnoteRef/></w:r>'
                    '<mc:AlternateContent><mc:Choice Requires="wps">' + textbox + '</mc:Choice>'
                    '<mc:Fallback>' + textbox + '</mc:Fallback></mc:AlternateContent>'
                    '</w:p></w:footnote></w:footnotes>')
            observed = note_snapshot(path, 'footnote')
            self.assertEqual(content(observed), [[{'kind': 'p', 'text': 'FRAME'}]])
            self.assertEqual(observed['notes'][0]['textboxCount'], 1)
            self.assertEqual(len(observed['alternateContent']), 1)
            self.assertFalse(writer_preserves_blocks({'stories': [{'blocks': content(observed)[0]}]}, observed))


if __name__ == '__main__':
    unittest.main()
