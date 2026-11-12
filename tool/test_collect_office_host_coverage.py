"""Adversarial controls for host source/run-bound LCOV provenance."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import collect_office_host_coverage as collector
import office_host_coverage as reporter
from collect_office_host_coverage import CollectionError, LCOV, RECEIPT, collect, digest, verify_receipt
from office_host_coverage import report_file


# Real child processes exercise exit status, output creation and mutation. No
# Flutter installation, package downloads or imported production decoder needed.
FAKE_FLUTTER = '''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
if sys.argv[1:] == ['--version', '--machine']:
    print(json.dumps({'frameworkVersion': 'test-protocol-fixture'}))
    raise SystemExit(0)
assert sys.argv[1:4] == ['test', '--no-pub', '--coverage']
output = Path(next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--coverage-path=')))
if '--no-output' not in sys.argv:
    output.write_text('SF:lib/services/office_document_service.dart\\nDA:1,1\\nDA:2,0\\nLF:2\\nLH:1\\nend_of_record\\n'
                      'SF:lib/widgets/office_editor_ribbon.dart\\nDA:1,1\\nLF:1\\nLH:1\\nend_of_record\\n')
if '--bad-output' in sys.argv:
    output.write_text('SF:lib/services/office_document_service.dart\\nDA:99,1\\n')
if '--contradictory-output' in sys.argv:
    output.write_text(output.read_text().replace('LF:2\\nLH:1', 'LF:100\\nLH:100'))
if '--truncated-output' in sys.argv:
    output.write_text(output.read_text().removesuffix('end_of_record\\n'))
if '--partial-output' in sys.argv:
    output.write_text(output.read_text().split('SF:lib/widgets/')[0])
if '--change-source' in sys.argv:
    Path('lib/services/office_document_service.dart').write_text('new\\ntwo\\nthree\\n')
if '--change-test' in sys.argv:
    Path('test/support/source.xml').write_text('<changed/>')
if '--change-asset' in sys.argv:
    Path('assets/fonts/Roboto-Regular.ttf').write_text('changed font')
if '--change-vendor' in sys.argv:
    Path('packages/quds_office_engine/lib/engine.dart').write_text('changed vendor')
if '--change-runtime' in sys.argv:
    executable = Path(__file__)
    executable.write_text(executable.read_text() + '\\n# runtime changed\\n')
if '--symlink-output' in sys.argv:
    external = Path('external.info').resolve()
    external.write_bytes(output.read_bytes())
    output.unlink()
    output.symlink_to(external)
raise SystemExit(3 if '--fail' in sys.argv else 0)
'''


class HostCollectionControls(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.root = self.workspace / 'host'
        for name, content in {
            'lib/services/office_document_service.dart': 'old\ntwo\nthree\n',
            'lib/widgets/office_editor_ribbon.dart': 'one\ntwo\nthree\n',
            'lib/models/shared.dart': 'shared host dependency',
            'test/office_test.dart': 'authored host scenario',
            'test/support/source.xml': '<authored/>',
            'assets/fonts/Roboto-Regular.ttf': 'shipped font fixture',
            'assets/images/app_icon.png': 'shipped image fixture',
            'tool/office_smoke.py': 'host tool',
            'tool/with_ci_system_sqlite.py': 'native runtime override',
            'tool/sync_legacy_doc_parser.py': 'independent parser source guard',
            'tool/test_sync_legacy_doc_parser.py': 'parser source guard tests',
            'pubspec.yaml': 'name: host\n',
            'pubspec.lock': 'locked dependencies',
            '.fvmrc': '{"flutter":"test-version"}',
            '.dart_tool/package_config.json': '{"packages":[]}',
            'packages/quds_office_engine/lib/engine.dart': 'pinned engine',
            'packages/quds_office_editor/lib/editor.dart': 'pinned editor',
            'packages/quds_office_engine/lib/unpinned.dart': 'legacy vendor source',
            'packages/quds_office_engine/test/vendor_test.dart': 'vendored scenario',
            'packages/quds_office_editor/example/fonts/fixture.ttf': 'font fixture',
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        for module in ('collect_office_host_coverage.py', 'office_host_coverage.py'):
            shutil.copyfile(Path(collector.__file__).parent / module, self.root / 'tool' / module)
        pinned = ('packages/quds_office_engine/lib/engine.dart',
                  'packages/quds_office_editor/lib/editor.dart')
        self.manifest = self.root / 'tool/office_fidelity_manifest.json'
        self.manifest.write_text(json.dumps({
            'source_repository': 'CrispStrobe/quds_office_suite',
            'source_commit': 'a' * 40,
            'files': {name: digest(self.root / name) for name in pinned},
        }))
        self.flutter = self.workspace / 'fake-flutter'
        self.flutter.write_text(FAKE_FLUTTER)
        self.flutter.chmod(0o755)
        self.directory = self.root / 'build/fresh'

    def run_collection(self, *arguments):
        return collect(self.directory, self.root, str(self.flutter), arguments)

    def read_receipt(self):
        return json.loads((self.directory / RECEIPT).read_text())

    def assert_no_receipt(self):
        self.assertFalse((self.directory / RECEIPT).exists())

    def test_real_child_success_binds_sources_vendor_config_runtime_and_lcov(self):
        receipt = self.run_collection('test/office_test.dart')
        self.assertEqual(receipt['status'], 'complete')
        self.assertEqual(receipt['returncode'], 0)
        for name in ('pubspec.lock', '.fvmrc', '.dart_tool/package_config.json',
                     'test/support/source.xml', 'lib/models/shared.dart',
                     'assets/fonts/Roboto-Regular.ttf', 'assets/images/app_icon.png',
                     'packages/quds_office_engine/lib/engine.dart',
                     'packages/quds_office_engine/lib/unpinned.dart',
                     'packages/quds_office_editor/example/fonts/fixture.ttf',
                     'tool/with_ci_system_sqlite.py',
                     'tool/sync_legacy_doc_parser.py',
                     'tool/test_sync_legacy_doc_parser.py'):
            self.assertIn(name, receipt['input_sha256'])
        self.assertEqual(receipt['coverage_sha256'], {LCOV: digest(self.directory / LCOV)})
        self.assertIn('test-protocol-fixture', receipt['runtime']['version'])
        report = report_file(self.directory / LCOV, self.root)
        self.assertTrue(report['collection']['verified'])
        self.assertEqual((report['covered_lines'], report['instrumented_lines']), (2, 3))
        self.assertEqual(report['uninstrumented_files'], [])

    def test_same_length_host_edit_cannot_relabel_old_hits(self):
        self.run_collection()
        (self.root / 'lib/services/office_document_service.dart').write_text('new\ntwo\nthree\n')
        for require in (True, False):
            with self.subTest(require=require), self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
                report_file(self.directory / LCOV, self.root, require_receipt=require)

    def test_changed_fixture_tool_lock_or_shared_import_rejects_old_lcov(self):
        self.run_collection()
        for name in ('test/office_test.dart', 'test/support/source.xml',
                     'tool/office_smoke.py', 'tool/with_ci_system_sqlite.py',
                     'tool/sync_legacy_doc_parser.py',
                     'tool/test_sync_legacy_doc_parser.py',
                     'pubspec.lock', 'pubspec.yaml', '.fvmrc',
                     '.dart_tool/package_config.json', 'lib/models/shared.dart',
                     'assets/fonts/Roboto-Regular.ttf', 'assets/images/app_icon.png',
                     'packages/quds_office_engine/test/vendor_test.dart',
                     'packages/quds_office_editor/example/fonts/fixture.ttf'):
            path = self.root / name
            original = path.read_bytes()
            with self.subTest(name=name):
                try:
                    path.write_bytes(original + b'!')
                    with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
                        verify_receipt(self.directory / LCOV, self.root)
                finally:
                    path.write_bytes(original)

    def test_manifest_hash_does_not_substitute_for_actual_vendor_contents(self):
        self.run_collection()
        (self.root / 'packages/quds_office_engine/lib/engine.dart').write_text('drifted engine')
        with self.assertRaisesRegex(CollectionError, 'Vendor drift'):
            verify_receipt(self.directory / LCOV, self.root)

    def test_legacy_unpinned_vendor_change_and_repin_both_reject_old_hits(self):
        self.run_collection()
        unpinned = self.root / 'packages/quds_office_engine/lib/unpinned.dart'
        old = unpinned.read_bytes()
        unpinned.write_text('different legacy code')
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            verify_receipt(self.directory / LCOV, self.root)
        unpinned.write_bytes(old)
        source = self.root / 'packages/quds_office_engine/lib/engine.dart'
        source.write_text('new correctly pinned version')
        manifest = json.loads(self.manifest.read_text())
        manifest['files'][source.relative_to(self.root).as_posix()] = digest(source)
        self.manifest.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            verify_receipt(self.directory / LCOV, self.root)

    def test_added_and_deleted_input_reject_old_hits(self):
        self.run_collection()
        added = self.root / 'lib/services/office_new.dart'
        added.write_text('new source')
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            verify_receipt(self.directory / LCOV, self.root)
        added.unlink()
        (self.root / 'test/office_test.dart').unlink()
        with self.assertRaisesRegex(CollectionError, 'no longer match collected sources'):
            verify_receipt(self.directory / LCOV, self.root)

    def test_modified_or_missing_lcov_cannot_pass(self):
        self.run_collection()
        path = self.directory / LCOV
        original = path.read_bytes()
        path.write_bytes(original.replace(b'DA:2,0', b'DA:2,1'))
        with self.assertRaisesRegex(CollectionError, 'LCOV no longer matches'):
            verify_receipt(path, self.root)
        path.unlink()
        with self.assertRaisesRegex(CollectionError, 'LCOV no longer matches'):
            verify_receipt(path, self.root)

    def test_report_rechecks_source_and_lcov_after_parsing(self):
        self.run_collection()
        original_parser = reporter.report_coverage
        for path, replacement in (
                (self.root / 'lib/services/office_document_service.dart', b'new\ntwo\nthree\n'),
                (self.directory / LCOV, b'changed LCOV')):
            original = path.read_bytes()

            def parse_then_mutate(lcov, root):
                report = original_parser(lcov, root)
                path.write_bytes(replacement)
                return report

            with self.subTest(path=path):
                try:
                    with patch.object(reporter, 'report_coverage', side_effect=parse_then_mutate):
                        with self.assertRaises(CollectionError):
                            report_file(self.directory / LCOV, self.root)
                finally:
                    path.write_bytes(original)

    def test_collector_rechecks_inputs_and_output_before_sealing(self):
        original_parser = reporter.report_coverage
        source = self.root / 'lib/services/office_document_service.dart'
        original_source = source.read_bytes()
        for target in ('source', 'lcov'):
            self.directory = self.root / 'build' / ('validation-change-' + target)

            def parse_then_mutate(lcov, root):
                report = original_parser(lcov, root)
                path = source if target == 'source' else self.directory / LCOV
                path.write_text('new\ntwo\nthree\n' if target == 'source' else 'changed LCOV')
                return report

            with self.subTest(target=target):
                try:
                    with patch.object(reporter, 'report_coverage', side_effect=parse_then_mutate):
                        with self.assertRaisesRegex(CollectionError, 'changed during'):
                            self.run_collection()
                    self.assert_no_receipt()
                finally:
                    source.write_bytes(original_source)

    def test_failed_test_does_not_issue_receipt_even_with_valid_lcov(self):
        with self.assertRaisesRegex(CollectionError, 'exit code 3'):
            self.run_collection('--fail')
        self.assertTrue((self.directory / LCOV).is_file())
        self.assert_no_receipt()

    def test_source_test_or_vendor_mutation_during_success_never_issues_receipt(self):
        for argument, message in (('--change-source', 'changed during tests'),
                                  ('--change-test', 'changed during tests'),
                                  ('--change-asset', 'changed during tests'),
                                  ('--change-vendor', 'Vendor drift')):
            with self.subTest(argument=argument):
                self.directory = self.root / 'build' / argument[2:]
                before = {path: path.read_bytes() for path in (
                    self.root / 'lib/services/office_document_service.dart',
                    self.root / 'test/support/source.xml',
                    self.root / 'assets/fonts/Roboto-Regular.ttf',
                    self.root / 'packages/quds_office_engine/lib/engine.dart')}
                try:
                    with self.assertRaisesRegex(CollectionError, message):
                        self.run_collection(argument)
                    self.assert_no_receipt()
                finally:
                    for path, data in before.items():
                        path.write_bytes(data)

    def test_missing_malformed_or_symlinked_output_cannot_be_sealed(self):
        for argument in ('--no-output', '--bad-output', '--symlink-output',
                         '--contradictory-output', '--truncated-output'):
            with self.subTest(argument=argument):
                self.directory = self.root / 'build' / argument[2:]
                with self.assertRaises(ValueError):
                    self.run_collection(argument)
                self.assert_no_receipt()

    def test_changed_runtime_is_not_sealed(self):
        with self.assertRaisesRegex(CollectionError, 'executable changed'):
            self.run_collection('--change-runtime')
        self.assert_no_receipt()

    def test_runtime_or_run_provenance_cannot_be_missing_or_inconsistent(self):
        self.run_collection()
        original = self.read_receipt()
        cases = []
        for key, value in [('schema_version', True), ('returncode', False),
                           ('returncode', 1), ('status', 'running')]:
            case = copy.deepcopy(original)
            case[key] = value
            cases.append(case)
        for key, value in [('version', ''), ('sha256', 'invalid'), ('executable', '/other/flutter')]:
            case = copy.deepcopy(original)
            case['runtime'][key] = value
            cases.append(case)
        case = copy.deepcopy(original)
        case['command'].append('--coverage-path=old.info')
        cases.append(case)
        for case in cases:
            with self.subTest(case=case['runtime']):
                (self.directory / RECEIPT).write_text(json.dumps(case))
                with self.assertRaises(CollectionError):
                    verify_receipt(self.directory / LCOV, self.root)

    def test_empty_and_occupied_destinations_are_never_reused_or_removed(self):
        self.directory.mkdir(parents=True)
        with self.assertRaisesRegex(CollectionError, 'already exists'):
            self.run_collection()
        keep = self.directory / 'keep.txt'
        keep.write_text('existing evidence')
        with self.assertRaisesRegex(CollectionError, 'already exists'):
            self.run_collection()
        self.assertEqual(keep.read_text(), 'existing evidence')
        self.assert_no_receipt()

    def test_output_override_and_pub_resolution_flags_are_rejected(self):
        for arguments in (('--coverage',), ('--no-coverage',), ('--pub',),
                          ('--coverage-path', 'old.info'), ('--coverage-path=old.info',),
                          ('--merge-coverage',), ('--no-merge-coverage',)):
            with self.subTest(arguments=arguments), self.assertRaisesRegex(CollectionError, 'collector owns'):
                self.run_collection(*arguments)
            self.assertFalse(self.directory.exists())

    def test_source_and_symlink_destinations_are_rejected(self):
        self.directory = self.root / 'test/coverage'
        with self.assertRaisesRegex(CollectionError, 'outside source'):
            self.run_collection()
        outside = self.workspace / 'outside'
        outside.mkdir()
        link = self.root / 'linked-output'
        link.symlink_to(outside, target_is_directory=True)
        self.directory = link / 'new'
        with self.assertRaisesRegex(CollectionError, 'Symlink'):
            self.run_collection()
        self.assertFalse((outside / 'new').exists())

    def test_missing_lockfile_or_vendor_drift_fails_before_collection(self):
        (self.root / 'pubspec.lock').unlink()
        with self.assertRaisesRegex(CollectionError, 'Missing resolved collection input'):
            self.run_collection()
        (self.root / 'pubspec.lock').write_text('restored')
        (self.root / 'packages/quds_office_editor/lib/editor.dart').write_text('drift')
        with self.assertRaisesRegex(CollectionError, 'Vendor drift'):
            self.run_collection()
        self.assertFalse(self.directory.exists())

    def test_symlinked_source_and_receipt_are_rejected(self):
        source = self.root / 'lib/services/office_document_service.dart'
        external = self.workspace / 'original.dart'
        source.rename(external)
        source.symlink_to(external)
        with self.assertRaisesRegex(CollectionError, 'Symlink'):
            self.run_collection()
        self.assertFalse(self.directory.exists())
        source.unlink()
        external.rename(source)
        self.run_collection()
        receipt = self.directory / RECEIPT
        saved = self.workspace / 'saved-receipt.json'
        receipt.rename(saved)
        receipt.symlink_to(saved)
        with self.assertRaisesRegex(CollectionError, 'Symlink'):
            report_file(self.directory / LCOV, self.root, require_receipt=False)

    def test_vendor_manifest_cannot_escape_the_host(self):
        self.manifest.write_text(json.dumps({'files': {'../outside.dart': 'a' * 64}}))
        with self.assertRaisesRegex(CollectionError, 'Invalid vendor path'):
            self.run_collection()
        self.assertFalse(self.directory.exists())

    def test_reporter_cli_is_strict_by_default_with_explicit_historical_mode(self):
        self.run_collection()
        receipt = self.directory / RECEIPT
        original = receipt.read_bytes()
        receipt.unlink()
        command = [sys.executable, str(self.root / 'tool/office_host_coverage.py'),
                   str(self.directory / LCOV), '--output', str(self.root / 'build/report.json')]
        run = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('Missing collection receipt', run.stderr)
        run = subprocess.run([*command, '--allow-unverified'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertFalse(json.loads((self.root / 'build/report.json').read_text())['collection']['verified'])
        receipt.write_bytes(original)
        run = subprocess.run([*command, '--require-receipt'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertTrue(json.loads((self.root / 'build/report.json').read_text())['collection']['verified'])
        (self.directory / LCOV).write_text('corrupt')
        run = subprocess.run([*command, '--allow-unverified'], cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('LCOV no longer matches', run.stderr)
        failed = json.loads((self.root / 'build/report.json').read_text())
        self.assertEqual(failed['status'], 'failed')
        self.assertFalse(failed['collection']['verified'])
        self.assertNotIn('covered_lines', failed)

    def test_reporter_requires_all_sources_before_publishing_success(self):
        self.run_collection('--partial-output')
        output = self.directory / 'gaps.json'
        command = [sys.executable, str(self.root / 'tool/office_host_coverage.py'),
                   str(self.directory / LCOV), '--output', str(output)]
        run = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(output.read_text())['status'], 'complete')
        run = subprocess.run([*command, '--require-all-sources'], cwd=self.root,
                             capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        failed = json.loads(output.read_text())
        self.assertEqual(failed['status'], 'failed')
        self.assertFalse(failed['collection']['verified'])
        self.assertIn('lib/widgets/office_editor_ribbon.dart', failed['error'])
        self.assertNotIn('covered_lines', failed)

    def test_interrupted_report_cannot_retain_old_verified_summary(self):
        output = self.root / 'build/report.json'
        output.parent.mkdir(parents=True)
        output.write_text(json.dumps({'status': 'complete', 'collection': {'verified': True}}))
        with patch.object(reporter, 'report_file', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                reporter.main([str(self.directory / LCOV), '--output', str(output)])
        pending = json.loads(output.read_text())
        self.assertEqual(pending['status'], 'pending')
        self.assertFalse(pending['collection']['verified'])

    def test_report_output_cannot_overwrite_raw_evidence_or_aliases(self):
        self.run_collection()
        for path in (self.directory / LCOV, self.directory / RECEIPT):
            original = path.read_bytes()
            alias = self.directory / ('alias-' + path.name)
            alias.symlink_to(path)
            for output in (path, alias):
                with self.subTest(output=output):
                    run = subprocess.run(
                        [sys.executable, str(self.root / 'tool/office_host_coverage.py'),
                         str(self.directory / LCOV), '--output', str(output)],
                        cwd=self.root, capture_output=True, text=True)
                    self.assertNotEqual(run.returncode, 0)
                    self.assertIn('must not overwrite raw LCOV', run.stderr)
                    self.assertEqual(path.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
