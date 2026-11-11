"""Independent positive and negative controls for retained opaque Word blocks."""
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from altchunk_oracle import verify_document, verify_directory
from corpus import FIXTURES, NS, W, read_zip


class AltChunkOracleTests(unittest.TestCase):
    def setUp(self):
        self.parts = read_zip(FIXTURES / 'word-altchunk.docx')

    def verify(self):
        return verify_document(self.parts, edited=False)

    def test_authored_input_is_an_independent_positive_control(self):
        self.verify()

    def test_missing_outputs_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(AssertionError, 'missing='):
                verify_directory(folder)

    def test_extra_outputs_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, 'unexpected.docx').write_bytes(b'')
            with self.assertRaisesRegex(AssertionError, 'unexpected.docx'):
                verify_directory(folder)

    def test_dropped_opaque_block_is_rejected(self):
        root = ET.fromstring(self.parts['word/document.xml'])
        body = root.find('w:body', NS)
        body.remove(body.find('w:altChunk', NS))
        self.parts['word/document.xml'] = ET.tostring(root)
        with self.assertRaisesRegex(AssertionError, 'Body chunk order'):
            self.verify()

    def test_same_id_in_the_wrong_story_is_rejected(self):
        name = 'word/_rels/footnotes.xml.rels'
        self.parts[name] = self.parts[name].replace(b'../payload/note.html', b'../payload/body.html')
        with self.assertRaisesRegex(AssertionError, 'Note chunk order/owner'):
            self.verify()

    def test_changed_payload_bytes_are_rejected(self):
        self.parts['payload/body.html'] += b'<p>unexpected edit</p>'
        with self.assertRaisesRegex(AssertionError, 'payload bytes'):
            self.verify()

    def test_deleted_payload_is_rejected(self):
        del self.parts['payload/cell.html']
        with self.assertRaisesRegex(AssertionError, 'payload/cell.html'):
            self.verify()

    def test_wrong_payload_content_type_is_rejected(self):
        self.parts['[Content_Types].xml'] = self.parts['[Content_Types].xml'].replace(b'ContentType="text/html"', b'ContentType="text/plain"')
        with self.assertRaisesRegex(AssertionError, 'content type'):
            self.verify()

    def test_omitted_source_format_properties_are_rejected(self):
        root = ET.fromstring(self.parts['word/document.xml'])
        chunk = root.find('w:body/w:altChunk', NS)
        chunk.remove(chunk.find('w:altChunkPr', NS))
        self.parts['word/document.xml'] = ET.tostring(root)
        with self.assertRaisesRegex(AssertionError, 'source-format'):
            self.verify()

    def test_changed_relationship_kind_is_rejected(self):
        self.parts['word/_rels/document.xml.rels'] = self.parts['word/_rels/document.xml.rels'].replace(b'/aFChunk', b'/hyperlink', 1)
        with self.assertRaisesRegex(AssertionError, 'relationship type'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
