import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

import sync_office_fidelity as sync


class SyncOfficeFidelityTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.source = Path(self.temporary.name)/'source'
        self.host = Path(self.temporary.name)/'host'
        self.source.mkdir()
        self.host.mkdir()
        self.run_git('init', '-q')
        self.run_git('config', 'user.email', 'test@example.invalid')
        self.run_git('config', 'user.name', 'Test')
        self.name = 'packages/quds_office_engine/lib/example.dart'
        self.write_source(self.name, 'before')
        self.run_git('add', '.')
        self.run_git('commit', '-qm', 'baseline')
        self.base = self.run_git('rev-parse', 'HEAD').strip()
        target = self.host/self.name
        target.parent.mkdir(parents=True)
        target.write_text('before')
        manifest = self.host/'tool/office_fidelity_manifest.json'
        manifest.parent.mkdir()
        manifest.write_text(json.dumps({'source_repository':'CrispStrobe/quds_office_suite',
                                       'source_branch':'main','source_commit':self.base,
                                       'files':{self.name:sync.digest(b'before')}}))

    def run_git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.source), *args], text=True)

    def write_source(self, name, value):
        path = self.source/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def commit(self):
        self.run_git('add', '-A')
        self.run_git('commit', '-qm', 'update')

    def test_dry_run_is_read_only_and_apply_pins_exact_bytes(self):
        self.write_source(self.name, 'after')
        new = 'packages/quds_office_engine/test/new_test.dart'
        self.write_source(new, 'test source')
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD', 'feature/fidelity')
        self.assertEqual((self.host/self.name).read_text(), 'before')
        self.assertFalse((self.host/new).exists())
        sync.apply(self.host, change)
        self.assertEqual((self.host/self.name).read_text(), 'after')
        self.assertEqual((self.host/new).read_text(), 'test source')
        self.assertEqual(change['manifest']['source_commit'], self.run_git('rev-parse','HEAD').strip())
        self.assertEqual(sync.plan(self.source, self.host, 'HEAD')['writes'], {})

    def test_existing_macro_example_is_backfilled_without_a_source_diff(self):
        example = f'{sync.MACRO_EXAMPLES}/word_example.bas'
        program = 'Sub Main()\nEnd Sub\n'
        self.write_source(example, program)
        self.commit()
        baseline = sync.plan(self.source, self.host, 'HEAD')['manifest']
        baseline['files'].pop(example)
        (self.host/'tool/office_fidelity_manifest.json').write_text(json.dumps(baseline))

        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertEqual(change['writes'], {example: program.encode()})
        sync.apply(self.host, change)
        self.assertEqual((self.host/example).read_text(), program)
        self.assertEqual(change['manifest']['files'][example], sync.digest(program.encode()))

    def test_modified_pinned_file_refuses_every_write(self):
        self.write_source(self.name, 'after')
        self.commit()
        (self.host/self.name).write_text('host customization')
        with self.assertRaisesRegex(sync.SyncError, 'Vendor drift'):
            sync.plan(self.source, self.host, 'HEAD')
        self.assertEqual((self.host/self.name).read_text(), 'host customization')

    def test_declared_patch_is_kept_until_upstream_absorbs_it(self):
        path = self.host/'tool/office_fidelity_manifest.json'
        manifest = json.loads(path.read_text())
        manifest['local_patch_bases'] = {self.name: manifest['files'][self.name]}
        manifest['files'][self.name] = sync.digest(b'patched')
        path.write_text(json.dumps(manifest))
        (self.host/self.name).write_bytes(b'patched')

        self.write_source('packages/quds_office_engine/lib/another.dart', 'new')
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertNotIn(self.name, change['writes'])
        self.assertEqual(change['manifest']['local_patch_bases'],
                         manifest['local_patch_bases'])

        self.write_source(self.name, 'a different upstream change')
        self.commit()
        with self.assertRaisesRegex(sync.SyncError, 'Upstream changed a locally patched file'):
            sync.plan(self.source, self.host, 'HEAD')

        self.write_source(self.name, 'patched')
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertNotIn(self.name, change['writes'])
        self.assertNotIn('local_patch_bases', change['manifest'])

    def test_apply_without_source_modes_keeps_existing_permission_behavior(self):
        target = self.host/self.name
        target.chmod(0o755)
        self.write_source(self.name, 'after')
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertNotIn('modes', change)
        sync.apply(self.host, change)
        self.assertEqual(target.read_text(), 'after')
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)

    def test_new_path_collision_refuses_every_write(self):
        new = 'packages/quds_office_engine/test/new.dart'
        self.write_source(new, 'upstream')
        self.commit()
        path = self.host/new
        path.parent.mkdir(parents=True)
        path.write_text('host test')
        with self.assertRaisesRegex(sync.SyncError, 'host customization'):
            sync.plan(self.source, self.host, 'HEAD')

    def test_unrelated_app_and_package_configuration_are_not_synced(self):
        self.write_source('packages/quds_office_engine/pubspec.yaml', 'unsafe version replacement')
        self.write_source('lib/app.dart', 'unrelated')
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertEqual(change['writes'], {})

    def test_embedded_data_sources_notices_and_manifest_follow_the_runtime_pin(self):
        supplied = {
            'packages/quds_office_engine/lib/src/bidi/german_hyphenation_data.dart': 'embedded patterns',
            'packages/quds_office_engine/third_party/hyphenation/hyph-de-1996.tex': 'original patterns and notice',
            'packages/quds_office_engine/third_party/hyphenation/LICENSE': 'original notice',
            'packages/quds_office_engine/third_party/hyphenation/ENGLISH_US_LICENSE': 'original Kuiken permission and copyright',
            'packages/quds_office_engine/third_party/hyphenation/ENGLISH_GB_LICENSE': 'original British MIT permission and copyright',
            'packages/quds_office_engine/third_party/hyphenation/README.md': 'pattern provenance',
            'packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE': 'original word-list notice',
            'packages/quds_office_engine/third_party/proofing/QUDS_WORDS_LICENSE': 'supplement notice',
            'packages/quds_office_engine/third_party/proofing/manifest.json': '{"source":"pinned"}',
            'packages/quds_office_engine/third_party/proofing/README.md': 'word-list provenance',
            'packages/quds_office_engine/third_party/fonttools/LICENSE': 'font data provenance and notice',
        }
        excluded = [
            'packages/quds_office_engine/third_party/unrelated/LICENSE',
            'packages/quds_office_engine/third_party/proofing-other/LICENSE',
            'packages/quds_office_engine/third_party/fonttools-other/LICENSE',
            'packages/quds_office_editor/third_party/fonttools/LICENSE',
            'packages/quds_office_editor/third_party/proofing/LICENSE',
            'packages/quds_office_editor/third_party/hyphenation/ENGLISH_US_LICENSE',
            'packages/quds_office_engine/third_party/hyphenation-other/ENGLISH_GB_LICENSE',
            'packages/quds_proofing_harper/pubspec.yaml',
            'packages/quds_proofing_harper/native/src/lib.rs',
        ]
        for name, value in supplied.items():
            self.write_source(name, value)
        for name in excluded:
            self.write_source(name, 'outside the Office data boundary')
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertEqual(set(change['writes']), set(supplied))
        self.assertFalse(any((self.host/name).exists() for name in supplied))
        sync.apply(self.host, change)
        for name, value in supplied.items():
            self.assertEqual((self.host/name).read_text(), value)
            self.assertEqual(change['manifest']['files'][name], sync.digest(value.encode()))
        self.assertFalse(any((self.host/name).exists() for name in excluded))
        self.assertEqual(sync.plan(self.source, self.host, 'HEAD')['writes'], {})

        # A local edit to a newly managed notice must stop every later write.
        self.write_source(self.name, 'new runtime source')
        self.commit()
        for notice in (
                'packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE',
                'packages/quds_office_engine/third_party/fonttools/LICENSE',
                'packages/quds_office_engine/third_party/hyphenation/ENGLISH_US_LICENSE',
                'packages/quds_office_engine/third_party/hyphenation/ENGLISH_GB_LICENSE'):
            with self.subTest(notice=notice):
                original = (self.host/notice).read_text()
                (self.host/notice).write_text('host edit')
                try:
                    with self.assertRaisesRegex(sync.SyncError, 'Vendor drift'):
                        sync.plan(self.source, self.host, 'HEAD')
                    self.assertEqual((self.host/self.name).read_text(), 'before')
                finally:
                    (self.host/notice).write_text(original)

    def test_deleted_tracked_file_is_removed_from_manifest(self):
        (self.source/self.name).unlink()
        self.commit()
        change = sync.plan(self.source, self.host, 'HEAD')
        self.assertEqual(change['deletes'], [self.name])
        sync.apply(self.host, change)
        self.assertFalse((self.host/self.name).exists())
        self.assertNotIn(self.name, change['manifest']['files'])

    def test_unknown_commit_does_not_write(self):
        with self.assertRaises(sync.SyncError):
            sync.plan(self.source, self.host, 'missing-ref')
        self.assertEqual((self.host/self.name).read_text(), 'before')

    def test_unsafe_manifest_path_is_rejected(self):
        path = self.host/'tool/office_fidelity_manifest.json'
        manifest = json.loads(path.read_text())
        manifest['files']['../outside'] = 'hash'
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(sync.SyncError, 'Unsafe'):
            sync.plan(self.source, self.host, 'HEAD')


if __name__ == '__main__':
    unittest.main()
