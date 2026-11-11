"""Mutation controls prove that the host schema gate cannot validate a subset."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile

import office_host_evidence as evidence


class HostEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def populate(self, base=None):
        base = base or self.root
        for name in evidence.expected_paths():
            file = base / name
            file.parent.mkdir(parents=True, exist_ok=True)
            with ZipFile(file, 'w') as archive:
                archive.writestr('word/document.xml', '<document/>')
        return base

    def test_complete_tree_has_hashes_for_every_expected_export(self):
        self.populate()
        report = evidence.inspect(self.root)
        self.assertEqual(report['failures'], [])
        self.assertEqual(report['verified'], 14)
        for entry in report['files']:
            self.assertEqual(entry['sha256'], hashlib.sha256(
                (self.root / entry['path']).read_bytes()).hexdigest())

    def test_artifact_download_wrapper_preserves_complete_relative_paths(self):
        self.populate(self.root / 'downloaded-artifact')
        report = evidence.inspect(self.root)
        self.assertEqual(report['failures'], [])
        self.assertEqual(report['verified'], 14)

    def test_missing_upload_or_controller_output_fails(self):
        for name in (evidence.expected_paths()[0], evidence.expected_paths()[-1]):
            with self.subTest(name=name):
                self.populate()
                (self.root / name).unlink()
                self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_duplicate_complete_artifacts_fail(self):
        self.populate(self.root / 'first')
        self.populate(self.root / 'second')
        self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_extra_output_and_invalid_zip_fail(self):
        self.populate()
        extra = self.root / 'build/fidelity-host/unreviewed.docx'
        extra.write_bytes(b'unreviewed')
        self.assertTrue(evidence.inspect(self.root)['failures'])
        extra.unlink()
        (self.root / evidence.expected_paths()[0]).write_bytes(b'not a zip')
        self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_external_file_cannot_satisfy_an_artifact(self):
        self.populate()
        file = self.root / evidence.expected_paths()[0]
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / 'outside.docx'
            external.write_bytes(file.read_bytes())
            file.unlink()
            file.symlink_to(external)
            self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_clean_only_removes_manifest_outputs_and_receipt(self):
        self.populate()
        receipt = self.root / evidence.REPORT
        receipt.write_text('{}')
        unrelated = self.root / 'build/fidelity-host/keep.txt'
        unrelated.write_text('retained')
        evidence.clean(self.root)
        self.assertFalse(receipt.exists())
        self.assertTrue(all(not (self.root / p).exists() for p in evidence.expected_paths()))
        self.assertEqual(unrelated.read_text(), 'retained')

    def test_clean_preflights_later_symlink_before_deleting_any_evidence(self):
        self.populate()
        last = self.root / evidence.expected_paths()[-1]
        original = last.read_bytes()
        last.unlink()
        last.parent.rmdir()
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / last.name
            external.write_bytes(original)
            last.parent.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                evidence.clean(self.root)
            self.assertTrue((self.root / evidence.expected_paths()[0]).exists())
            self.assertEqual(external.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
