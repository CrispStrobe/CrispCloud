# SPDX-License-Identifier: MPL-2.0
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from native_text_probe import load_cases, normalized, probe


class NativeTextProbeTest(unittest.TestCase):
    def test_normalization_retains_nonwhitespace_differences(self):
        self.assertEqual(normalized(' A\tB\n\fC '), 'ABC')
        self.assertNotEqual(normalized('A\u00adB'), normalized('AB'))
        self.assertNotEqual(normalized('A\x0eB'), normalized('AB'))
        self.assertNotEqual(normalized('A7Z'), normalized('A1Z'))

    def test_manifest_does_not_accept_duplicate_output_identities(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'case.docx').write_bytes(b'input')
            manifest = root / 'manifest.json'
            case = {'name': 'same', 'input': 'case.docx', 'expectedText': 'A'}
            manifest.write_text(json.dumps({'cases': [case, case]}))
            with self.assertRaises(ValueError):
                load_cases(manifest)
            manifest.write_text(json.dumps({'cases': [dict(case, name='../escape')]}))
            with self.assertRaises(ValueError):
                load_cases(manifest)
            manifest.write_text(json.dumps({'cases': [case]}))
            self.assertEqual(load_cases(manifest)[0]['source'], (root / 'case.docx').resolve())

    def test_a_later_matching_import_does_not_hide_initial_difference(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.docx'
            source.write_bytes(b'original')

            def convert(office, current, target, kind):
                target.mkdir()
                result = target / ('case.' + kind)
                result.write_bytes(b'%PDF-probe' if kind == 'pdf' else b'native-docx')
                return result

            case = {'name': 'case', 'input': 'source.docx', 'source': source, 'expectedText': 'A7Z'}
            with patch('native_text_probe.office_convert', side_effect=convert), patch(
                    'native_text_probe.command', side_effect=['A1Z', 'A7Z']):
                result = probe(case, root, 'office', 2)
            self.assertFalse(result['passed'])
            self.assertEqual([r['passed'] for r in result['rounds']], [False, True])
            self.assertEqual((root / result['rounds'][0]['text']).read_text(), 'A1Z')
            self.assertTrue((root / result['rounds'][0]['nativeDocx']).is_file())
            self.assertEqual(json.loads((root / 'case/report.json').read_text()), result)

    def test_native_failure_is_recorded_without_discarding_finished_stages(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.docx'
            source.write_bytes(b'original')

            def convert(office, current, target, kind):
                if kind == 'docx':
                    raise RuntimeError('native export failed')
                target.mkdir()
                result = target / 'case.pdf'
                result.write_bytes(b'%PDF-probe')
                return result

            case = {'name': 'case', 'input': 'source.docx', 'source': source, 'expectedText': 'AZ'}
            with patch('native_text_probe.office_convert', side_effect=convert), patch(
                    'native_text_probe.command', return_value='AZ'):
                result = probe(case, root, 'office', 2)
            self.assertFalse(result['passed'])
            self.assertEqual(result['error'], 'native export failed')
            self.assertTrue(result['rounds'][0]['passed'])
            self.assertTrue((root / result['rounds'][0]['pdf']).is_file())


if __name__ == '__main__':
    unittest.main()
