"""Reject false-green selections, stale outputs and unsafe feature plans."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from zipfile import BadZipFile, ZipFile

import feature_matrix as matrix


class FeatureMatrixControls(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.workspace = Path(temporary.name)
        self.root = self.workspace / 'packages/quds_office_engine'
        self.editor = self.root.parent / 'quds_office_editor'
        for name in ('lib/document.dart', 'test/alpha_test.dart', 'test/beta_test.dart',
                     'tool/fidelity/check_oracle.py', 'tool/fidelity/test_check_oracle.py',
                     'tool/fidelity/corpus.py'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('authored source\n')
        (self.root / 'pubspec.yaml').write_text('name: quds_office_engine\n')
        for name in ('test/page_test.dart', 'test/goldens/page.png'):
            path = self.editor / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'authored golden')
        self.manifest = {'version': 1, 'package': 'quds_office_engine',
                         'expected_file_count': 6, 'standalone': [],
                         'series': [{'pattern': f'fidelity-{name}/output-{{cycle}}.docx',
                                     'cycles': [1, 2, 3], 'producer': f'test/{name}_test.dart'}
                                    for name in ('alpha', 'beta')]}
        self.manifest_path = self.root / 'tool/fidelity/output_manifest.json'
        self.manifest_path.write_text(json.dumps(self.manifest))
        bundle = {'tests': ['test/alpha_test.dart'], 'scripts': [],
                  'oracles': [['tool/fidelity/check_oracle.py']],
                  'controls': ['tool/fidelity/test_check_oracle.py']}
        self.data = {'version': 1,
                     'features': {name: {'description': 'Authored feature',
                                        'bundles': ['alpha'], 'goldens': ['page']}
                                  for name in sorted(matrix.REQUIRED_FEATURES)},
                     'bundles': {'alpha': bundle, 'beta': dict(bundle, tests=['test/beta_test.dart'])},
                     'goldens': {'page': {'tests': ['test/page_test.dart'], 'files': ['test/goldens/page.png']}}}
        self.data['features']['images']['bundles'] = ['alpha', 'beta']
        self.path = self.root / 'tool/fidelity/feature_matrix.json'
        self.write_matrix()
        self.calls = []

    def write_matrix(self):
        self.path.write_text(json.dumps(self.data))

    def output(self, group='alpha', cycle=1):
        return self.root / f'build/fidelity-{group}/output-{cycle}.docx'

    def produce(self, group='alpha'):
        for cycle in range(1, 4):
            path = self.output(group, cycle)
            path.parent.mkdir(parents=True, exist_ok=True)
            with ZipFile(path, 'w') as package:
                package.writestr('[Content_Types].xml', '<Types/>')
                package.writestr('_rels/.rels', '<Relationships/>')
                package.writestr('word/document.xml', f'<document>Authored {cycle}</document>')

    def successful(self, argv, **kwargs):
        self.calls.append(argv)
        self.assertEqual(kwargs, {'cwd': self.root, 'check': False})
        self.assertNotIn('--update-goldens', argv)
        self.assertNotIn('seed', argv)
        if argv[1] == 'test':
            if 'test/alpha_test.dart' in argv:
                self.produce('alpha')
            if 'test/beta_test.dart' in argv:
                self.produce('beta')
        return subprocess.CompletedProcess(argv, 0)

    def run_selection(self, features=('styles',), runner=None):
        return matrix.run(list(features), self.root, self.path, dart=sys.executable,
                          runner=runner or self.successful)

    def test_plan_combines_tests_oracles_controls_and_golden_references_once(self):
        plan = matrix.plan(['styles', 'images'], self.root, self.path)
        tests = [item for item in plan['commands'] if item['stage'] == 'tests']
        self.assertEqual(tests, [{'stage': 'tests', 'argv': [
            'dart', 'test', 'test/alpha_test.dart', 'test/beta_test.dart']}])
        self.assertEqual(len(plan['commands']), 3)
        self.assertEqual(len(plan['expected_outputs']), 6)
        self.assertFalse(plan['editor_goldens']['executed'])
        self.assertEqual(plan['editor_goldens']['files'], ['test/goldens/page.png'])
        self.assertFalse((self.root / 'build').exists())

    def test_success_regenerates_selected_outputs_preserves_unselected_and_hashes_bytes(self):
        self.produce('alpha')
        for cycle in range(1, 4):
            self.output('alpha', cycle).write_text('stale sentinel')
        self.produce('beta')
        unrelated = self.output('beta').read_bytes()
        report, receipt = self.run_selection()
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['features'], ['styles'])
        self.assertEqual(len(report['files']), 3)
        self.assertEqual(self.output('beta').read_bytes(), unrelated)
        self.assertEqual(report['files'][0]['sha256'], hashlib.sha256(self.output().read_bytes()).hexdigest())
        self.assertEqual(json.loads(receipt.read_text())['status'], 'passed')
        self.assertEqual(len(self.calls), 3)
        self.assertFalse((self.root / 'build/fidelity-feature-run.lock').exists())

    def test_empty_unknown_and_duplicate_selection_rejected_without_mutation(self):
        self.produce()
        original = self.output().read_bytes()
        for features in ([], ['unknown'], ['styles', 'styles']):
            with self.subTest(features=features), self.assertRaises(matrix.MatrixError):
                self.run_selection(features)
        self.assertEqual(self.output().read_bytes(), original)
        self.assertFalse(self.calls)

    def test_removing_any_required_feature_rejects_the_whole_matrix(self):
        original = copy.deepcopy(self.data)
        for feature in matrix.REQUIRED_FEATURES:
            with self.subTest(feature=feature):
                self.data = copy.deepcopy(original)
                del self.data['features'][feature]
                self.write_matrix()
                with self.assertRaisesRegex(matrix.MatrixError, 'Missing required features'):
                    matrix.plan(['styles'], self.root, self.path)

    def test_bad_refs_and_malformed_matrix_fail_before_selected_outputs_are_deleted(self):
        self.produce()
        original = self.output().read_bytes()
        baseline = copy.deepcopy(self.data)
        changes = [lambda data: data['features']['styles'].update(bundles=[]),
                   lambda data: data['features']['styles'].update(bundles=['absent']),
                   lambda data: data['features']['styles'].update(goldens=['absent']),
                   lambda data: data['bundles']['alpha'].update(tests=['../escape_test.dart']),
                   lambda data: data['bundles']['alpha'].update(tests=['test/missing_test.dart']),
                   lambda data: data['bundles']['alpha'].update(oracles=[]),
                   lambda data: data['bundles']['alpha'].update(oracles=[['tool/fidelity/corpus.py', 'seed']]),
                   lambda data: data['goldens']['page'].update(files=['test/goldens/missing.png']),
                   lambda data: data.update(version=True)]
        for change in changes:
            self.data = copy.deepcopy(baseline)
            change(self.data)
            self.write_matrix()
            with self.subTest(data=self.data), self.assertRaises(matrix.MatrixError):
                self.run_selection()
            self.assertEqual(self.output().read_bytes(), original)
        self.assertFalse(self.calls)

    def test_duplicate_json_keys_rejected(self):
        self.path.write_text('{"version":1,"version":1}')
        with self.assertRaisesRegex(matrix.MatrixError, 'Duplicate matrix JSON key'):
            matrix.load_matrix(self.root, self.path)

    def test_zero_manifest_outputs_cannot_satisfy_a_bundle(self):
        self.data['bundles']['alpha']['tests'] = []
        self.write_matrix()
        with self.assertRaisesRegex(matrix.MatrixError, 'no manifest outputs'):
            matrix.plan(['styles'], self.root, self.path)

    def test_successful_process_without_outputs_cannot_reuse_stale_evidence(self):
        self.produce()
        def no_output(argv, **kwargs):
            return subprocess.CompletedProcess(argv, 0)
        with self.assertRaisesRegex(matrix.MatrixError, 'Missing/empty selected output'):
            self.run_selection(runner=no_output)
        self.assertFalse(self.output().exists())
        receipt = self.root / 'build/fidelity-features/styles.json'
        self.assertEqual(json.loads(receipt.read_text())['status'], 'failed')

    def test_failed_subprocess_stops_oracles_and_replaces_prior_success(self):
        _, receipt = self.run_selection()
        self.calls.clear()
        def fail(argv, **kwargs):
            self.calls.append(argv)
            self.assertEqual(json.loads(receipt.read_text())['status'], 'running')
            return subprocess.CompletedProcess(argv, 17)
        with self.assertRaisesRegex(matrix.MatrixError, r'tests failed \(17\)'):
            self.run_selection(runner=fail)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(json.loads(receipt.read_text())['status'], 'failed')
        self.assertFalse((self.root / 'build/fidelity-feature-run.lock').exists())

    def test_oracle_failure_is_not_hidden_by_successful_production(self):
        def fail_oracle(argv, **kwargs):
            result = self.successful(argv, **kwargs)
            if 'tool/fidelity/check_oracle.py' in argv:
                result.returncode = 3
            return result
        with self.assertRaisesRegex(matrix.MatrixError, 'oracle failed'):
            self.run_selection(runner=fail_oracle)
        self.assertEqual(len(self.calls), 2)

    def test_interruption_marks_failed_and_releases_its_output_lock(self):
        def interrupt(argv, **kwargs):
            raise KeyboardInterrupt('control interruption')
        with self.assertRaises(KeyboardInterrupt):
            self.run_selection(runner=interrupt)
        receipt = self.root / 'build/fidelity-features/styles.json'
        self.assertEqual(json.loads(receipt.read_text())['status'], 'failed')
        self.assertFalse((self.root / 'build/fidelity-feature-run.lock').exists())

    def test_missing_dart_fails_before_deleting_output(self):
        self.produce()
        original = self.output().read_bytes()
        with self.assertRaisesRegex(matrix.MatrixError, 'Dart executable not found'):
            matrix.run(['styles'], self.root, self.path,
                       dart=str(self.workspace / 'missing-dart'))
        self.assertEqual(self.output().read_bytes(), original)

    def test_corrupt_output_and_source_mutation_cannot_issue_success(self):
        def corrupt(argv, **kwargs):
            result = self.successful(argv, **kwargs)
            self.output().write_text('not a ZIP')
            return result
        with self.assertRaises(BadZipFile):
            self.run_selection(runner=corrupt)
        def change_source(argv, **kwargs):
            result = self.successful(argv, **kwargs)
            (self.root / 'lib/document.dart').write_text('changed source')
            return result
        with self.assertRaisesRegex(matrix.MatrixError, 'inputs changed'):
            self.run_selection(runner=change_source)

    def test_later_unsafe_output_is_preflighted_before_earlier_deletion(self):
        self.produce()
        original = self.output().read_bytes()
        outside = self.workspace / 'outside.docx'
        outside.write_text('keep outside')
        self.output(cycle=3).unlink()
        self.output(cycle=3).symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_selection()
        self.assertEqual(self.output().read_bytes(), original)
        self.assertEqual(outside.read_text(), 'keep outside')
        self.assertFalse(self.calls)

    def test_concurrent_run_lock_prevents_deletion(self):
        self.produce()
        original = self.output().read_bytes()
        (self.root / 'build/fidelity-feature-run.lock').write_text('active run')
        with self.assertRaisesRegex(matrix.MatrixError, 'Another feature run'):
            self.run_selection()
        self.assertEqual(self.output().read_bytes(), original)
        self.assertFalse(self.calls)

    def test_committed_matrix_has_every_requested_feature_and_valid_references(self):
        data, _ = matrix.load_matrix()
        self.assertTrue(matrix.REQUIRED_FEATURES <= set(data['features']))
        plan = matrix.plan(sorted(matrix.REQUIRED_FEATURES))
        self.assertGreater(len(plan['expected_outputs']), 100)
        self.assertEqual(len(plan['editor_goldens']['files']), 27)
        self.assertTrue(all('--update-goldens' not in item['argv'] for item in plan['commands']))


if __name__ == '__main__':
    unittest.main()
