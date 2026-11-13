#!/usr/bin/env python3
"""Measure existing build/source assets. Does not build or modify production files."""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import zlib

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--build', type=Path)
args = parser.parse_args()
repo = args.repo.resolve()
web = (args.build or repo / 'build/web').resolve()
runtime = repo / 'packages/file_viewer_documents/assets/runtime'
assets = runtime.parent
built_assets = web / 'assets/packages/file_viewer_documents/assets'

def record(path, base):
    data = path.read_bytes()
    return {'path': str(path.relative_to(base)), 'bytes': len(data),
            'gzip9_bytes': len(gzip.compress(data, compresslevel=9, mtime=0)),
            'sha256': hashlib.sha256(data).hexdigest()}

def files(path):
    return sorted(p for p in path.rglob('*') if p.is_file())

def totals(rows):
    return {'files': len(rows), 'bytes': sum(r['bytes'] for r in rows),
            'gzip9_bytes': sum(r['gzip9_bytes'] for r in rows)}

asset_rows = [record(p, assets) for p in files(assets)]
built_rows = [record(p, built_assets) for p in files(built_assets)]
assert asset_rows == built_rows, 'Built selected asset set differs from source'
runtime_rows = [r for r in asset_rows if r['path'].startswith('runtime/')]
notice_rows = [r for r in asset_rows if r['path'].startswith('licenses/')]
runtime_by_name = {Path(r['path']).name: r for r in runtime_rows}
host = (runtime / 'host.js').read_text()
entries = dict(re.findall(r'case "([a-z]+)":\s*instance = await \(await import\("\./([^\"]+)"\)', host))
assert set(entries) == {'wordperfect', 'chm', 'spreadsheet', 'ppt', 'postscript', 'xml'}
auxiliaries = {
    'wordperfect': ['wordperfect.worker.js', 'libwpd.mjs', 'libwpd.wasm'],
    'chm': ['chm.worker.js', 'chm_wasm.js', 'chm_wasm_bg.wasm'],
    'spreadsheet': ['sheet.worker.js'],
    'ppt': ['pptjs.worker.js'],
    'postscript': ['postscript.worker.js', 'stet_wasm_bg.wasm'],
    'xml': ['xmllint-browser.mjs', 'xmllint.wasm', 'xslt-wasm.js'],
}
graph = {}
for path in files(runtime):
    if path.suffix in {'.js', '.mjs'}:
        candidates = re.findall(r'''["'](?:\./)?([A-Za-z0-9_.-]+\.(?:js|mjs|wasm))["']''', path.read_text())
        graph[path.name] = {n for n in candidates if n in runtime_by_name}

def closure(roots):
    result, pending = set(), list(roots)
    while pending:
        name = pending.pop()
        if name in result:
            continue
        result.add(name)
        pending.extend(graph.get(name, set()) - result)
    return result

reachable = {engine: closure([entry, *auxiliaries[engine]]) for engine, entry in entries.items()}
owners = defaultdict(list)
for engine, names in reachable.items():
    for name in names:
        owners[name].append(engine)
engine_sizes = {}
for engine, names in reachable.items():
    own = {name for name in names if len(owners[name]) == 1}
    engine_sizes[engine] = {
        'entry': entries[engine], 'explicit_auxiliary_roots': auxiliaries[engine],
        'conservative_reachable_files': sorted(names),
        'conservative_reachable_totals': totals([runtime_by_name[n] for n in names]),
        'exclusive_files': sorted(own),
        'exclusive_totals': totals([runtime_by_name[n] for n in own]),
    }
shared = sorted(name for name, engines in owners.items() if len(engines) > 1)
unassigned = sorted(set(runtime_by_name) - set(owners))

font_rows = [record(p, web) for p in files(web) if p.suffix.lower() in {'.ttf', '.otf', '.woff', '.woff2'}]
font_groups = defaultdict(list)
font_hashes = defaultdict(list)
for r in font_rows:
    parts = Path(r['path']).parts
    group = parts[2] if parts[:2] == ('assets', 'packages') else '/'.join(parts[:-1])
    font_groups[group].append(r)
    font_hashes[r['sha256']].append(r['path'])
notice_hashes = defaultdict(list)
for r in notice_rows:
    notice_hashes[r['sha256']].append(r)
duplicate_notices = [
    {'sha256': h, 'paths': [r['path'] for r in rows], 'bytes_per_copy': rows[0]['bytes'],
     'duplicate_bytes': rows[0]['bytes'] * (len(rows) - 1)}
    for h, rows in notice_hashes.items() if len(rows) > 1
]
manifest = json.loads((runtime/'manifest.json').read_text())
manifest_notices = {f"licenses/{r['file']}" for r in manifest['notices']} | {'licenses/THIRD_PARTY.txt'}
output = {
    'schema': 1,
    'scope': 'Existing 2026-11-13 JavaScript web release assets and matching tracked selected runtime; no rebuild',
    'runtime_code_baseline': '087b73a14b64c445c5eb717f187925b5472ed9b3',
    'source_commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
    'versions': {'python': platform.python_version(), 'zlib_compile': zlib.ZLIB_VERSION, 'zlib_runtime': zlib.ZLIB_RUNTIME_VERSION},
    'method': {
        'units': 'bytes; divide by 1048576 for MiB',
        'compression': 'gzip.compress(data, compresslevel=9, mtime=0) per file, then sum; estimate, not measured HTTP, app-store or installer download',
        'font_scope': 'Standalone .ttf/.otf/.woff/.woff2 in build/web only; excludes font data embedded inside WASM or documents',
        'engine_partition': 'Read actual compiled host imports, manually supply runtime auxiliary roots from source, recursively follow quoted local js/mjs/wasm filenames. Conservative all-feature dependency closure, including lazy optional imports. Shared files counted once in partition; not an initial-load network trace.',
        'license_scope': 'Both original notices and generated aggregate are currently bundled. Identical-byte duplicates are identified, not removed. Aggregate overlap is not treated as byte-identical file duplication.',
        'native_size_limit': 'Raw asset bytes approximate native resource contribution only. Actual native compressed packages were not built or measured.',
    },
    'selected_assets_match_source': True,
    'selected_totals': totals(asset_rows),
    'runtime_totals_including_manifest': totals(runtime_rows),
    'notice_totals': totals(notice_rows),
    'selected_files': asset_rows,
    'engine_sizes': engine_sizes,
    'shared_runtime_files': shared,
    'shared_runtime_totals': totals([runtime_by_name[n] for n in shared]),
    'unassigned_runtime_files': unassigned,
    'unassigned_runtime_totals': totals([runtime_by_name[n] for n in unassigned]),
    'font_totals': totals(font_rows),
    'font_group_totals': {k: totals(v) for k,v in sorted(font_groups.items())},
    'fonts': font_rows,
    'exact_duplicate_fonts': [{'sha256': h, 'paths': ps} for h,ps in font_hashes.items() if len(ps)>1],
    'exact_duplicate_notice_files': duplicate_notices,
    'exact_duplicate_notice_extra_bytes': sum(r['duplicate_bytes'] for r in duplicate_notices),
    'notice_files_beyond_generated_manifest': sorted(r['path'] for r in notice_rows if r['path'] not in manifest_notices),
}
print(json.dumps(output, indent=2, sort_keys=True))
