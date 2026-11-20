import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).with_name('macos_distribution.py'))
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


def encoded(*values):
    return ','.join(base64.b64encode(v.encode()).decode() for v in values)


class ProfileTests(unittest.TestCase):
    def test_store_refuses_optional_copyleft_helper(self):
        with self.assertRaisesRegex(ValueError, 'exclude FUSE'):
            distribution.validate('appstore', {'CRISP_ENABLE_FUSE': 'true'})

    def test_native_dart_profile_mismatch_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'disagree'):
            distribution.validate('github', {})

    def test_duplicate_defines_use_actual_last_value(self):
        values = distribution.defines(encoded('CRISP_ENABLE_FUSE=true', 'CRISP_ENABLE_FUSE=false'))
        self.assertFalse(distribution.validate('appstore', values))

    def test_build_failure_restores_default_configuration(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(distribution, 'ROOT', Path(d)):
            with mock.patch.object(subprocess, 'run', side_effect=OSError('missing compiler')):
                with self.assertRaises(OSError):
                    distribution.build('github', True, 'flutter', [])
            self.assertFalse((Path(d) / 'macos/Flutter/ephemeral/Distribution.xcconfig').exists())

    def test_release_wrapper_refuses_debug_build_mode(self):
        with self.assertRaisesRegex(ValueError, 'release Runner'):
            distribution.build('appstore', False, 'flutter', ['--debug'])

    def test_targeted_override_does_not_unsandbox_extension(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(distribution, 'ROOT', Path(d)):
            def compiler(command, **kwargs):
                config = Path(d) / 'macos/Flutter/ephemeral/Distribution.xcconfig'
                text = config.read_text()
                self.assertIn('CRISP_APP_ENTITLEMENTS = Runner/Direct.entitlements', text)
                self.assertNotIn('\nCODE_SIGN_ENTITLEMENTS', text)
                self.assertIn('--dart-define=CRISP_DISTRIBUTION=github', command)
                return subprocess.CompletedProcess(command, 0)
            with mock.patch.object(subprocess, 'run', side_effect=compiler):
                self.assertEqual(distribution.build('github', False, 'flutter', ['--no-pub']), 0)

    def test_runner_and_extension_share_version_and_inherited_settings(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(distribution, 'ROOT', Path(d)):
            (Path(d) / 'pubspec.yaml').write_text('version: 1.3.4+32\n')
            parent = Path(d) / 'Existing.xcconfig'
            parent.write_text('ARCHS = arm64\n')
            settings_path = None
            def compiler(command, **kwargs):
                nonlocal settings_path
                settings_path = Path(kwargs['env']['XCODE_XCCONFIG_FILE'])
                text = settings_path.read_text()
                self.assertIn(f'#include "{parent.resolve()}"', text)
                self.assertIn('FLUTTER_BUILD_NAME = 1.3.5\n', text)
                self.assertIn('FLUTTER_BUILD_NUMBER = 44\n', text)
                return subprocess.CompletedProcess(command, 0)
            with mock.patch.dict(distribution.os.environ, {'XCODE_XCCONFIG_FILE': str(parent)}), mock.patch.object(subprocess, 'run', side_effect=compiler):
                self.assertEqual(distribution.build('appstore', False, 'flutter', ['--build-name=1.3.5', '--build-number', '44']), 0)
            self.assertFalse(settings_path.exists())
            self.assertEqual(parent.read_text(), 'ARCHS = arm64\n')

    def test_entitlement_policy_rejects_swapped_signed_profiles(self):
        for profile, sandbox in [('github', True), ('appstore', False)]:
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                distribution.check_entitlements(profile, {'com.apple.security.app-sandbox': sandbox})

    def test_store_rejects_debug_and_direct_loader_capabilities(self):
        for key in ['com.apple.security.cs.disable-library-validation', 'com.apple.security.cs.allow-unsigned-executable-memory', 'get-task-allow']:
            with self.subTest(key=key), self.assertRaises(ValueError):
                distribution.check_entitlements('appstore', {'com.apple.security.app-sandbox': True, key: True})

    def test_committed_store_and_direct_entitlements(self):
        root = distribution.ROOT / 'macos'
        for profile, name in distribution.ENTITLEMENTS.items():
            distribution.check_entitlements(profile, plistlib.loads((root / name).read_bytes()))

    @unittest.skipUnless(sys.platform == 'darwin', 'native macOS signing acceptance')
    def test_real_signed_native_apps_obey_profile_boundary(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            source = root / 'main.c'
            source.write_text('int main(void) { return 0; }\n')
            for profile, entitlements in distribution.ENTITLEMENTS.items():
                app = root / f'{profile}.app'
                macos = app / 'Contents/MacOS'
                macos.mkdir(parents=True)
                subprocess.run(['clang', str(source), '-o', str(macos / 'fixture')], check=True)
                (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleExecutable': 'fixture', 'CFBundleIdentifier': 'test.crisp.' + profile,
                    'CFBundlePackageType': 'APPL'}))
                distribution.stage(profile, app / 'Contents/Resources', encoded('CRISP_DISTRIBUTION=' + profile))
                subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements',
                    str(distribution.ROOT / 'macos' / entitlements), str(app)], check=True)
                distribution.verify(profile, app)
                other = 'github' if profile == 'appstore' else 'appstore'
                with self.assertRaisesRegex(ValueError, 'metadata'):
                    distribution.verify(other, app)
                # Correctly signed metadata cannot disguise the host's actual sandbox.
                distribution.stage(other, app / 'Contents/Resources', encoded('CRISP_DISTRIBUTION=' + other))
                subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements',
                    str(distribution.ROOT / 'macos' / entitlements), str(app)], check=True)
                with self.assertRaisesRegex(ValueError, 'sandboxed|direct-distribution'):
                    distribution.verify(other, app)


if __name__ == '__main__':
    unittest.main()
