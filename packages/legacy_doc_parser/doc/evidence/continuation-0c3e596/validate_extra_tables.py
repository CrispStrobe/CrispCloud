#!/usr/bin/env python3
"""Validate independent table controls with the exact combined parser source."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

root, original, prior, out, dart, dotnet = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=False)
sys.path.insert(0, str(root / 'tool/fidelity'))
from schema import source_snapshot, verify_report


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parts(path):
    with zipfile.ZipFile(path) as z:
        return {name: z.read(name) for name in z.namelist()}


def run(args, log):
    with log.open('wb') as stream:
        subprocess.run(list(map(str, args)), cwd=root, env=os.environ,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)


main_gate = json.loads((prior / 'report.json').read_text())
commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
assert main_gate['passed'] and not main_gate['gitWorktreeDirty']
assert commit == main_gate['gitHead']
before = source_snapshot(root)
assert before == main_gate['sourceAfter']
validator = prior / 'validator'
for name, expected in main_gate['validatorBuild']['artifacts'].items():
    assert sha(validator / name) == expected, name
receipt = {'parserCommit': commit, 'sourceBefore': before,
           'primarySchemaReportSha256': sha(prior / 'report.json'),
           'validatorArtifacts': main_gate['validatorBuild']['artifacts'],
           'cases': [], 'passed': False}


def save():
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


save()
executable = out / 'convert'
run([dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', executable], out / 'compile.log')
receipt['compilerSha256'] = sha(dart)
receipt['converterSha256'] = sha(executable)
receipt['compileLogSha256'] = sha(out / 'compile.log')
for group, expected_count in [('floating-context-matrix', 13), ('floating-edge-matrix', 4),
                              ('table-margin-schema-controls', 4)]:
    files = sorted((original / group).glob('*.doc'))
    assert len(files) == expected_count, group
    (out / 'inputs' / group).mkdir(parents=True)
    (out / 'corpus' / group).mkdir(parents=True)
    for src in files:
        retained = out / 'inputs' / group / src.name
        shutil.copyfile(src, retained)
        target = out / 'corpus' / group / (src.stem + '.docx')
        log = target.with_suffix('.log')
        source_hash = sha(src)
        run([executable, retained, target], log)
        reference = src.with_name(src.stem + '-76fa966.docx')
        assert parts(target) == parts(reference), src.name
        assert sha(src) == source_hash == sha(retained), src.name
        receipt['cases'].append({'id': group + '/' + src.stem,
            'source': str(retained.relative_to(out)), 'sourceSha256': source_hash,
            'output': str(target.relative_to(out)), 'outputSha256': sha(target),
            'tableBranchOutputSha256': sha(reference), 'opcPartsIdentical': True,
            'log': str(log.relative_to(out)), 'logSha256': sha(log)})
        save()
assert len(receipt['cases']) == 21
sdk_report = out / 'schema-validation.json'
run([dotnet, validator / 'OfficeValidation.dll', out / 'corpus', sdk_report], out / 'schema-validation.log')
sdk = json.loads(sdk_report.read_text())
expected_outputs = {
    str((out / item['output']).resolve()): item['outputSha256']
    for item in receipt['cases']
}
receipt['validation'] = verify_report(sdk, expected_outputs, 0)
receipt['sdkReportSha256'] = sha(sdk_report)
receipt['sdkLogSha256'] = sha(out / 'schema-validation.log')
receipt['sdkSummary'] = {k: sdk[k] for k in ('Files', 'Failures')}
receipt['sourceAfter'] = source_snapshot(root)
receipt['sourceUnchanged'] = receipt['sourceAfter'] == before
for item in receipt['cases']:
    assert sha(out / item['source']) == item['sourceSha256']
    assert sha(out / item['output']) == item['outputSha256']
for name, expected in receipt['validatorArtifacts'].items():
    assert sha(validator / name) == expected
receipt['passed'] = receipt['sourceUnchanged']
save()
print(json.dumps({'passed': receipt['passed'], 'cases': len(receipt['cases']), 'schema': receipt['sdkSummary']}))
