import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ci_sqlite', Path(__file__).with_name('with_ci_system_sqlite.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

STORAGE_HOOK = (b'hooks: # retain existing native hooks\n'
                b'  user_defines:\n'
                b'    crisp_storage:\n'
                b'      rust_smb: true\n')


class SystemSqliteWrapperTests(unittest.TestCase):
    def test_child_sees_documented_hook_and_original_is_restored_on_success_and_failure(self):
        for exit_code in (0, 7):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as directory:
                pubspec = Path(directory) / 'pubspec.yaml'
                original = b'name: fixture\r\ndependencies:\r\n  sqlite3: 3.3.3\r\n'
                pubspec.write_bytes(original)
                child = ("from pathlib import Path; import sys; "
                         "s=Path('pubspec.yaml').read_text(); "
                         "assert 'source: system' in s; "
                         "assert 'name_windows: winsqlite3' in s; "
                         f"sys.exit({exit_code})")
                self.assertEqual(module.run_with_system_sqlite([sys.executable, '-c', child], pubspec), exit_code)
                self.assertEqual(pubspec.read_bytes(), original)

    def test_existing_storage_hook_is_preserved_and_restored(self):
        for newline in (b'\n', b'\r\n'):
            for exit_code in (0, 7):
                with self.subTest(newline=newline, exit_code=exit_code), tempfile.TemporaryDirectory() as directory:
                    pubspec = Path(directory) / 'pubspec.yaml'
                    before = b'name: fixture\n' + STORAGE_HOOK
                    after = b'  other_config:\n    enabled: true\nflutter:\n  generate: true\n'
                    original = (before + after).replace(b'\n', newline)
                    expected = (before + module.SQLITE_HOOK + after).replace(b'\n', newline)
                    pubspec.write_bytes(original)
                    child = ("from pathlib import Path; import sys; "
                             f"assert Path('pubspec.yaml').read_bytes() == {expected!r}; "
                             f"sys.exit({exit_code})")
                    self.assertEqual(module.run_with_system_sqlite([sys.executable, '-c', child], pubspec), exit_code)
                    self.assertEqual(pubspec.read_bytes(), original)

    def test_missing_or_empty_user_defines_is_added_inside_existing_hooks(self):
        for existing in (b'hooks:\n', b'hooks:\n  other_config:\n    enabled: true\n',
                         b'hooks:\n  user_defines: # empty\n'):
            with self.subTest(existing=existing):
                addition = module.SQLITE_HOOK
                if b'user_defines:' not in existing:
                    addition = b'  user_defines:\n' + addition
                after = b'flutter:\n  generate: true\n'
                self.assertEqual(module.with_system_sqlite_hook(existing + after), existing + addition + after)

    def test_insertion_preserves_trailing_block_scalar_newlines(self):
        for before, addition in (
                (b'name: fixture\ndescription: |+\n  retained text\n\n', module.HOOK),
                (STORAGE_HOOK + b'      description: |+\n        retained text\n\n', module.SQLITE_HOOK)):
            with self.subTest(before=before):
                self.assertEqual(module.with_system_sqlite_hook(before), before + addition)

    def test_existing_sqlite3_hook_conflicts_fail_before_write_or_launch(self):
        for sqlite in (b'    sqlite3:\n      source: system\n', b'    sqlite3:\n      source: bundled\n'):
            with self.subTest(sqlite=sqlite), tempfile.TemporaryDirectory() as directory:
                pubspec = Path(directory) / 'pubspec.yaml'
                original = b'name: fixture\n' + STORAGE_HOOK + sqlite
                pubspec.write_bytes(original)
                with patch.object(subprocess, 'run') as run:
                    with self.assertRaisesRegex(RuntimeError, 'Existing sqlite3'):
                        module.run_with_system_sqlite(['test-command'], pubspec)
                    run.assert_not_called()
                self.assertEqual(pubspec.read_bytes(), original)

    def test_ambiguous_and_unsupported_hooks_fail_before_write_or_launch(self):
        fixtures = (
            b'hooks: {user_defines: {}}\n',
            b'hooks:\n  user_defines: {}\n',
            b'hooks: *defaults\n',
            b'hooks: &defaults\n  user_defines:\n',
            b'hooks:\n  <<: *defaults\n',
            b'"hooks":\n  user_defines:\n',
            b'hooks:\n  "user_defines":\n',
            b'hooks:\n  user_defines:\n    "sqlite3":\n',
            b'hooks:\n  user_defines:\n    <<: *defaults\n',
            b'hooks:\n  user_defines:\n    - sqlite3\n',
            b'hooks:\n    user_defines:\n',
            b'hooks:\n\tuser_defines:\n',
            b'hooks:\nhooks:\n',
            b'hooks:\n  user_defines:\n  user_defines:\n',
            STORAGE_HOOK + b'    crisp_storage:\n      rust_smb: false\n',
            b'---\nhooks:\n',
            b'description: "hello\nhooks:\n  user_defines:\n    foo:\n      closing: text"\n',
            b'other:\n  value: "hello\nhooks:\n  user_defines:\n    foo:\n      closing: text"\n',
            b'other:\n  - "hello\nhooks:\n  user_defines:\n    foo:\n      closing: text"\n',
            b'other:\n  value: &some "hello\nhooks:\n  user_defines:\n    foo:\n      closing: text"\n',
            b'other:\n  value: !!str "hello\nhooks:\n  user_defines:\n    foo:\n      closing: text"\n',
            b'hooks:\n  other: "hello\n  user_defines:\n    foo:\n      closing: text"\n',
            b'description: |+\n  retained text',
        )
        for hooks in fixtures:
            with self.subTest(hooks=hooks), tempfile.TemporaryDirectory() as directory:
                pubspec = Path(directory) / 'pubspec.yaml'
                original = b'name: fixture\n' + hooks
                pubspec.write_bytes(original)
                with patch.object(subprocess, 'run') as run:
                    with self.assertRaises(RuntimeError):
                        module.run_with_system_sqlite(['test-command'], pubspec)
                    run.assert_not_called()
                self.assertEqual(pubspec.read_bytes(), original)

    def test_command_start_failure_restores_original(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / 'pubspec.yaml'
            original = b'name: fixture\n' + STORAGE_HOOK
            pubspec.write_bytes(original)
            with patch.object(subprocess, 'run', side_effect=OSError('cannot launch')):
                with self.assertRaises(OSError):
                    module.run_with_system_sqlite(['missing-executable'], pubspec)
            self.assertEqual(pubspec.read_bytes(), original)

    def test_interruption_restores_original(self):
        for interruption in (KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(interruption=type(interruption).__name__), tempfile.TemporaryDirectory() as directory:
                pubspec = Path(directory) / 'pubspec.yaml'
                original = b'name: fixture\n' + STORAGE_HOOK
                pubspec.write_bytes(original)
                with patch.object(subprocess, 'run', side_effect=interruption):
                    with self.assertRaises(type(interruption)):
                        module.run_with_system_sqlite(['test-command'], pubspec)
                self.assertEqual(pubspec.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
