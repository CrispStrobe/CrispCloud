import json
from pathlib import Path
import shutil
import tempfile
import unittest

import verify_document_runtime as verifier


class RuntimeRetentionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.package = Path(temporary.name)
        manifest = json.loads((verifier.PACKAGE / 'RUNTIME_MANIFEST.json').read_text())
        paths = ['RUNTIME_MANIFEST.json', 'assets/runtime/manifest.json',
                 'assets/licenses/THIRD_PARTY.txt']
        paths += ['assets/runtime/' + r['path'] for r in manifest['assets']]
        paths += ['assets/licenses/' + r['file'] for r in manifest['notices']]
        paths += [r['path'] for key in ('overlays', 'correspondingSource')
                  for r in manifest[key]]
        for name in paths:
            target = self.package / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(verifier.PACKAGE / name, target)

    def test_reviewed_payload_matches(self):
        self.assertEqual(verifier.verify(self.package), 174)

    def test_altered_runtime_rejected(self):
        manifest = json.loads((self.package / 'RUNTIME_MANIFEST.json').read_text())
        path = self.package / 'assets/runtime' / manifest['assets'][0]['path']
        path.write_bytes(path.read_bytes() + b'!')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            verifier.verify(self.package)

    def test_missing_matching_source_rejected(self):
        manifest = json.loads((self.package / 'RUNTIME_MANIFEST.json').read_text())
        (self.package / manifest['correspondingSource'][0]['path']).unlink()
        with self.assertRaisesRegex(ValueError, 'Missing or unsafe'):
            verifier.verify(self.package)

    def test_unreviewed_runtime_rejected(self):
        (self.package / 'assets/runtime/unreviewed.js').write_text('alert(1)')
        with self.assertRaisesRegex(ValueError, 'inventory mismatch'):
            verifier.verify(self.package)


if __name__ == '__main__':
    unittest.main()
