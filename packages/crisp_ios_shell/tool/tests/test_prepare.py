"""Preparation safety/provenance tests; no network, Xcode or prebuilts needed."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tarfile
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[1] / 'prepare.py'
spec = importlib.util.spec_from_file_location('crisp_prepare', TOOL)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def archive(self, members):
        target = self.root / 'source.tar.gz'
        with tarfile.open(target, 'w:gz') as archive:
            for name, content, link in members:
                entry = tarfile.TarInfo(name)
                if link is not None:
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = link
                    archive.addfile(entry)
                else:
                    entry.size = len(content)
                    archive.addfile(entry, io.BytesIO(content))
        return target

    def test_streaming_digest(self):
        path = self.root / 'large'
        path.write_bytes(b'abc' * 500000)
        self.assertEqual(prepare.sha256(path), hashlib.sha256(path.read_bytes()).hexdigest())

    def test_source_pins_are_immutable_and_complete(self):
        manifest = json.loads(prepare.MANIFEST.read_text())
        for value in manifest['sources'].values():
            self.assertRegex(value['commit'], r'^[0-9a-f]{40}$')
            self.assertIn(value['commit'], value['url'])
            self.assertRegex(value['sha256'], r'^[0-9a-f]{64}$')
        self.assertEqual(manifest['targets'], ['ios_system', 'files', 'text', 'shell', 'awk', 'tar'])
        self.assertEqual(len(manifest['dash_variants']), 6)
        self.assertEqual(set(manifest['build_helpers']), {'automake-missing', 'automake-compile', 'automake-install-sh', 'automake-depcomp'})
        for filename, record in manifest['build_helpers'].items():
            helper = prepare.PACKAGE / 'tool' / filename
            self.assertEqual(prepare.sha256(helper), record['sha256'])
            self.assertIn(record['commit'], record['url'])

    def test_cached_source_is_verified_without_network(self):
        destination = self.root / 'source.tar.gz'
        destination.write_bytes(b'known source')
        record = {'url': 'https://invalid.example/source', 'sha256': prepare.sha256(destination)}
        with mock.patch.object(prepare.urllib.request, 'urlopen', side_effect=AssertionError('network should not run')):
            prepare.download(record, destination)

    def test_corrupt_cache_is_replaced_only_after_verification(self):
        destination = self.root / 'source.tar.gz'
        destination.write_bytes(b'corrupt')
        expected = b'correct'
        record = {'url': 'https://invalid.example/source', 'sha256': hashlib.sha256(expected).hexdigest()}
        with mock.patch.object(prepare.urllib.request, 'urlopen', return_value=io.BytesIO(expected)):
            prepare.download(record, destination)
        self.assertEqual(destination.read_bytes(), expected)
        self.assertFalse(destination.with_suffix('.download').exists())

    def test_bad_download_preserves_cache_and_removes_partial(self):
        destination = self.root / 'source.tar.gz'
        destination.write_bytes(b'old')
        record = {'url': 'https://invalid.example/source', 'sha256': '0' * 64}
        with mock.patch.object(prepare.urllib.request, 'urlopen', return_value=io.BytesIO(b'untrusted')):
            with self.assertRaisesRegex(RuntimeError, 'digest mismatch'):
                prepare.download(record, destination)
        self.assertEqual(destination.read_bytes(), b'old')
        self.assertFalse(destination.with_suffix('.download').exists())

    def test_extracts_one_source_root(self):
        archive = self.archive([('root/src/file.c', b'source', None)])
        target = self.root / 'extracted'
        prepare.extract_source(archive, target)
        self.assertEqual((target / 'src/file.c').read_bytes(), b'source')
        self.assertFalse((target / 'root').exists())

    def test_rejects_multiple_roots(self):
        archive = self.archive([('one/a', b'a', None), ('two/b', b'b', None)])
        with self.assertRaisesRegex(RuntimeError, 'one root'):
            prepare.extract_source(archive, self.root / 'extracted')

    def test_rejects_traversal_members(self):
        archive = self.archive([('root/../../outside', b'x', None)])
        with self.assertRaisesRegex(RuntimeError, 'Unsafe source path'):
            prepare.extract_source(archive, self.root / 'extracted')
        self.assertFalse((self.root / 'outside').exists())

    def test_rejects_absolute_symlink(self):
        archive = self.archive([('root/a', b'a', None), ('root/bad', b'', '/etc/passwd')])
        with self.assertRaisesRegex(RuntimeError, 'Absolute source link'):
            prepare.extract_source(archive, self.root / 'extracted')

    def test_rejects_escaping_relative_symlink(self):
        archive = self.archive([('root/a', b'a', None), ('root/bad', b'', '../../outside')])
        with self.assertRaisesRegex(RuntimeError, 'Escaping source link'):
            prepare.extract_source(archive, self.root / 'extracted')

    def test_explicit_build_only_omission_does_not_trust_other_links(self):
        archive = self.archive([('root/a', b'a', None), ('root/missing', b'', '/maintainer/path')])
        target = self.root / 'extracted'
        prepare.extract_source(archive, target, omit={'missing'})
        self.assertFalse((target / 'missing').exists())
        self.assertEqual((target / 'a').read_bytes(), b'a')

    def test_binary_cache_rejects_missing_or_modified_outputs(self):
        frameworks = self.root / 'Frameworks'
        frameworks.mkdir()
        binary = frameworks / 'binary'
        binary.write_bytes(b'framework')
        inputs = {'compiler': 'pinned'}
        stamp = {'inputs': inputs, 'outputs': {'binary': prepare.sha256(binary)}}
        self.assertTrue(prepare.output_is_current(stamp, inputs, frameworks))
        self.assertFalse(prepare.output_is_current(stamp, {'compiler': 'changed'}, frameworks))
        binary.write_bytes(b'changed')
        self.assertFalse(prepare.output_is_current(stamp, inputs, frameworks))
        binary.unlink()
        self.assertFalse(prepare.output_is_current(stamp, inputs, frameworks))
        self.assertFalse(prepare.output_is_current({'inputs': inputs, 'outputs': {}}, inputs, frameworks))

    def test_fingerprint_includes_preparation_patches_and_command_allowlist(self):
        manifest = json.loads(prepare.MANIFEST.read_text())
        result = prepare.fingerprint(manifest)
        self.assertEqual(result['manifest'], manifest)
        self.assertEqual(result['preparation_sha256'], prepare.sha256(TOOL))
        self.assertEqual(set(result['patches']), {'ios_system.patch', 'dash.patch'})
        self.assertEqual(result['commands_sha256'], prepare.sha256(prepare.PACKAGE / 'ios/Resources/commands.plist'))

    def test_committed_patches_include_real_engine_and_canonical_input(self):
        native = (prepare.PACKAGE / 'patches/ios_system.patch').read_text()
        dash = (prepare.PACKAGE / 'patches/dash.patch').read_text()
        self.assertIn('crisp_interrupt_owned_streams', native)
        self.assertIn('interruptCancelled', native)
        self.assertIn('crisp_set_command_list', native)
        self.assertIn('crispWindowMutex', native)
        self.assertIn('crisp_window_value', native)
        self.assertIn('crisp_shell_read', dash)
        self.assertIn('crisp_shell_check_interrupt', dash)
        self.assertIn('ios_getenv("COLUMNS")', dash)
        self.assertIn('#define main dash_main', dash)
        self.assertNotIn("== '\n'", dash)  # A C character literal must not span lines.

    def test_command_exports_checked_in_every_sdk_and_architecture(self):
        resource = self.root / 'ios/Resources'
        resource.mkdir(parents=True)
        (resource / 'commands.plist').write_bytes(plistlib.dumps({
            'dash': ['dash.framework/dash', 'dash_main', '', 'file'],
            'cat': ['files.framework/files', 'cat_main', '', 'file'],
            'pwd': ['SELF', 'pwd_main', '', 'no'],
        }))
        products = {'iphoneos': self.root / 'device', 'iphonesimulator': self.root / 'simulator'}
        manifest = {'dash_variants': ['dash', 'dashA']}
        listing = '000001000 T _dash_main\n000002000 T _cat_main\n000003000 T _pwd_main\n'
        with mock.patch.object(prepare, 'PACKAGE', self.root), mock.patch.object(
            prepare.subprocess, 'check_output', return_value=listing
        ) as inspected:
            prepare.validate_command_symbols(products, manifest)
        calls = [call.args[0] for call in inspected.call_args_list]
        self.assertEqual(len(calls), 12)
        self.assertEqual(sum(call[3] == 'x86_64' for call in calls), 4)
        self.assertTrue(any('dashA.framework/dashA' in call[-1] for call in calls))

    def test_missing_dash_export_fails_before_packaging(self):
        resource = self.root / 'ios/Resources'
        resource.mkdir(parents=True)
        (resource / 'commands.plist').write_bytes(plistlib.dumps({
            'dash': ['dash.framework/dash', 'dash_main', '', 'file'],
        }))
        with mock.patch.object(prepare, 'PACKAGE', self.root), mock.patch.object(
            prepare.subprocess, 'check_output', return_value='000001000 T _main\n'
        ):
            with self.assertRaisesRegex(RuntimeError, r'iphoneos/arm64/dash.*dash_main'):
                prepare.validate_command_symbols({'iphoneos': self.root}, {'dash_variants': ['dash']})

    def test_aggregate_notices_preserve_all_build_helper_conditions(self):
        notices = prepare.source_notices({})
        for name in ('missing', 'compile', 'install-sh', 'depcomp'):
            self.assertIn(f'Sources: tool/automake-{name}\n', notices)
        self.assertIn('As a special exception to the GNU General Public License', notices)
        self.assertIn('configuration script generated by Autoconf', notices)
        self.assertIn('Copyright (C) 1994 X Consortium', notices)
        self.assertIn('FSF changes to this file are in the public domain.', notices)
        self.assertNotIn('func_cl_dashL ()', notices)


if __name__ == '__main__':
    unittest.main()
