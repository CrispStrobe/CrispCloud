"""The native diagnostic fallback must preserve the required full-suite gate."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).resolve().parents[1] / 'run_native_tests.sh'


class NativeRunnerTests(unittest.TestCase):
    def run_with_statuses(self, statuses):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake = root / 'xcrun'
            fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
assert sys.argv[1:5] == ['simctl', 'spawn', 'test-simulator', '/test/NativeShellTests']
case = sys.argv[5] if len(sys.argv) > 5 else 'full'
with open(os.environ['CRISP_NATIVE_TEST_CALLS'], 'a') as log:
    log.write(json.dumps(case) + '\\n')
if case == '--list':
    print('alpha\\n\\nbeta')
sys.exit(json.loads(os.environ['CRISP_NATIVE_TEST_STATUS']).get(case, 0))
''')
            fake.chmod(0o755)
            calls_path = root / 'calls'
            environment = os.environ.copy()
            environment.update({
                'PATH': str(root) + os.pathsep + environment['PATH'],
                'CRISP_NATIVE_TEST_CALLS': str(calls_path),
                'CRISP_NATIVE_TEST_STATUS': json.dumps(statuses),
            })
            result = subprocess.run(
                ['bash', str(RUNNER), 'test-simulator', '/test/NativeShellTests'],
                env=environment, text=True, capture_output=True, check=False,
            )
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            return result, calls

    def test_successful_full_suite_is_not_repeated(self):
        result, calls = self.run_with_statuses({'full': 0})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['full'])
        self.assertNotIn('DIAGNOSTIC', result.stdout)

    def test_individual_results_cannot_override_full_suite_failure(self):
        result, calls = self.run_with_statuses({'full': 7, 'alpha': 9})
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(calls, ['full', '--list', 'alpha', 'beta'])
        self.assertIn('alpha failed with status 9', result.stdout)
        self.assertIn('native case beta', result.stdout)

    def test_case_listing_failure_preserves_original_failure(self):
        result, calls = self.run_with_statuses({'full': 42, '--list': 65})
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(calls, ['full', '--list'])
        self.assertIn('could not list native cases', result.stdout)


if __name__ == '__main__':
    unittest.main()
