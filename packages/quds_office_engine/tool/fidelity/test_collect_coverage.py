"""Adversarial controls for successful-run and exact-source coverage receipts."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from collect_coverage import CollectionError, RECEIPT, collect, verify_receipt
import coverage_report as reporter
from coverage_report import report_coverage


# A real child process follows the Dart command protocol while keeping controls
# independent of Flutter installation, package resolution and network access.
FAKE_DART = '''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
if sys.argv[1:] == ['--version']:
    print('Dart SDK version: test-protocol-fixture')
    raise SystemExit(0)
assert sys.argv[1] == 'test'
output = Path(next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--coverage=')))
if '--no-output' not in sys.argv:
    output.joinpath('word.vm.json').write_text(json.dumps({'coverage': [
        {'source': 'package:quds_office_engine/src/word/document.dart', 'hits': [1, 1, 2, 0]}
    ]}))
if '--change-source' in sys.argv:
    Path('lib/src/word/document.dart').write_text('new\\ntwo\\nthree\\n')
if '--bad-output' in sys.argv:
    output.joinpath('word.vm.json').write_text('{}')
raise SystemExit(2 if '--fail' in sys.argv else 0)
'''


class BoundCollectionControls(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.root = self.workspace / 'packages/quds_office_engine'
        for name, value in {
            'lib/src/word/document.dart': 'old\ntwo\nthree\n',
            'test/word_test.dart': 'authored test',
            'test/fixtures/input.xml': '<authored/>',
            'tool/fidelity/steps.json': '[{"op":"heading"}]',
            'pubspec.yaml': 'name: quds_office_engine\n',
            'example/document.dart': 'imported example',
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
        (self.workspace / 'pubspec.lock').write_text('locked dependencies')
        self.dart = self.workspace / 'fake-dart'
        self.dart.write_text(FAKE_DART)
        self.dart.chmod(0o755)
        self.directory = self.root / 'coverage/fresh'

    def run_collection(self, *arguments):
        return collect(self.directory, self.root, str(self.dart), arguments)

    def receipt(self):
        return json.loads((self.directory / RECEIPT).read_text())

    def test_real_child_success_seals_sources_lockfile_runtime_and_hits(self):
        receipt = self.run_collection('test/word_test.dart')
        self.assertEqual(receipt['status'], 'complete')
        self.assertEqual(receipt['returncode'], 0)
        self.assertIn('workspace/pubspec.lock', receipt['input_sha256'])
        self.assertIn('engine/test/fixtures/input.xml', receipt['input_sha256'])
        self.assertIn('engine/example/document.dart', receipt['input_sha256'])
        self.assertEqual(list(receipt['coverage_sha256']), ['word.vm.json'])
        self.assertIn('test-protocol-fixture', receipt['runtime']['version'])
        report = report_coverage(self.directory, self.root, require_receipt=True)
        self.assertTrue(report['collection']['verified'])
        self.assertEqual(report['covered_lines'], 1)
        self.assertEqual(report['files'][0]['uncovered_lines'], [2])
        self.assertEqual(report['collection']['command'][2], 'test/word_test.dart')

    def test_same_length_source_edit_cannot_relabel_old_hits(self):
        self.run_collection()
        (self.root / 'lib/src/word/document.dart').write_text('new\ntwo\nthree\n')
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            report_coverage(self.directory, self.root, require_receipt=True)
        # An invalid existing receipt cannot be bypassed by the historical mode.
        with self.assertRaises(CollectionError):
            report_coverage(self.directory, self.root, require_receipt=False)

    def test_changed_test_fixture_lockfile_or_example_rejects_old_hits(self):
        self.run_collection()
        for path in (self.root / 'test/word_test.dart',
                     self.root / 'test/fixtures/input.xml',
                     self.root / 'tool/fidelity/steps.json',
                     self.root / 'example/document.dart',
                     self.workspace / 'pubspec.lock'):
            original = path.read_bytes()
            with self.subTest(path=path):
                path.write_bytes(original + b'!')
                with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
                    verify_receipt(self.directory, self.root)
                path.write_bytes(original)
        self.assertTrue(verify_receipt(self.directory, self.root)['verified'])

    def test_added_or_missing_source_rejects_old_hits(self):
        self.run_collection()
        added = self.root / 'lib/new.dart'
        added.write_text('new source')
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            verify_receipt(self.directory, self.root)
        added.unlink()
        removed = self.root / 'test/word_test.dart'
        removed.unlink()
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            verify_receipt(self.directory, self.root)

    def test_replaced_missing_or_extra_hits_cannot_pass(self):
        self.run_collection()
        original = self.directory / 'word.vm.json'
        data = original.read_bytes()
        for damage in ('replace', 'remove', 'extra'):
            with self.subTest(damage=damage):
                if damage == 'replace':
                    original.write_bytes(data.replace(b'2, 0', b'2, 1'))
                elif damage == 'remove':
                    original.unlink()
                else:
                    (self.directory / 'stale.vm.json').write_bytes(data)
                with self.assertRaisesRegex(CollectionError, 'no longer match successful collection'):
                    verify_receipt(self.directory, self.root)
                original.write_bytes(data)
                (self.directory / 'stale.vm.json').unlink(missing_ok=True)

    def test_empty_or_occupied_directory_is_not_reused_or_deleted(self):
        self.directory.mkdir(parents=True)
        with self.assertRaisesRegex(CollectionError, 'already exists'):
            self.run_collection()
        sentinel = self.directory / 'keep.txt'
        sentinel.write_text('keep')
        with self.assertRaisesRegex(CollectionError, 'already exists'):
            self.run_collection()
        self.assertEqual(sentinel.read_text(), 'keep')
        self.assertFalse((self.directory / RECEIPT).exists())

    def test_failed_run_cannot_issue_complete_receipt_even_with_valid_hits(self):
        with self.assertRaisesRegex(CollectionError, 'exit code 2'):
            self.run_collection('--fail')
        self.assertTrue((self.directory / 'word.vm.json').is_file())
        self.assertEqual(self.receipt()['status'], 'failed')
        self.assertEqual(self.receipt()['returncode'], 2)
        with self.assertRaisesRegex(CollectionError, 'did not complete successfully'):
            verify_receipt(self.directory, self.root)

    def test_source_change_during_test_invalidates_successful_exit(self):
        with self.assertRaisesRegex(CollectionError, 'changed during tests'):
            self.run_collection('--change-source')
        self.assertEqual(self.receipt()['status'], 'failed')
        self.assertEqual(self.receipt()['returncode'], 0)

    def test_absent_or_malformed_output_invalidates_successful_exit(self):
        for argument in ('--no-output', '--bad-output'):
            with self.subTest(argument=argument):
                self.directory = self.directory.parent / argument[2:]
                with self.assertRaises(ValueError):
                    self.run_collection(argument)
                self.assertEqual(self.receipt()['status'], 'failed')

    def test_interruption_is_retained_as_failure(self):
        def interrupt(*arguments, **options):
            raise KeyboardInterrupt('interrupted control')
        with self.assertRaises(KeyboardInterrupt):
            collect(self.directory, self.root, str(self.dart), runner=interrupt)
        self.assertEqual(self.receipt()['status'], 'failed')
        self.assertIn('KeyboardInterrupt', self.receipt()['error'])
        with self.assertRaisesRegex(CollectionError, 'did not complete successfully'):
            verify_receipt(self.directory, self.root)

    def test_missing_receipt_is_explicitly_unverified_and_strict_mode_fails(self):
        self.run_collection()
        (self.directory / RECEIPT).unlink()
        report = report_coverage(self.directory, self.root)
        self.assertFalse(report['collection']['verified'])
        with self.assertRaisesRegex(CollectionError, 'Missing collection receipt'):
            report_coverage(self.directory, self.root, require_receipt=True)

    def test_source_or_hits_changed_after_initial_verification_are_rejected(self):
        self.run_collection()
        source = self.root / 'lib/src/word/document.dart'
        hits = self.directory / 'word.vm.json'
        for path, replacement in ((source, b'new\ntwo\nthree\n'),
                                  (hits, hits.read_bytes().replace(b'2, 0', b'2, 1'))):
            original = path.read_bytes()
            calls = 0
            def verified_then_changed(directory, root):
                nonlocal calls
                result = verify_receipt(directory, root)
                calls += 1
                if calls == 1:
                    path.write_bytes(replacement)
                return result
            with self.subTest(path=path):
                try:
                    with patch.object(reporter, 'verify_receipt', side_effect=verified_then_changed):
                        with self.assertRaises(CollectionError):
                            report_coverage(self.directory, self.root, require_receipt=True)
                finally:
                    path.write_bytes(original)

    def test_failed_cli_rerun_replaces_old_success_at_the_requested_report_path(self):
        for name in ('coverage_report.py', 'collect_coverage.py'):
            shutil.copyfile(Path(reporter.__file__).with_name(name), self.root / 'tool/fidelity' / name)
        self.run_collection()
        output = self.root / 'build/report.json'
        command = [sys.executable, str(self.root / 'tool/fidelity/coverage_report.py'),
                   str(self.directory), '--output', str(output)]
        first = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue(json.loads(output.read_text())['collection']['verified'])
        # Invalidating a requested report must never overwrite raw evidence.
        for protected in (self.directory / RECEIPT, self.directory / 'word.vm.json'):
            before = protected.read_bytes()
            rejected = subprocess.run([*command[:-1], str(protected)], cwd=self.root,
                                      capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('outside the raw coverage directory', rejected.stderr)
            self.assertEqual(protected.read_bytes(), before)
        hits = self.directory / 'word.vm.json'
        hits.write_bytes(hits.read_bytes().replace(b'2, 0', b'2, 1'))
        second = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn('no longer match successful collection', second.stderr)
        failed = json.loads(output.read_text())
        self.assertEqual(failed.get('status'), 'failed')
        self.assertFalse(failed['collection']['verified'])
        self.assertNotIn('covered_lines', failed)

    def test_command_or_snapshot_metadata_damage_is_not_accepted(self):
        self.run_collection()
        path = self.directory / RECEIPT
        original = path.read_text()
        for field, value in (('command', ['dart', 'test', '--coverage=elsewhere']),
                             ('input_tree_sha256', '0' * 64),
                             ('returncode', False), ('status', 'running')):
            with self.subTest(field=field):
                receipt = json.loads(original)
                receipt[field] = value
                path.write_text(json.dumps(receipt))
                with self.assertRaises(CollectionError):
                    verify_receipt(self.directory, self.root)
                path.write_text(original)

    def test_coverage_override_or_source_destination_fails_before_mutation(self):
        for arguments in (('--coverage=somewhere',), ('--coverage', 'somewhere')):
            with self.subTest(arguments=arguments):
                with self.assertRaisesRegex(CollectionError, 'owns --coverage'):
                    self.run_collection(*arguments)
                self.assertFalse(self.directory.exists())
        for folder in ('lib', 'test', 'tool', 'example'):
            destination = self.root / folder / 'coverage'
            with self.subTest(folder=folder):
                with self.assertRaisesRegex(CollectionError, 'outside source/input'):
                    collect(destination, self.root, str(self.dart))
                self.assertFalse(destination.exists())

    def test_symlinked_inputs_destination_and_evidence_are_rejected(self):
        outside = self.workspace / 'outside.txt'
        outside.write_text('unchanged')
        link = self.root / 'lib/linked.dart'
        link.symlink_to(outside)
        with self.assertRaisesRegex(CollectionError, 'Symlink'):
            self.run_collection()
        self.assertFalse(self.directory.exists())
        link.unlink()
        self.run_collection()
        output = self.directory / 'linked.vm.json'
        output.symlink_to(outside)
        with self.assertRaisesRegex(CollectionError, 'Symlink'):
            verify_receipt(self.directory, self.root)
        self.assertEqual(outside.read_text(), 'unchanged')


if __name__ == '__main__':
    unittest.main()
