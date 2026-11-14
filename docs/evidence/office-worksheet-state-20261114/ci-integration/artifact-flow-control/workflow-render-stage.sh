python3 - <<'PYTHON'
import hashlib
import json
from pathlib import Path
import shutil
report = json.loads(Path('build/external/host-inventory.json').read_text())
assert not report['failures'] and report['verified'] == report['expected']
# The two explicit acceptance roots receive SDK schema validation
# above. Their declared scope makes no renderer or visual claim.
rendered = [item for item in report['files']
            if item['validation_scope'] == 'schema_and_render']
assert len(rendered) == report['expected_rendered'] == report['verified_rendered']
destination = Path('build/external/host-input')
destination.mkdir(parents=True, exist_ok=False)
for item in rendered:
    source = Path('evidence') / item['file']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == item['sha256']
    target = destination / item['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
PYTHON
