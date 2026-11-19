import importlib.util
from pathlib import Path
import tempfile
import zipfile
import unittest
from unittest import mock
import runpy
import subprocess
import sys

spec = importlib.util.spec_from_file_location('components', Path(__file__).with_name('check_distribution_components.py'))
components = importlib.util.module_from_spec(spec)
spec.loader.exec_module(components)


class DistributionTests(unittest.TestCase):
    def test_default_artifacts_refuse_bundled_lgpl_library(self):
        for name in ['libsmb2.dylib', 'libsmb2.so', 'smb2.dll', 'dart_smb2.framework']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as d:
                (Path(d) / name).write_bytes(b'fixture')
                with self.assertRaisesRegex(ValueError, 'libsmb2'):
                    components.check_artifact(Path(d), fuse_opt_in=True)

    def test_android_archive_and_renamed_native_asset_declarations_are_checked(self):
        with tempfile.TemporaryDirectory() as d:
            apk = Path(d) / 'app.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libdart_smb2.so', b'fixture')
            with self.assertRaisesRegex(ValueError, 'libsmb2'):
                components.check_artifact(apk)
            apk.unlink()
            (Path(d) / 'native_assets.json').write_text('{"package:dart_smb2/native": "opaque-library.so"}')
            with self.assertRaisesRegex(ValueError, 'declaration'):
                components.check_artifact(Path(d))

    def test_rust_backend_is_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'libcrisp_smb_bridge.dylib').write_bytes(b'fixture')
            self.assertTrue(components.check_artifact(Path(d)))

    def test_native_mounts_require_an_opted_in_artifact(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'crispcloud_fuse_bridge').write_bytes(b'fixture')
            with self.assertRaisesRegex(ValueError, 'default build'):
                components.check_artifact(Path(d))
            self.assertTrue(components.check_artifact(Path(d), fuse_opt_in=True))

    def test_cli_bundle_actually_contains_project_license_and_native_notices(self):
        root = Path(__file__).resolve().parents[1]
        def compiler(command, **kwargs):
            if command[1:3] == ['build', 'cli']:
                target = Path(command[command.index('-o') + 1]) / 'bundle'
                (target / 'bin').mkdir(parents=True)
                (target / 'bin' / target.parent.name).write_bytes(b'compiled CLI fixture')
                (target / 'lib').mkdir()
                (target / 'lib/native-fixture').write_bytes(b'identical native asset')
            elif command[1] == str(root / 'tool/collect_catalog_licenses.py'):
                Path(command[command.index('--output') + 1]).mkdir(parents=True)
            else:
                self.fail(f'Unexpected compiler invocation: {command}')
        with tempfile.TemporaryDirectory() as d, mock.patch.object(
            subprocess, 'run', side_effect=compiler
        ), mock.patch.object(sys, 'argv', ['build_cli_bundle.py', '--output', d]):
            runpy.run_path(str(root / 'tool/build_cli_bundle.py'), run_name='__main__')
            bundle = Path(d) / 'bundle'
            self.assertEqual((bundle / 'LICENSE-CRISPCLOUD.txt').read_bytes(),
                             (root / 'LICENSE.txt').read_bytes())
            self.assertIn('smb2 0.43.0', (bundle / 'STORAGE-NOTICES.txt').read_text())
            self.assertTrue((bundle / 'bin/crispcloud').is_file())
            self.assertTrue((bundle / 'bin/crisp').is_file())
            self.assertEqual((bundle / 'install.sh').read_bytes(), (root / 'cli/install.sh').read_bytes())
            self.assertTrue((bundle / 'README.md').is_file())
            self.assertTrue(components.check_artifact(bundle))


if __name__ == '__main__':
    unittest.main()
