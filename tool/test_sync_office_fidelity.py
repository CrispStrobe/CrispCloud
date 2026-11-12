import json
from pathlib import Path
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

    def test_modified_pinned_file_refuses_every_write(self):
        self.write_source(self.name, 'after')
        self.commit()
        (self.host/self.name).write_text('host customization')
        with self.assertRaisesRegex(sync.SyncError, 'Vendor drift'):
            sync.plan(self.source, self.host, 'HEAD')
        self.assertEqual((self.host/self.name).read_text(), 'host customization')

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
