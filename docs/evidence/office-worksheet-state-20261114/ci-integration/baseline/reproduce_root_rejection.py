"""Reproduce the pre-change verifier's rejection of the two explicit roots.

This invokes the preserved original expected_paths() with one additional
output path at a time. It does not execute a host test or a schema validator.
"""
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch


root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('baseline_host_evidence', root / 'office_host_evidence.py')
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)
original = json.loads((root / 'office_host_evidence.json').read_text())
checks = []
with tempfile.TemporaryDirectory() as temporary:
    manifest = Path(temporary) / 'manifest.json'
    for name in ('build/office-fill-host-acceptance/source.xlsx',
                 'build/office-sheet-state-acceptance/source.xlsx'):
        data = json.loads(json.dumps(original))
        data['outputs'].append(name)
        manifest.write_text(json.dumps(data))
        with patch.object(evidence, 'MANIFEST', manifest):
            try:
                evidence.expected_paths()
            except ValueError as error:
                checks.append({'probe_path': name, 'accepted': False, 'error': str(error)})
            else:
                raise AssertionError('The old verifier unexpectedly accepted the new root')
print(json.dumps(checks, indent=2))
