"""Prove that the preserved two-root verifier rejects a third scoped root."""
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('two_root_verifier', root / 'office_host_evidence.py')
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)
data = json.loads((root / 'office_host_evidence.json').read_text())
entry = {'path': 'build/office-style-history-acceptance/source.xlsx', 'role': 'authored_input'}
data['schema_only_artifacts'].append(entry)
with tempfile.TemporaryDirectory() as temporary:
    manifest = Path(temporary) / 'manifest.json'
    manifest.write_text(json.dumps(data))
    with patch.object(evidence, 'MANIFEST', manifest):
        try:
            evidence.expected_paths()
        except ValueError as error:
            print(json.dumps({'entry': entry, 'accepted': False, 'error': str(error)}, indent=2))
        else:
            raise AssertionError('The preserved two-root verifier accepted the third root')
