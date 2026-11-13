#!/usr/bin/env python3
"""Independent semantic corruptions after bypassing the outer checksum seals."""
import contextlib
import io
import json
from pathlib import Path

import verify


def edit(records, name, change):
    records = dict(records)
    data = json.loads(records[name])
    change(data)
    records[name] = (json.dumps(data) + '\n').encode()
    return records


def main():
    with contextlib.redirect_stdout(io.StringIO()):
        metadata, provider = verify.verify(Path(__file__).resolve().parent)
    rejected = []

    def control(name, action):
        try:
            action()
        except (ValueError, KeyError):
            rejected.append(name)
        else:
            raise RuntimeError('Accepted semantic corruption: ' + name)

    p = lambda name, change: verify.verify_provider(edit(provider, name, change))
    m = lambda name, change: verify.verify_metadata(edit(metadata, name, change), provider)
    control('claimed provider promotion', lambda: p('results/report.json', lambda x: x.update(promotion_ready=True)))
    control('missing known provider gap', lambda: p('results/report.json', lambda x: x['known_gaps'].pop()))
    control('misattributed provider source', lambda: p('results/report.json', lambda x: x.update(workflow_commit='0' * 40)))
    control('unreported raw provider difference', lambda: p('results/dart.json',
            lambda x: x['results']['filen.chunk.0'].update(value={'unexpected': True})))
    control('wrong actual cross-decryption', lambda: p('results/rust-to-dart.json',
            lambda x: x['results']['filen.chunk.0'].update(value={'unexpected': True})))
    control('failed hosted provider step', lambda: m('provider-jobs.json',
            lambda x: x['jobs'][0]['steps'][8].update(conclusion='failure')))
    control('wrong hosted branch', lambda: m('provider-run.json', lambda x: x.update(head_branch='main')))
    control('different source artifact', lambda: m('provider-artifacts.json',
            lambda x: x['artifacts'][0].update(digest='sha256:' + '0' * 64)))
    control('extra omitted output', lambda: m('provider-retention.json',
            lambda x: x['omitted'].update({'results/report.json': {'reason': 'omitted'}})))
    control('incomplete source inventory', lambda: m('source.json', lambda x: x['files'].pop('pubspec.yaml')))
    control('invented Office completion', lambda: m('queue/office-queued-run.json',
            lambda x: x.update(status='completed', conclusion='success')))
    control('invented Office runner', lambda: m('queue/office-jobs.json',
            lambda x: x['jobs'][0].update(runner_id=42, runner_name='invented')))
    altered = dict(metadata)
    altered['provider-job.log'] = altered['provider-job.log'].replace(
        b'131 cases; 363 cross-decryptions; 0 failures; 10 reviewed gaps', b'provider results omitted')
    control('missing actual result marker', lambda: verify.verify_metadata(altered, provider))
    print(json.dumps({'validEvidenceAccepted': True, 'semanticCorruptionsRejected': len(rejected),
                      'controls': rejected}, indent=2))


if __name__ == '__main__':
    main()
