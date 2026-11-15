import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import with_ci_apple_sqlite as module


class AppleSqliteWrapperTests(unittest.TestCase):
    def fixture(self, root, newline=b'\n'):
        original = (b'name: fixture\nhooks:\n  user_defines:\n'
                    b'    crisp_storage:\n      rust_smb: true\n').replace(b'\n', newline)
        (root / 'pubspec.yaml').write_bytes(original)
        (root / 'pubspec.lock').write_text('packages:\n  sqlite3:\n    version: "3.3.3"\n')
        directory = root / module.DIRECTORY
        directory.mkdir(parents=True)
        payload = b'fixture library bytes'
        (directory / 'fixture.dylib').write_bytes(payload)
        return original, {'fixture.dylib': hashlib.sha256(payload).hexdigest()}

    def test_child_uses_local_assets_retains_rust_hook_and_restores_exact_bytes(self):
        for newline in (b'\n', b'\r\n'):
            for status in (0, 7):
                with self.subTest(newline=newline, status=status), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    original, assets = self.fixture(root, newline)
                    command = [sys.executable, '-c',
                               'from pathlib import Path; import sys; '
                               's=Path("pubspec.yaml").read_text(); '
                               'assert "source: test-sqlite3" in s; '
                               'assert "directory: .dart_tool/apple-sqlite-assets/" in s; '
                               'assert "rust_smb: true" in s; '
                               f'sys.exit({status})']
                    with patch.object(module, 'ASSETS', assets):
                        self.assertEqual(module.run_with_apple_sqlite(command, root), status)
                    self.assertEqual((root / 'pubspec.yaml').read_bytes(), original)

    def test_missing_or_changed_assets_fail_before_launch_and_manifest_write(self):
        for change in ('missing', 'changed'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                original, assets = self.fixture(root)
                file = root / module.DIRECTORY / 'fixture.dylib'
                if change == 'missing':
                    file.unlink()
                else:
                    file.write_bytes(b'changed bytes')
                with patch.object(module, 'ASSETS', assets), patch.object(subprocess, 'run') as run:
                    with self.assertRaisesRegex(RuntimeError, 'pinned Apple SQLite'):
                        module.run_with_apple_sqlite(['child'], root)
                    run.assert_not_called()
                self.assertEqual((root / 'pubspec.yaml').read_bytes(), original)

    def test_changed_dependency_version_cannot_reuse_the_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original, assets = self.fixture(root)
            (root / 'pubspec.lock').write_text('packages:\n  sqlite3:\n    version: "4.0.0"\n')
            with patch.object(module, 'ASSETS', assets), patch.object(subprocess, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'reviewed sqlite3'):
                    module.run_with_apple_sqlite(['child'], root)
                run.assert_not_called()
            self.assertEqual((root / 'pubspec.yaml').read_bytes(), original)

    def test_existing_sqlite_configuration_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original, assets = self.fixture(root)
            original += b'    sqlite3:\n      source: system\n'
            (root / 'pubspec.yaml').write_bytes(original)
            with patch.object(module, 'ASSETS', assets), patch.object(subprocess, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'Existing sqlite3'):
                    module.run_with_apple_sqlite(['child'], root)
                run.assert_not_called()
            self.assertEqual((root / 'pubspec.yaml').read_bytes(), original)

    def test_start_failure_and_interruptions_restore_original_configuration(self):
        for failure in (OSError('start failed'), KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(failure=type(failure).__name__), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                original, assets = self.fixture(root)
                with patch.object(module, 'ASSETS', assets), patch.object(subprocess, 'run', side_effect=failure):
                    with self.assertRaises(type(failure)):
                        module.run_with_apple_sqlite(['child'], root)
                self.assertEqual((root / 'pubspec.yaml').read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
