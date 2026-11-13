#!/usr/bin/env python3
"""Semantic corruption controls after checking the complete original byte seals."""
import contextlib
import io
import json
from pathlib import Path

import verify


def edit(records, name, change):
    result = dict(records)
    data = json.loads(records[name])
    change(data)
    result[name] = (json.dumps(data) + '\n').encode()
    return result


def main():
    with contextlib.redirect_stdout(io.StringIO()):
        metadata, host, external = verify.verify(Path(__file__).resolve().parent)
    rejected = []
    source = json.loads(metadata['source.json'])['files']

    def control(name, action):
        try:
            action()
        except (ValueError, KeyError, IndexError):
            rejected.append(name)
        else:
            raise RuntimeError('Accepted semantic corruption: ' + name)

    m = lambda name, change: verify.verify_host(edit(metadata, name, change), host)
    h = lambda name, change: verify.verify_host_inventory(metadata, edit(host, name, change))
    c = lambda name, change: verify.verify_coverage(metadata, edit(host, name, change), source)
    n = lambda change: verify.verify_native(metadata, host, edit(external, 'host-render/render-report.json', change))
    e = lambda name, change: verify.verify_external(edit(metadata, name, change), host, external)
    s = lambda change: verify.verify_schema(host, edit(external, 'schema-report.json', change))
    control('wrong committed source', lambda: m('source.json', lambda x: x.update(commit='0' * 40)))
    control('failed host step', lambda: m('office-host-jobs.json', lambda x: x['jobs'][0]['steps'][7].update(conclusion='failure')))
    control('wrong host artifact source', lambda: m('office-artifacts-host.json', lambda x: x['artifacts'][0]['workflow_run'].update(head_sha='0' * 40)))
    control('missing required host output', lambda: h('build/fidelity-host/inventory.json', lambda x: x['files'].pop()))
    control('different host output bytes', lambda: h('build/fidelity-host/inventory.json', lambda x: x['files'][0].update(sha256='0' * 64)))
    control('wrong owning OPC part', lambda: h('build/fidelity-host/inventory.json', lambda x: x['files'][0].update(main_part='word/unrelated.xml')))
    collection = verify.COVERAGE + '/collection-receipt.json'
    control('substituted Flutter command', lambda: c(collection, lambda x: x.update(command=['true'])))
    control('unrelated host test file', lambda: c(collection, lambda x: x['command'].__setitem__(-1, 'test/unrelated.dart')))
    control('wrong collection cwd', lambda: c(collection, lambda x: x.update(host_root='/different/source')))
    control('false pristine test pubspec', lambda: c(collection, lambda x: x['input_sha256'].update({'pubspec.yaml': source['pubspec.yaml']['sha256']})))
    control('changed root lock', lambda: c(collection, lambda x: x['input_sha256'].update({'pubspec.lock': '0' * 64})))
    control('extra generated input', lambda: c(collection, lambda x: x['input_sha256'].update({'unrelated/generated.json': '0' * 64})))
    control('wrong Flutter version', lambda: c(collection, lambda x: x['runtime'].update(version='{}')))
    control('invented coverage total', lambda: c(verify.COVERAGE + '/gaps.json', lambda x: x.update(covered_lines=4138)))
    altered = dict(host)
    altered[verify.COVERAGE + '/lcov.info'] = altered[verify.COVERAGE + '/lcov.info'].replace(b'DA:', b'DZ:', 1)
    control('modified raw LCOV', lambda: verify.verify_coverage(metadata, altered, source))
    control('wrong final run head', lambda: e('office-final-run.json', lambda x: x.update(head_sha='0' * 40)))
    control('failed external job', lambda: e('office-final-jobs.json', lambda x: x['jobs'][1].update(conclusion='failure')))
    control('substituted required external step', lambda: e('office-final-jobs.json', lambda x: x['jobs'][1]['steps'][5].update(name='Unrelated successful command')))
    control('missing SDK package', lambda: s(lambda x: x['Reports'].pop()))
    control('wrong SDK package hash', lambda: s(lambda x: x['Reports'][0].update(Sha256='0' * 64)))
    control('SDK errors hidden by zero total', lambda: s(lambda x: x['Reports'][0].update(Errors=[{'Description': 'invalid'}])))
    control('SDK exception hidden by empty errors', lambda: s(lambda x: x['Reports'][0].update(Exception='validation failed despite empty Errors')))
    altered = dict(external)
    name = next(name for name in external if name.startswith('host-input/'))
    altered[name] = external[name] + b'changed'
    control('substituted staged host package', lambda: verify.verify_native(metadata, host, altered))
    control('invented schema-only exclusion', lambda: n(lambda x: x.update(native_schema_only_files=1)))
    control('invented baseline comparison', lambda: n(lambda x: x.update(baseline_comparisons=1)))
    control('missing native record', lambda: n(lambda x: x['reports'].pop()))
    control('wrong native source hash', lambda: n(lambda x: x['reports'][0].update(input_sha256='0' * 64)))
    control('changed native conversion argv', lambda: n(lambda x: x['reports'][0]['conversion_attempts'][0].update(command=['true'])))
    control('invented native retry', lambda: n(lambda x: x['reports'][0]['conversion_attempts'].append(x['reports'][0]['conversion_attempts'][0])))
    control('wrong native page fingerprint', lambda: n(lambda x: x['reports'][0]['pixel_sha256'].__setitem__(0, '0' * 64)))
    control('wrong native extracted text', lambda: n(lambda x: x['reports'][0].update(text='invented')))
    control('altered three-save membership', lambda: n(lambda x: x['cycle_comparisons'][0]['files'].__setitem__(1, 'unrelated.docx')))
    control('invented picture measurement', lambda: n(lambda x: next(r for r in x['reports'] if 'picture_pixel_evidence' in r)['picture_pixel_evidence'].update(black_pixels=0)))
    print(json.dumps({'validEvidenceAccepted': True, 'semanticCorruptionsRejected': len(rejected), 'controls': rejected}, indent=2))


if __name__ == '__main__':
    main()
