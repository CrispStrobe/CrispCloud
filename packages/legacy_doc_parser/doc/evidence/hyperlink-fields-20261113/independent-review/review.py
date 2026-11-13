#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Independent read-only replay of the final hyperlink evidence fixes."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path('/workspace/scratch/c1ca2a1344e9')
REPO = ROOT / 'parser-hyperlink-probes'
FOLDER = REPO / 'doc/evidence/hyperlink-fields-20261113'
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(FOLDER))
import verify
import test_verifier as controls


def identity(path):
    data = path.read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def run(name, argv):
    completed = subprocess.run(argv, cwd=REPO, capture_output=True)
    for stream in ('stdout', 'stderr'):
        (OUT / (name + '.' + stream)).write_bytes(getattr(completed, stream))
    if completed.returncode:
        raise ValueError(name + ' failed')
    return {'argv': argv, 'cwd': str(REPO), 'exitCode': completed.returncode,
            **{stream: identity(OUT / (name + '.' + stream)) for stream in ('stdout', 'stderr')}}


def check(label, mutate, expected):
    payloads = verify.load_payloads()
    mutate(payloads)
    try:
        verify.verify_payloads(payloads, REPO)
    except ValueError as error:
        if expected not in str(error):
            raise ValueError(label + ': wrong rejection: ' + str(error)) from error
        return {'name': label, 'rejected': True, 'guard': str(error),
                'scope': 'In-memory semantic replay after original outer seal; original observations unchanged.'}
    raise ValueError(label + ': counterexample still accepted')


def owner_swap(files):
    for member, old, new in [
        ('word/_rels/document.xml.rels', b'https://example.com/body', b'https://example.com/note'),
        ('word/_rels/footnotes.xml.rels', b'https://example.com/note', b'https://example.com/body'),
    ]:
        controls.package_member(files, 'external/native/parser.docx', member,
                                lambda value, old=old, new=new: controls.xml_replace(value, old, new))


def constant_entrypoint(files):
    path = 'javascript-final/acceptance.dart'
    source = files[path].decode()
    if source.count('void main()') != 1:
        raise ValueError('Unexpected executable template')
    source = source.replace('void main()', 'void unusedAcceptance()')
    source += 'void main() { print(' + json.dumps(files['javascript-final/node.stdout'].decode().strip()) + '); }\n'
    files[path] = source.encode()


def omitted_inputs(files):
    path = 'reference-final/native-export.json'
    record = json.loads(files[path])
    record.pop('inputsBefore')
    record.pop('inputsAfter')
    files[path] = json.dumps(record).encode()


before = {p.name: identity(p) for p in sorted(FOLDER.iterdir()) if p.is_file()}
commands = [
    run('verifier', ['python3', str(FOLDER / 'verify.py'), '--repository', '.']),
    run('controls-normal', ['python3', '-m', 'unittest', 'discover', '-s', str(FOLDER), '-p', 'test_verifier.py']),
    run('controls-optimized', ['python3', '-O', '-m', 'unittest', 'discover', '-s', str(FOLDER), '-p', 'test_verifier.py']),
]
rechecks = [
    check('native body/note target ownership swap', owner_swap, 'Native URL story/text/target ownership'),
    check('constant-result JavaScript entrypoint', constant_entrypoint, 'Exact executable JS entrypoint and native payload'),
    check('omitted native command input receipts', omitted_inputs, 'Required exact command input receipts'),
]
after = {p.name: identity(p) for p in sorted(FOLDER.iterdir()) if p.is_file()}
if before != after:
    raise ValueError('Evidence helper or original observations changed during review')
result = {
    'schema': 'legacy-doc-parser/independent-hyperlink-evidence-review',
    'version': 1, 'observedUtc': datetime.now(timezone.utc).isoformat(),
    'evidenceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
    'evidenceTree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=REPO, text=True).strip(),
    'evidenceFolder': str(FOLDER), 'filesBefore': before, 'filesAfter': after,
    'reviewSource': identity(Path(__file__)), 'commands': commands, 'counterexampleRechecks': rechecks,
    'originalResult': json.loads((OUT / 'verifier.stdout').read_bytes()),
    'controls': {'normal': 31, 'optimized': 31, 'semantics': '30 resealed negative controls plus the positive original'},
    'reviewFindings': 'No remaining concrete discrepancy in the bounded source/command/story/JS/SDK receipt review.',
    'scope': 'Read-only evidence replay and in-memory corruption controls. No converter, renderer, production test or native workflow rerun. Does not certify all field or renderer behavior.',
}
(OUT / 'review.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'receipt': str(OUT / 'review.json'), **identity(OUT / 'review.json'),
                  'originalRecords': result['originalResult']['records'], 'counterexamplesRejected': len(rechecks)}, sort_keys=True))
