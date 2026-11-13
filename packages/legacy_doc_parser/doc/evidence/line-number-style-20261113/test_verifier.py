#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Discriminating internal-binding controls after the outer byte checks."""
import copy
import json

import verify


def mutate_json(files, name, change):
    value = json.loads(files[name])
    change(value)
    files[name] = (json.dumps(value, indent=2) + '\n').encode()


def main():
    manifest, original = verify.load()
    verify.verify_payloads(manifest, original)
    results = []

    def rejects(name, change):
        files = dict(original)
        changed_manifest = copy.deepcopy(manifest)
        change(changed_manifest, files)
        try:
            verify.verify_payloads(changed_manifest, files)
        except (ValueError, KeyError) as error:
            results.append({'control': name, 'rejected': True, 'reason': str(error)})
        else:
            raise RuntimeError('Verifier accepted corruption: ' + name)

    rejects('actual command failed', lambda m, f: mutate_json(
        f, 'native/focused-tests.command.json', lambda d: d.update(exitCode=9)))
    rejects('unrelated command with retained success log', lambda m, f: mutate_json(
        f, 'native/focused-tests.command.json', lambda d: d.update(argv=['true'])))
    for stage_name in verify.SCHEMA_STAGES:
        rejects('unrelated SDK command: ' + stage_name, lambda m, f, name=stage_name: mutate_json(
            f, 'schema/report.json', lambda d: next(stage for stage in d['stages']
                                                   if stage['name'] == name).update(command=['true'])))
    rejects('generated second corpus omitted', lambda m, f: f.pop(
        next(n for n in f if n.startswith('schema/corpus-repeat/') and n.endswith('.docx'))))
    def stale_sdk_hash(manifest, files):
        mutate_json(files, 'schema/schema-validation.json',
                    lambda d: d['Reports'][0].update(Sha256='0' * 64))
        mutate_json(files, 'schema/report.json', lambda d: d['validation'].update(
            reportSha256=verify.sha(files['schema/schema-validation.json'])))

    rejects('SDK output hash stale despite resealed report', stale_sdk_hash)
    rejects('source bytes changed', lambda m, f: f.__setitem__(
        'source/test/fixtures/word_native/line-number-style.doc', b'changed source'))
    rejects('native cycle omitted', lambda m, f: mutate_json(
        f, 'native/report.json', lambda d: d['case']['roundtripCycles'].pop()))
    rejects('restored output replaced by failing baseline', lambda m, f: f.__setitem__(
        'diagnostic/line-style-control/restored-line-style.docx',
        f['diagnostic/line-style-control/converted.docx']))
    rejects('old output changed', lambda m, f: f.__setitem__(
        'native/unchanged/bookmarks/current.docx', b'changed old output'))
    rejects('font receipt altered', lambda m, f: mutate_json(
        f, 'native/report.json', lambda d: d.update(fontFilesSha256='0' * 64)))
    print(json.dumps({'validEvidenceAccepted': True, 'corruptionsRejected': len(results),
                      'pythonOptimizationEnabled': __debug__ is False, 'controls': results}, indent=2))


if __name__ == '__main__':
    main()
