import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from generate_storage_notices import check
import generate_storage_notices as storage


class NoticeGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        manifest = json.loads(storage.MANIFEST.read_text())
        for name in manifest['inputs']:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(storage.STORAGE / name, target)
        shutil.copyfile(storage.OUTPUT, root / 'NOTICES')
        shutil.copyfile(storage.MANIFEST, root / 'licensing/bundled_notices.json')
        self.root = root
        for name, value in [('STORAGE', root), ('OUTPUT', root / 'NOTICES'), ('MANIFEST', root / 'licensing/bundled_notices.json')]:
            patcher = patch.object(storage, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_missing_dependency_is_rejected_even_with_intact_text(self):
        path = self.root / 'licensing/bundled_notices.json'
        manifest = json.loads(path.read_text())
        manifest['packages'].pop()
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'Missing native licence'):
            check()

    def test_truncated_notice_is_rejected(self):
        (self.root / 'NOTICES').write_text('Native dependencies use permissive licences.')
        with self.assertRaisesRegex(ValueError, 'drifted'):
            check()

    def test_lock_update_requires_review(self):
        with (self.root / 'rust/Cargo.lock').open('a') as f:
            f.write('\n# an updated graph\n')
        with self.assertRaisesRegex(ValueError, 'drifted'):
            check()


if __name__ == '__main__':
    unittest.main()
