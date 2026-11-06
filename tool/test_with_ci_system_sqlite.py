import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ci_sqlite', Path(__file__).with_name('with_ci_system_sqlite.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


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

    def test_existing_hooks_fail_closed_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / 'pubspec.yaml'
            original = b'name: fixture\nhooks:\n  user_defines: {}\n'
            pubspec.write_bytes(original)
            with self.assertRaisesRegex(RuntimeError, 'explicit merging'):
                module.run_with_system_sqlite([sys.executable, '-c', 'raise Exception()'], pubspec)
            self.assertEqual(pubspec.read_bytes(), original)

    def test_command_start_failure_restores_original(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / 'pubspec.yaml'
            original = b'name: fixture\n'
            pubspec.write_bytes(original)
            with patch.object(subprocess, 'run', side_effect=OSError('cannot launch')):
                with self.assertRaises(OSError):
                    module.run_with_system_sqlite(['missing-executable'], pubspec)
            self.assertEqual(pubspec.read_bytes(), original)

    def test_interruption_restores_original(self):
        from unittest.mock import patch
        for interruption in (KeyboardInterrupt(), SystemExit(143)):
            with self.subTest(interruption=type(interruption).__name__), tempfile.TemporaryDirectory() as directory:
                pubspec = Path(directory) / 'pubspec.yaml'
                original = b'name: fixture\n'
                pubspec.write_bytes(original)
                with patch.object(subprocess, 'run', side_effect=interruption):
                    with self.assertRaises(type(interruption)):
                        module.run_with_system_sqlite(['test-command'], pubspec)
                self.assertEqual(pubspec.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
