#!/usr/bin/env python3
"""Stage immutable recovery audits and excluded attempts without touching source."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parent.parent
out = root / 'recovery-publication' / 'common'
assert not out.exists(), 'Use a fresh output directory; do not overwrite evidence.'
(out / 'audit').mkdir(parents=True)

def copy(src, dst):
    assert src.is_file() and not src.is_symlink(), src
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    assert src.read_bytes() == dst.read_bytes()

excluded_names = {'final-readme-draft.md', 'crisp-final-readme-draft.md'}
for src in sorted((root / 'recovery-audit' / 'quds').iterdir()):
    if src.is_file() and src.name not in excluded_names:
        copy(src, out / 'audit' / src.name)
for src in sorted((root / 'recovery-audit').iterdir()):
    if not src.is_file() or src.name in excluded_names:
        continue
    if src.name.startswith(('crisp-', 'host-', 'delivery-verification', 'unmanaged-')) or src.name in {'audit_crisp_refs.py', 'verify-delivery.py'}:
        copy(src, out / 'audit' / src.name)
for src in sorted((root / 'recovery-audit' / 'unmanaged-diffs').rglob('*')):
    if src.is_file():
        copy(src, out / 'audit' / 'unmanaged-diffs' / src.name)

attempts = [
    ('zotero-toolchain/expanded-canonical-qualification/attempt-1-sparse-manifest-setup', 'sparse-setup'),
    ('zotero-toolchain/expanded-canonical-qualification/attempt-2-executor-interruption', 'interruption'),
    ('recovery-validation/host-attempt-1-interrupted', 'host-interruption'),
    ('recovery-audit/quds/retry-runner-mechanics', 'runner-mechanics'),
]
for source_name, destination_name in attempts:
    source = root / source_name
    for src in sorted(source.rglob('*')):
        if src.is_file():
            copy(src, out / 'attempts' / destination_name / src.relative_to(source))
copy(root / 'recovery-audit/quds/sparse-setup-missing.json', out / 'attempts/sparse-setup-missing.json')
for name in ['retry-invocation.json', 'run-retry-canonical.sh']:
    copy(root / 'recovery-audit' / 'quds' / name, out / name)

(out / 'attempts/README.md').write_text('''# Excluded setup and interrupted attempts\n\nThese records preserve partial execution and runner-mechanics evidence. **None of their test counters contributes to the fresh qualification totals.**\n\n- `sparse-setup/`: missing sparse-checkout manifests; zero tests ran.\n- `interruption/`: completed 390 engine tests, followed by incomplete editor progress and loss of the managed execution handle; no complete qualification receipt. The cause is unknown. Flutter also added two package-config metadata fields, so the original harness byte-invariance claim remains false.\n- `host-interruption/`: 41 completed host tests, passed vendor guards, and an incomplete analyzer run; no complete qualification receipt.\n- `runner-mechanics/`: synthetic subprocess controls for timeouts, heartbeats, exit codes and terminal test markers. These are runner checks, not application tests.\n\nThe successful fresh runs are published separately under `../canonical/` and `../host/`. Original filenames and bytes in these attempt directories are retained. Existing `.gz` files restore losslessly with `gzip -dk`; their original archive inventories remain unchanged.\n''')
rows = []
for path in sorted(out.rglob('*')):
    if path.is_file():
        data = path.read_bytes()
        rows.append({'path': str(path.relative_to(out)), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
(out / 'static-evidence-inventory.json').write_text(json.dumps({'schema_version':1, 'artifacts':rows, 'attempts_counted_as_fresh_tests':False}, indent=2, sort_keys=True)+'\n')
print(json.dumps({'destination':str(out), 'files':len(rows), 'bytes':sum(x['bytes'] for x in rows)}))
