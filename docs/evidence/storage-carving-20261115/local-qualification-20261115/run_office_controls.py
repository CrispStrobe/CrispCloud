#!/usr/bin/env python3
"""Run the three existing Office inventory/sync control modules without changing source."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import unittest

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--summary', type=Path, required=True)
args = parser.parse_args()
patterns = ['test_sync_office_fidelity.py', 'test_sync_legacy_doc_parser.py',
            'test_office_host_evidence.py']
suite = unittest.TestSuite()
modules = []
for pattern in patterns:
    discovered = unittest.TestLoader().discover('tool', pattern=pattern)
    count = discovered.countTestCases()
    if count == 0:
        raise SystemExit('No tests discovered for '+pattern)
    modules.append({'file': 'tool/'+pattern, 'discovered_tests': count,
                    'source_sha256': hashlib.sha256((Path('tool')/pattern).read_bytes()).hexdigest()})
    suite.addTests(discovered)
result = unittest.TextTestRunner(verbosity=2).run(suite)
summary = {'modules': modules, 'tests_run': result.testsRun,
           'passed': result.testsRun-len(result.failures)-len(result.errors)-len(result.skipped)-len(result.expectedFailures)-len(result.unexpectedSuccesses),
           'failures': len(result.failures), 'errors': len(result.errors),
           'skipped': len(result.skipped), 'expected_failures': len(result.expectedFailures),
           'unexpected_successes': len(result.unexpectedSuccesses),
           'success': result.wasSuccessful() and not result.skipped and not result.expectedFailures}
args.summary.write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
raise SystemExit(0 if summary['success'] else 1)
