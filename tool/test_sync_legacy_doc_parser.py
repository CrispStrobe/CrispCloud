import json
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

import sync_legacy_doc_parser as legacy
import sync_office_fidelity as office
import verify_office_fidelity as verifier


class StandaloneParserSyncTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.source, self.quds, self.host = [self.base / name for name in ('parser', 'quds', 'host')]
        for repository in (self.source, self.quds):
            repository.mkdir()
            self.git(repository, 'init', '-q')
            self.git(repository, 'config', 'user.email', 'test@example.invalid')
            self.git(repository, 'config', 'user.name', 'Test')
            self.git(repository, 'config', 'core.filemode', 'true')
        self.host.mkdir()
        self.old = {'pubspec.yaml': b'name: legacy_doc_parser\n', 'LICENSE': b'MPL source notice\n',
                    'lib/legacy_doc_parser.dart': b'old parser\n', 'doc/old.md': b'old note\n'}
        for name, data in self.old.items():
            self.write(self.source, name, data)
            self.write(self.host, f'{legacy.PREFIX}/{name}', data)
            self.write(self.quds, f'{legacy.PREFIX}/{name}', data)
        self.before = self.commit(self.source)
        self.quds_name = 'packages/quds_office_engine/lib/example.dart'
        self.write(self.quds, self.quds_name, b'Quds before\n')
        self.write(self.host, self.quds_name, b'Quds before\n')
        self.quds_before = self.commit(self.quds)
        self.write(self.host, f'{legacy.PREFIX}/UPSTREAM.json', json.dumps(
            {'repository': legacy.REPOSITORY, 'commit': self.before, 'patches': []}).encode())
        self.write(self.host, 'pubspec.yaml', (f'name: host\ndependencies:\n'
            f'  legacy_doc_parser:\n    git:\n      url: https://github.com/{legacy.REPOSITORY}.git\n'
            f'      ref: {self.before}\ndependency_overrides:\n  legacy_doc_parser:\n'
            '    path: packages/legacy_doc_parser\n').encode())
        self.manifest = {'source_repository': 'CrispStrobe/quds_office_suite',
                         'source_commit': self.quds_before, 'source_branch': 'main',
                         'files': {self.quds_name: office.digest(b'Quds before\n'),
                                   f'{legacy.PREFIX}/lib/legacy_doc_parser.dart': office.digest(b'old parser\n')}}
        self.write_manifest(self.manifest)
        self.write(self.host, 'lib/host.dart', b'host customization\n')

    def git(self, root, *args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True)

    def commit(self, root):
        self.git(root, 'add', '-A')
        self.git(root, 'commit', '-qm', 'fixture')
        return self.git(root, 'rev-parse', 'HEAD').strip()

    def write(self, root, name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def write_manifest(self, value):
        self.write(self.host, 'tool/office_fidelity_manifest.json', json.dumps(value).encode())

    def update(self):
        self.write(self.source, 'lib/legacy_doc_parser.dart', b'new parser\n')
        self.write(self.source, 'doc/new.md', b'new standalone documentation\n')
        (self.source / 'doc/old.md').unlink()
        return self.commit(self.source)

    def test_exact_update_is_dry_until_apply_and_retains_quds_identity(self):
        after = self.update()
        original = (self.host / 'pubspec.yaml').read_bytes()
        change = legacy.plan(self.source, self.host, after)
        self.assertEqual((self.host / 'pubspec.yaml').read_bytes(), original)
        self.assertEqual(change['manifest']['source_commit'], self.quds_before)
        self.assertEqual(change['manifest']['files'][self.quds_name], self.manifest['files'][self.quds_name])
        office.apply(self.host, change)
        self.assertFalse((self.host / legacy.PREFIX / 'doc/old.md').exists())
        self.assertEqual((self.host / legacy.PREFIX / 'doc/new.md').read_bytes(), b'new standalone documentation\n')
        self.assertIn(after, (self.host / 'pubspec.yaml').read_text())
        self.assertEqual((self.host / 'lib/host.dart').read_bytes(), b'host customization\n')
        _, failures = verifier.verify(self.host, self.quds, self.source)
        self.assertEqual(failures, [])

    def test_new_executable_uses_committed_mode_and_bytes(self):
        name = 'tool/check.sh'
        script = b'#!/bin/sh\nexit 0\n'
        self.write(self.source, name, script)
        (self.source / name).chmod(0o755)
        after = self.commit(self.source)
        self.assertTrue(self.git(self.source, 'ls-tree', after, '--', name).startswith('100755 '))
        # The checked-out source may differ; the exact commit is authoritative.
        (self.source / name).chmod(0o644)
        (self.source / name).write_bytes(b'uncommitted source\n')
        # Existing callers still receive the same (commit, byte-map) pair.
        commit, files = legacy.source_tree(self.source, after)
        self.assertEqual(commit, after)
        self.assertEqual(files[name], script)
        change = legacy.plan(self.source, self.host, after)
        target = self.host / legacy.PREFIX / name
        self.assertFalse(target.exists())
        office.apply(self.host, change)
        self.assertEqual(target.read_bytes(), script)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source)[1], [])

    def test_mode_only_updates_are_applied_in_both_directions(self):
        name = 'lib/legacy_doc_parser.dart'
        target = self.host / legacy.PREFIX / name
        for mode in (0o755, 0o644):
            with self.subTest(mode=oct(mode)):
                (self.source / name).chmod(mode)
                after = self.commit(self.source)
                change = legacy.plan(self.source, self.host, after)
                self.assertIn(f'{legacy.PREFIX}/{name}', change['writes'])
                self.assertEqual(target.read_bytes(), self.old[name])
                self.assertNotEqual(stat.S_IMODE(target.stat().st_mode), mode)
                office.apply(self.host, change)
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), mode)
                self.assertEqual(target.read_bytes(), self.old[name])
                self.assertEqual(verifier.verify(self.host, legacy_source=self.source)[1], [])

    def test_mirror_executable_bit_drift_blocks_every_planned_write(self):
        after = self.update()
        target = self.host / legacy.PREFIX / 'lib/legacy_doc_parser.dart'
        target.chmod(0o755)
        original = (self.host / 'pubspec.yaml').read_bytes()
        with self.assertRaisesRegex(office.SyncError, 'mode drift'):
            legacy.plan(self.source, self.host, after)
        self.assertEqual((self.host / 'pubspec.yaml').read_bytes(), original)
        self.assertEqual(target.read_bytes(), b'old parser\n')
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)

    def test_verifier_reports_executable_bit_drift_against_pinned_source(self):
        after = self.update()
        office.apply(self.host, legacy.plan(self.source, self.host, after))
        name = 'lib/legacy_doc_parser.dart'
        (self.host / legacy.PREFIX / name).chmod(0o755)
        failures = verifier.verify(self.host, legacy_source=self.source)[1]
        self.assertIn(f'standalone parser mode mismatch: {name}', failures)

    def test_git_index_check_rejects_ignored_upstream_evidence(self):
        name = 'doc/evidence/retained/formatter.log'
        self.write(self.source, name, b'original diagnostic record\n')
        after = self.commit(self.source)
        office.apply(self.host, legacy.plan(self.source, self.host, after))
        self.git(self.host, 'init', '-q')
        self.write(self.host, '.gitignore', b'*.log\n')
        self.git(self.host, 'add', '-A')
        # Filesystem verification succeeds, even though an ordinary git add
        # silently omits this immutable upstream source from the next commit.
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source)[1], [])
        path = f'{legacy.PREFIX}/{name}'
        failures = verifier.verify(self.host, legacy_source=self.source,
                                   require_tracked=True)[1]
        self.assertEqual(failures, [f'Office source missing from Git index: {path}'])
        self.git(self.host, 'add', '-f', '--', path)
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source,
                                         require_tracked=True)[1], [])

    def test_git_index_check_rejects_stale_source_pins_and_modes(self):
        office.apply(self.host, legacy.plan(self.source, self.host, self.before))
        self.git(self.host, 'init', '-q')
        self.git(self.host, 'config', 'core.filemode', 'true')
        self.git(self.host, 'add', '-A')
        after = self.update()
        office.apply(self.host, legacy.plan(self.source, self.host, after))
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source)[1], [])
        failures = verifier.verify(self.host, legacy_source=self.source,
                                   require_tracked=True)[1]
        for name in ('pubspec.yaml', 'tool/office_fidelity_manifest.json',
                     f'{legacy.PREFIX}/UPSTREAM.json',
                     f'{legacy.PREFIX}/lib/legacy_doc_parser.dart'):
            self.assertIn(f'Office source differs from Git index: {name}', failures)
        self.git(self.host, 'add', '-A')
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source,
                                         require_tracked=True)[1], [])
        name = f'{legacy.PREFIX}/lib/legacy_doc_parser.dart'
        self.git(self.host, 'update-index', '--chmod=+x', '--', name)
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source,
                                         require_tracked=True)[1],
                         [f'Office source differs from Git index: {name}'])

    def test_git_index_check_rejects_unstaged_upstream_deletions(self):
        office.apply(self.host, legacy.plan(self.source, self.host, self.before))
        self.git(self.host, 'init', '-q')
        self.git(self.host, 'add', '-A')
        after = self.update()
        office.apply(self.host, legacy.plan(self.source, self.host, after))
        manifest = json.loads((self.host / 'tool/office_fidelity_manifest.json').read_text())
        # Staging every surviving file misses the deletion: the old source
        # would reappear after the resulting commit is checked out elsewhere.
        self.git(self.host, 'add', '--', 'pubspec.yaml',
                 'tool/office_fidelity_manifest.json', f'{legacy.PREFIX}/UPSTREAM.json',
                 *manifest['files'])
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source)[1], [])
        deleted = f'{legacy.PREFIX}/doc/old.md'
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source,
                                         require_tracked=True)[1],
                         [f'Unexpected parser source in Git index: {deleted}'])
        self.git(self.host, 'add', '-u', '--', deleted)
        self.assertEqual(verifier.verify(self.host, legacy_source=self.source,
                                         require_tracked=True)[1], [])

    def test_modified_or_extra_mirror_source_refuses_every_write(self):
        after = self.update()
        original = (self.host / 'pubspec.yaml').read_bytes()
        path = self.host / legacy.PREFIX / 'doc/old.md'
        path.write_bytes(b'host patch')
        with self.assertRaisesRegex(office.SyncError, 'vendor drift'):
            legacy.plan(self.source, self.host, after)
        path.write_bytes(self.old['doc/old.md'])
        self.write(self.host, f'{legacy.PREFIX}/lib/unreviewed.dart', b'extra source')
        with self.assertRaisesRegex(office.SyncError, 'unreviewed files'):
            legacy.plan(self.source, self.host, after)
        self.assertEqual((self.host / 'pubspec.yaml').read_bytes(), original)

    def test_unrelated_vendor_drift_blocks_parser_update(self):
        after = self.update()
        self.write(self.host, self.quds_name, b'host Quds customization')
        with self.assertRaisesRegex(office.SyncError, 'Vendor drift'):
            legacy.plan(self.source, self.host, after)

    def test_oversized_mirror_drift_is_rejected_before_allocating_file_contents(self):
        path = self.host / legacy.PREFIX / 'lib/legacy_doc_parser.dart'
        with path.open('wb') as stream:
            stream.truncate(65 * 1024 * 1024)
        original = Path.read_bytes
        def checked_read(candidate):
            if candidate == path:
                self.fail('oversized mirror drift was read into memory')
            return original(candidate)
        with mock.patch.object(Path, 'read_bytes', checked_read):
            with self.assertRaisesRegex(office.SyncError, 'vendor drift'):
                legacy.plan(self.source, self.host, self.before)

    def test_upstream_metadata_symlink_is_rejected_before_following_it(self):
        path = self.host / legacy.PREFIX / 'UPSTREAM.json'
        outside = self.base / 'metadata.json'
        outside.write_bytes(path.read_bytes())
        path.unlink()
        path.symlink_to(outside)
        with self.assertRaisesRegex(office.SyncError, 'unsafe legacy parser upstream metadata'):
            legacy.plan(self.source, self.host, self.before)

    def test_git_pin_or_missing_override_cannot_misdescribe_runtime(self):
        after = self.update()
        path = self.host / 'pubspec.yaml'
        original = path.read_text()
        for changed in (original.replace(self.before, '0' * 40),
                        original.replace('    path: packages/legacy_doc_parser', '    path: elsewhere')):
            path.write_text(changed)
            with self.assertRaisesRegex(office.SyncError, 'Git dependency'):
                legacy.plan(self.source, self.host, after)

    def test_source_symlinks_are_rejected_before_installation(self):
        (self.source / 'lib/link.dart').symlink_to('../LICENSE')
        after = self.commit(self.source)
        with self.assertRaisesRegex(office.SyncError, 'Unsupported standalone source entry'):
            legacy.plan(self.source, self.host, after)

    def test_generated_package_outputs_are_not_treated_as_source_patches(self):
        self.write(self.host, f'{legacy.PREFIX}/.dart_tool/package_config.json', b'{}')
        self.write(self.host, f'{legacy.PREFIX}/build/check.js', b'generated')
        self.write(self.host, f'{legacy.PREFIX}/pubspec.lock', b'generated lock')
        self.assertEqual(legacy.plan(self.source, self.host, self.before)['deletes'], [])

    def test_body_size_limit_is_checked_before_reading_the_blob(self):
        def fake_git(source, *args, **kwargs):
            if args[0] == 'rev-parse':
                return (self.before + '\n').encode()
            if args[0] == 'ls-tree':
                return f'100644 blob {"f" * 40} {64 * 1024 * 1024 + 1}\tlib/large.dart\0'.encode()
            self.fail('oversized source blob was read')
        with mock.patch.object(office, 'git', fake_git):
            with self.assertRaisesRegex(office.SyncError, 'byte limit'):
                legacy.source_tree(self.source, self.before)

    def test_later_quds_sync_preserves_independent_parser_even_if_suite_changes_it(self):
        after = self.update()
        office.apply(self.host, legacy.plan(self.source, self.host, after))
        self.write(self.quds, self.quds_name, b'Quds after\n')
        self.write(self.quds, f'{legacy.PREFIX}/lib/legacy_doc_parser.dart', b'stale suite parser')
        self.write(self.quds, f'{legacy.PREFIX}/lib/suite_only.dart', b'not standalone source')
        target = self.commit(self.quds)
        change = office.plan(self.quds, self.host, target)
        self.assertEqual(set(change['writes']), {self.quds_name})
        office.apply(self.host, change)
        self.assertEqual((self.host / legacy.PREFIX / 'lib/legacy_doc_parser.dart').read_bytes(), b'new parser\n')
        self.assertFalse((self.host / legacy.PREFIX / 'lib/suite_only.dart').exists())
        self.assertEqual(verifier.verify(self.host, self.quds, self.source)[1], [])

    def test_standalone_boundary_cannot_exclude_quds_from_checks(self):
        manifest = dict(self.manifest, standalone_sources={
            'packages/quds_office_engine': {'repository': legacy.REPOSITORY, 'commit': self.before}})
        self.write_manifest(manifest)
        with self.assertRaisesRegex(office.SyncError, 'source boundary'):
            verifier.verify(self.host)

    def test_verifier_rejects_pin_inventory_and_upstream_byte_mismatches(self):
        after = self.update()
        office.apply(self.host, legacy.plan(self.source, self.host, after))
        metadata = self.host / legacy.PREFIX / 'UPSTREAM.json'
        original = metadata.read_bytes()
        metadata.write_bytes(original.replace(after.encode(), self.before.encode()))
        with self.assertRaisesRegex(office.SyncError, 'metadata disagrees'):
            verifier.verify(self.host)
        metadata.write_bytes(original)
        manifest_path = self.host / 'tool/office_fidelity_manifest.json'
        manifest = json.loads(manifest_path.read_text())
        del manifest['files'][f'{legacy.PREFIX}/doc/new.md']
        self.write_manifest(manifest)
        failures = verifier.verify(self.host, legacy_source=self.source)[1]
        self.assertIn('standalone parser mirror inventory mismatch', failures)
        self.assertIn(f'standalone parser source mismatch at {after}', failures)


if __name__ == '__main__':
    unittest.main()
