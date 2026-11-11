"""Negative controls prove the independent story-media oracle fails closed."""
import tempfile
from pathlib import Path
import unittest

from corpus import FIXTURES, read_zip
from story_media_oracle import verify_document, verify_directory


class StoryMediaOracleTests(unittest.TestCase):
    def setUp(self):
        self.parts = read_zip(FIXTURES / 'story-media.docx')

    def test_authored_source_matches_pixel_and_story_expectations(self):
        verify_document(self.parts)

    def test_missing_exports_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(AssertionError, 'missing='):
                verify_directory(Path(folder))

    def test_deleted_header_picture_is_rejected(self):
        self.parts['word/header11.xml'] = self.parts['word/header11.xml'].replace(b'<w:drawing>', b'<w:discarded>').replace(b'</w:drawing>', b'</w:discarded>')
        with self.assertRaisesRegex(AssertionError, 'wrong, missing or cross-wired'):
            verify_document(self.parts)

    def test_same_relationship_id_in_wrong_story_cannot_pass(self):
        self.parts['word/_rels/header11.xml.rels'] = self.parts['word/_rels/header11.xml.rels'].replace(b'media/image1.png', b'media/body.png')
        with self.assertRaisesRegex(AssertionError, 'default header'):
            verify_document(self.parts)

    def test_changed_note_pixels_are_rejected(self):
        self.parts['word/media/note.png'] = self.parts['word/media/body.png']
        with self.assertRaisesRegex(AssertionError, 'Note picture'):
            verify_document(self.parts)

    def test_blank_story_paragraph_accumulation_is_rejected(self):
        self.parts['word/header11.xml'] = self.parts['word/header11.xml'].replace(b'</w:hdr>', b'<w:p/></w:hdr>')
        with self.assertRaisesRegex(AssertionError, 'blank paragraphs'):
            verify_document(self.parts)

    def test_wrong_media_mime_is_rejected(self):
        self.parts['[Content_Types].xml'] = self.parts['[Content_Types].xml'].replace(b'ContentType="image/png"', b'ContentType="image/jpeg"')
        with self.assertRaisesRegex(AssertionError, 'content type'):
            verify_document(self.parts)

    def test_retained_chart_overwrite_is_rejected(self):
        self.parts['word/charts/chart1.xml'] = self.parts['word/charts/chart1.xml'].replace(b'<c:layout/>', b'<c:layout><c:manualLayout/></c:layout>')
        with self.assertRaisesRegex(AssertionError, 'Retained consumer payload'):
            verify_document(self.parts)


if __name__ == '__main__':
    unittest.main()
