import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import audit_operations as audit


class OperationInventoryControls(unittest.TestCase):
    def run_inventory(self, executed, unused, *, raw=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures = root/'test/fixtures/fidelity/scripts'
            fixtures.mkdir(parents=True)
            tool = root/'tool/fidelity'
            tool.mkdir(parents=True)
            (tool/'example_steps.json').write_text('[]')
            for filename in ('word', 'word-structure-edit', 'word-structure-remove'):
                (fixtures/f'{filename}.json').write_text('[]')
            (fixtures/'sheet.json').write_text('[{"op":"cell","value":1}]')
            (fixtures/'slide.json').write_text('[{"op":"shape","value":1}]')
            (fixtures/'word-structure-create.json').write_text(json.dumps(executed) if raw is None else raw)
            (fixtures/'word-structure-unused.json').write_text(json.dumps(unused))
            with patch.object(audit, 'ROOT', root), patch.object(audit, 'FIXTURES', fixtures):
                return audit.audit({'docx': {'required': ['value']},
                                    'xlsx': {'cell': ['value']},
                                    'pptx': {'shape': ['value']}})

    def test_unused_scenario_cannot_satisfy_operation_inventory(self):
        with self.assertRaisesRegex(AssertionError, 'Unexercised operation: docx/required'):
            self.run_inventory([], [{'op': 'required', 'value': 1}])

    def test_inventory_cites_only_the_explicitly_executed_script(self):
        result = self.run_inventory([{'op': 'required', 'value': 1}], [{'op': 'unknown'}])
        self.assertEqual(result['operations'], 3)
        self.assertEqual(result['evidence'][0]['scenarios'], [{
            'script': 'test/fixtures/fidelity/scripts/word-structure-create.json', 'step': 1,
        }])

    def test_unknown_parameter_in_executed_script_fails(self):
        with self.assertRaisesRegex(AssertionError, 'unknown fields'):
            self.run_inventory([{'op': 'required', 'vlaue': 1}], [])

    def test_empty_missing_and_extra_format_catalogs_cannot_pass(self):
        valid = {name: {'operation': []} for name in ('docx', 'xlsx', 'pptx')}
        for catalog in (None, [], {}, {'docx': {'operation': []}},
                        dict(valid, pdf={'operation': []})):
            with self.subTest(catalog=catalog):
                with self.assertRaisesRegex(AssertionError, 'exactly docx, xlsx and pptx'):
                    audit.audit(catalog)

    def test_empty_or_malformed_format_catalog_cannot_pass(self):
        for operations in ({}, [], None, {'': []}, {'bad name ': []},
                           {'operation': 'value'}, {'operation': ['value', 'value']},
                           {'operation': [None]}, {'operation': ['op']},
                           {'operation': [' value']}):
            with self.subTest(operations=operations):
                catalog = {name: {'operation': []} for name in ('docx', 'xlsx', 'pptx')}
                catalog['docx'] = operations
                with self.assertRaises(AssertionError):
                    audit.audit(catalog)

    def test_malformed_executed_scenario_cannot_count_as_coverage(self):
        for scenario in ({'op': 'required'}, [None], ['required'], [{'op': 1}], [{}]):
            with self.subTest(scenario=scenario):
                with self.assertRaisesRegex(AssertionError, 'scenario must|step must'):
                    self.run_inventory(scenario, [])

    def test_duplicate_step_fields_are_not_silently_discarded(self):
        with self.assertRaisesRegex(AssertionError, 'Duplicate JSON key.*op'):
            self.run_inventory([], [], raw='[{"op":"unknown","op":"required","value":1}]')

    def test_duplicate_catalog_formats_or_operations_are_rejected(self):
        for raw in ('{"docx":{},"docx":{}}', '{"operation":[],"operation":[]}'):
            with self.subTest(raw=raw):
                with self.assertRaisesRegex(AssertionError, 'Duplicate JSON key'):
                    json.loads(raw, object_pairs_hook=audit.unique_object)


if __name__ == '__main__':
    unittest.main()
