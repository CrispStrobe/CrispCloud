"""Reject damaged or incomplete evidence, including valid ZIP containers."""
import io
import unittest
import warnings
from zipfile import ZipFile

import verify


class ArchiveIntegrityTest(unittest.TestCase):
    def setUp(self):
        self.data = b'preserved Office bytes'
        self.manifest = {'output.docx': {
            'bytes': len(self.data), 'sha256': verify.digest(self.data)}}

    def archive(self, entries):
        output = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with ZipFile(output, 'w') as archive:
                archive.writestr('archive-manifest.json', b'{}')
                for name, data in entries:
                    archive.writestr(name, data)
        return output.getvalue()

    def test_exact_inventory_and_content_pass(self):
        with verify.verify_zip(self.archive([('output.docx', self.data)]), self.manifest):
            pass

    def test_changed_content_in_valid_zip_fails(self):
        with self.assertRaisesRegex(ValueError, 'content mismatch'):
            verify.verify_zip(self.archive([('output.docx', self.data.upper())]), self.manifest)

    def test_missing_file_fails(self):
        with self.assertRaisesRegex(ValueError, 'inventory differs'):
            verify.verify_zip(self.archive([]), self.manifest)

    def test_unrecorded_file_fails(self):
        with self.assertRaisesRegex(ValueError, 'inventory differs'):
            verify.verify_zip(self.archive([('output.docx', self.data), ('extra', b'')]), self.manifest)

    def test_duplicate_member_fails(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate archive'):
            verify.verify_zip(self.archive([('output.docx', self.data)] * 2), self.manifest)

    def test_reported_byte_length_is_checked(self):
        self.manifest['output.docx']['bytes'] += 1
        with self.assertRaisesRegex(ValueError, 'content mismatch'):
            verify.verify_zip(self.archive([('output.docx', self.data)]), self.manifest)


if __name__ == '__main__':
    unittest.main()
