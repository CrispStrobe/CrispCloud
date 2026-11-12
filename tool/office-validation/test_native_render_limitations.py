"""The declared native-only result must never become a blanket render skip."""
from contextlib import nullcontext, redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import render
from test_render import record


def rejection():
    return subprocess.CalledProcessError(
        1, ['soffice'], stderr='Error: source file could not be loaded\n')


class NativeRendererLimitationTests(unittest.TestCase):
    def fixture(self, folder, corpus='fidelity-aux-controls'):
        root = Path(folder) / 'input'
        directory = root / corpus
        directory.mkdir(parents=True)
        paths = {}
        for name in sorted(render.NATIVE_AUX_FILES):
            path = directory / name
            path.write_bytes(('Native fixture bytes for ' + name).encode())
            paths[name] = path
        receipt = Path(folder) / 'schema.json'
        entries = [{'File': str(path), 'Sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'Errors': []} for path in paths.values()]
        receipt.write_text(json.dumps({'Files': len(entries), 'Failures': 0, 'Reports': entries}))
        return root, paths, receipt

    def run_renderer(self, root, *, receipt=None, source_renders=False, drift=False,
                     validate=True, source_error=None, extra_failure=None):
        output = root.parent / 'rendered'

        def convert(path, input_root, destination, index):
            name = path.relative_to(input_root).as_posix()
            if path.name == 'source.docx' and not source_renders:
                raise source_error or rejection()
            if path.name == extra_failure:
                raise rejection()
            text = 'Edited text' if path.name.startswith('edited-') else 'Original text'
            if drift and path.name.startswith('imported-'):
                text = 'First-save text drift'
            return record(name, text=text)

        # Fixture XML/semantic validation has its own positive and destructive
        # oracle suite. Here it is stubbed for routing tests; real malformed-ZIP
        # and XML controls below exercise the mandatory preflight separately.
        validation = patch.object(render, 'validate_native_aux_corpus') if validate else nullcontext()
        with validation, redirect_stdout(io.StringIO()), \
                patch.object(render.subprocess, 'check_output', return_value='LibreOffice test'), \
                patch.object(render, 'render_document', side_effect=convert) as conversions:
            args = [str(root), str(output)]
            if receipt is not None:
                args += ['--schema-report', str(receipt)]
            result = render.main(args)
        report = json.loads((output / 'render-report.json').read_text())
        return result, report, conversions

    def test_qualified_rejection_is_native_only_without_any_visual_success(self):
        with tempfile.TemporaryDirectory() as folder:
            root, paths, receipt = self.fixture(folder)
            result, report, conversions = self.run_renderer(root, receipt=receipt)
            self.assertEqual(result, 0)
            self.assertEqual(report['failures'], [])
            self.assertEqual(report['files'], 7)
            self.assertEqual(report['native_schema_only_files'], 7)
            self.assertEqual(report['visual_input_files'], 0)
            self.assertEqual(report['rendered_files'], 0)
            self.assertEqual(report['cycle_groups'], 0)
            self.assertEqual(report['baseline_comparisons'], 0)
            self.assertEqual(report['reports'], [])
            self.assertEqual(conversions.call_count, 1)
            self.assertEqual(conversions.call_args.args[0], paths['source.docx'])
            for item in report['native_schema_only']:
                self.assertEqual(item['status'], 'native_schema_only')
                self.assertIn('no visual certification', item['reason'])
                self.assertIn('source file could not be loaded', item['source_diagnostic'])
                self.assertEqual(item['schema_sha256'], hashlib.sha256((root / item['file']).read_bytes()).hexdigest())

    def test_every_exact_current_file_needs_one_clean_sdk_receipt(self):
        for change in ('absent', 'missing-file', 'wrong-path', 'hash', 'changed-bytes',
                       'errors', 'exception', 'duplicate', 'malformed'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as folder:
                root, paths, receipt = self.fixture(folder)
                data = json.loads(receipt.read_text())
                item = data['Reports'][0]
                if change == 'missing-file':
                    data['Reports'].pop(0)
                elif change == 'wrong-path':
                    item['File'] = str(Path(folder) / 'another-folder' / Path(item['File']).name)
                elif change == 'hash':
                    item['Sha256'] = '0' * 64
                elif change == 'changed-bytes':
                    Path(item['File']).write_bytes(b'Changed after SDK validation')
                elif change == 'errors':
                    item['Errors'] = [{'Description': 'Invalid native structure'}]
                elif change == 'exception':
                    item['Exception'] = 'SDK could not open this package'
                elif change == 'duplicate':
                    data['Reports'].append(dict(item))
                receipt.write_text('invalid JSON' if change == 'malformed' else json.dumps(data))
                result, report, _ = self.run_renderer(root, receipt=None if change == 'absent' else receipt)
                self.assertEqual(result, 1)
                self.assertEqual(report['native_schema_only'], [])
                self.assertTrue(any('qualification_error' in failure for failure in report['failures']))

    def test_missing_source_or_cycle_fails_before_limitation_can_apply(self):
        for missing in ('source.docx', 'edited-3.docx'):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as folder:
                root, paths, receipt = self.fixture(folder)
                paths[missing].unlink()
                result, report, _ = self.run_renderer(root, receipt=receipt, validate=False)
                self.assertEqual(result, 1)
                self.assertEqual(report['native_schema_only_files'], 0)
                self.assertTrue(any('Incomplete native auxiliary corpus' in failure['error']
                                    for failure in report['failures']))

    def test_new_renderer_success_enforces_normal_source_and_cycle_comparisons(self):
        for drift in (False, True):
            with self.subTest(drift=drift), tempfile.TemporaryDirectory() as folder:
                root, paths, receipt = self.fixture(folder)
                result, report, conversions = self.run_renderer(root, source_renders=True, drift=drift)
                self.assertEqual(result, 1 if drift else 0)
                self.assertEqual(report['native_schema_only'], [])
                self.assertEqual(report['rendered_files'], 7)
                self.assertEqual(report['visual_input_files'], 7)
                self.assertEqual(report['cycle_groups'], 2)
                self.assertEqual(conversions.call_count, 7)
                if drift:
                    self.assertTrue(any('Render changed' in failure['error'] for failure in report['failures']))
                else:
                    self.assertEqual(report['baseline_comparisons'], 1)

    def test_other_directories_and_extra_files_are_never_exempted(self):
        with tempfile.TemporaryDirectory() as folder:
            root, paths, receipt = self.fixture(folder, corpus='fidelity-aux-controls-other')
            result, report, _ = self.run_renderer(root, receipt=receipt)
            self.assertEqual(result, 1)
            self.assertEqual(report['native_schema_only_files'], 0)
        with tempfile.TemporaryDirectory() as folder:
            root, paths, receipt = self.fixture(folder)
            (paths['source.docx'].parent / 'unexpected.docx').write_bytes(b'Unreviewed input')
            result, report, _ = self.run_renderer(root, receipt=receipt, extra_failure='unexpected.docx')
            self.assertEqual(result, 1)
            self.assertEqual(report['native_schema_only_files'], 7)
            self.assertEqual(report['visual_input_files'], 1)
            self.assertTrue(any(failure.get('file', '').endswith('/unexpected.docx')
                                for failure in report['failures']))

    def test_conversion_timeout_or_other_failure_is_not_a_native_limitation(self):
        for error in (subprocess.TimeoutExpired(['soffice'], 60),
                      subprocess.CalledProcessError(1, ['soffice'], stderr='Permission denied'),
                      subprocess.CalledProcessError(11, ['soffice'], stderr='Error: source file could not be loaded')):
            with self.subTest(error=error), tempfile.TemporaryDirectory() as folder:
                root, paths, receipt = self.fixture(folder)
                result, report, _ = self.run_renderer(root, receipt=receipt, source_error=error)
                self.assertEqual(result, 1)
                self.assertEqual(report['native_schema_only_files'], 0)

    def test_real_malformed_zip_and_xml_cannot_use_a_clean_receipt(self):
        for malformed_xml in (False, True):
            with self.subTest(xml=malformed_xml), tempfile.TemporaryDirectory() as folder:
                root, paths, receipt = self.fixture(folder)
                if malformed_xml:
                    for path in paths.values():
                        with ZipFile(path, 'w') as archive:
                            archive.writestr('[Content_Types].xml', '<Types/>')
                            archive.writestr('_rels/.rels', '<Relationships/>')
                            archive.writestr('word/document.xml', '<unclosed>')
                result, report, _ = self.run_renderer(root, receipt=receipt, validate=False)
                self.assertEqual(result, 1)
                self.assertEqual(report['native_schema_only'], [])
                self.assertTrue(any('Native auxiliary structure is not qualified' in failure['error']
                                    for failure in report['failures']))


if __name__ == '__main__':
    unittest.main()
