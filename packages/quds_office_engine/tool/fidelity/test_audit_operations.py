import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import audit_operations as audit


class OperationInventoryControls(unittest.TestCase):
    def run_inventory(self, executed, unused):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures = root/'test/fixtures/fidelity/scripts'
            fixtures.mkdir(parents=True)
            tool = root/'tool/fidelity'
            tool.mkdir(parents=True)
            (tool/'example_steps.json').write_text('[]')
            for filename in ('word', 'sheet', 'slide', 'word-structure-edit', 'word-structure-remove'):
                (fixtures/f'{filename}.json').write_text('[]')
            (fixtures/'word-structure-create.json').write_text(json.dumps(executed))
            (fixtures/'word-structure-unused.json').write_text(json.dumps(unused))
            with patch.object(audit, 'ROOT', root), patch.object(audit, 'FIXTURES', fixtures):
                return audit.audit({'docx': {'required': ['value']}})

    def test_unused_scenario_cannot_satisfy_operation_inventory(self):
        with self.assertRaisesRegex(AssertionError, 'Unexercised operation: docx/required'):
            self.run_inventory([], [{'op': 'required', 'value': 1}])

    def test_inventory_cites_only_the_explicitly_executed_script(self):
        result = self.run_inventory([{'op': 'required', 'value': 1}], [{'op': 'unknown'}])
        self.assertEqual(result['operations'], 1)
        self.assertEqual(result['evidence'][0]['scenarios'], [{
            'script': 'test/fixtures/fidelity/scripts/word-structure-create.json', 'step': 1,
        }])

    def test_unknown_parameter_in_executed_script_fails(self):
        with self.assertRaisesRegex(AssertionError, 'unknown fields'):
            self.run_inventory([{'op': 'required', 'vlaue': 1}], [])


if __name__ == '__main__':
    unittest.main()
