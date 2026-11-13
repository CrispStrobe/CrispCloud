import hashlib
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
        paths += ['notices/' + r['file'] for r in manifest['notices']]
        paths += [r['path'] for r in manifest['distributionNotices']]
        paths += [r['path'] for key in ('overlays', 'correspondingSource')
                  for r in manifest[key]]
        for name in paths:
            target = self.package / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(verifier.PACKAGE / name, target)

    def test_reviewed_payload_matches(self):
        self.assertGreater(verifier.verify(self.package), 100)

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

    def test_altered_distribution_notice_rejected(self):
        path = self.package / 'assets/licenses/THIRD_PARTY.txt'
        path.write_bytes(path.read_bytes() + b'altered')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            verifier.verify(self.package)

    def test_missing_original_notice_rejected(self):
        manifest = json.loads((self.package / 'RUNTIME_MANIFEST.json').read_text())
        (self.package / 'notices' / manifest['notices'][0]['file']).unlink()
        with self.assertRaisesRegex(ValueError, 'Missing or unsafe'):
            verifier.verify(self.package)

    def test_unlisted_bundled_notice_rejected(self):
        (self.package / 'assets/licenses/duplicate.txt').write_text('extra')
        with self.assertRaisesRegex(ValueError, 'inventory mismatch'):
            verifier.verify(self.package)

    def test_rehashed_aggregate_cannot_omit_a_grant(self):
        manifest = json.loads((self.package / 'RUNTIME_MANIFEST.json').read_text())
        original = (self.package / 'notices' / manifest['notices'][0]['file']).read_bytes()
        path = self.package / 'assets/licenses/THIRD_PARTY.txt'
        content = path.read_bytes().replace(original, b'')
        path.write_bytes(content)
        self._update_distribution_hash(manifest, path, content)
        with self.assertRaisesRegex(ValueError, 'omits complete original notice'):
            verifier.verify(self.package)

    def test_rehashed_aggregate_cannot_omit_an_alias_attribution(self):
        manifest = json.loads((self.package / 'RUNTIME_MANIFEST.json').read_text())
        shared = next(r for r in manifest['notices'] if len(r['sources']) > 1)
        alias = shared['sources'][1]
        attribution = f"Source: {alias['name']} ({alias['source']})\n".encode()
        path = self.package / 'assets/licenses/THIRD_PARTY.txt'
        content = path.read_bytes().replace(attribution, b'')
        path.write_bytes(content)
        self._update_distribution_hash(manifest, path, content)
        with self.assertRaisesRegex(ValueError, 'omits original notice attribution'):
            verifier.verify(self.package)

    def _update_distribution_hash(self, manifest, path, content):
        record = next(r for r in manifest['distributionNotices']
                      if r['path'] == path.relative_to(self.package).as_posix())
        record['bytes'] = len(content)
        record['sha256'] = hashlib.sha256(content).hexdigest()
        data = json.dumps(manifest).encode()
        (self.package / 'RUNTIME_MANIFEST.json').write_bytes(data)
        (self.package / 'assets/runtime/manifest.json').write_bytes(data)


if __name__ == '__main__':
    unittest.main()
