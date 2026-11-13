#!/usr/bin/env python3
"""Verify captured official-head provider evidence without rerunning providers."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

APP = 'fb81b2ace557964459189afd7c0c7d76b2c9557d'
TREE = 'a14d066f1179ea00e20eaa3431aec0dd4fe05a5f'
RUN = 43390627091
JOB = 131769379332
ARTIFACT = 14020796791
ARTIFACT_SHA = '13800eb19f18cd237f43ac82efe889fcd641b0cd17e07108d7b01107f35bd495'
ENGINES = ['rust', 'dart', 'dart-pointycastle', 'dart-native']
GAPS = {
    'internxt.password.reject.123', 'internxt.text.roundtrip.0',
    'internxt.text.reject.bad-magic', 'internxt.text.encoding.utf8',
    'internxt.text.encoding.latin1', 'internxt.range.reject.0.-16',
    'internxt.range.reject.1.-16', 'internxt.mock.list.retry-503',
    'filen.mock.list.corrupt-metadata', 'internxt.mock.list.missing-result',
}
OMITTED = {'results/rust-probe', 'results/dart-probe'}
COMMAND = ('python _provider_conformance/conformance/run.py --pointycastle 4.0.0 '
           '--dart-pg 2.1.0 --dart-filen packages/filen_client --published-internxt 0.2.3')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unpack(raw):
    records = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:xz') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            require(member.isfile() and not path.is_absolute() and '..' not in path.parts, 'Unsafe member')
            require(member.name not in records and member.size <= 64 * 1024 * 1024, 'Duplicate/oversized member')
            records[member.name] = archive.extractfile(member).read()
            require(len(records) <= 1000 and sum(map(len, records.values())) <= 128 * 1024 * 1024, 'Archive limit')
    return records


def verify_provider(records):
    load = lambda name: json.loads(records['results/' + name + '.json'])
    report = load('report')
    require(report['schema'] == 1 and report['workflow_commit'] == APP, 'Provider report source')
    require(report['cases'] == 131 and report['engines'] == ENGINES, 'Provider case/engine inventory')
    require(report['failures'] == [] and report['passed'] is True, 'Provider failures')
    require(report['promotion_ready'] is False, 'Promotion limit changed')
    require(report['mock_cases'] == 34 and report['cross_decryptions'] == 363, 'Provider totals')
    require(report['probe_mode'] == 'compiled from source' and report['native_backend'] == 'openssl', 'Provider backend')
    gaps = report['known_gaps']
    require(len(gaps) == 10 and {gap['id'] for gap in gaps} == GAPS, 'Known gap inventory changed')
    raw = {engine: load(engine) for engine in ENGINES}
    ids = set(raw['rust']['results'])
    require(len(ids) == 131, 'Raw provider case count')
    for engine, result in raw.items():
        require(result['schema'] == 1 and set(result['results']) == ids, 'Raw case inventory: ' + engine)
        require(result['engine'] == ('rust' if engine == 'rust' else 'dart'), 'Raw engine identity')
    for engine, backend, actual in [('dart', 'cryptography', 'cryptography'),
                                     ('dart-pointycastle', 'pointycastle', 'pointycastle'),
                                     ('dart-native', 'native', 'openssl')]:
        require(raw[engine]['backend'] == backend and raw[engine]['actual_backend'] == actual, 'Backend identity')
    for gap in gaps:
        require(gap['reason'] and set(gap['results']) == set(ENGINES), 'Known gap description')
        require(gap['results'] == {engine: raw[engine]['results'][gap['id']] for engine in ENGINES}, 'Known gap/raw contradiction')
    differences = {case for case in ids if any(raw[engine]['results'][case] != raw['rust']['results'][case]
                                              for engine in ENGINES[1:])}
    require(differences == GAPS - {'internxt.mock.list.missing-result'}, 'Unreported provider difference')
    total = 0
    for producer in ENGINES:
        exports = load(producer + '-exports')['cases']
        require(exports == raw[producer]['exports'], 'Export/raw contradiction')
        require(len(exports) == (31 if producer == 'rust' else 30), 'Export count')
        expected = {case['id']: {'status': 'ok', 'value': case['expected']} for case in exports}
        require(len(expected) == len(exports), 'Duplicate export ID')
        for consumer in ENGINES:
            if producer == consumer:
                continue
            result = load(producer + '-to-' + consumer)
            require(result['schema'] == 1 and result['engine'] == ('rust' if consumer == 'rust' else 'dart'), 'Cross-decryption engine')
            require(result['results'] == expected and result['exports'] == [], 'Cross-decryption/export contradiction')
            total += len(result['results'])
    require(total == report['cross_decryptions'], 'Cross-decryption aggregate')
    require(len(load('mock-requests')) == 263, 'Mock request count')
    return report


def verify_metadata(records, provider, repository=None):
    load = lambda name: json.loads(records[name])
    run, jobs = load('provider-run.json'), load('provider-jobs.json')['jobs']
    require(run['id'] == RUN and run['head_sha'] == APP and run['head_commit']['tree_id'] == TREE, 'Hosted run identity')
    require(run['head_branch'] == 'feature/office-fidelity-gaps-20261113' and run['run_attempt'] == 1, 'Hosted branch/attempt')
    require(run['path'] == '.github/workflows/provider-conformance.yml', 'Hosted workflow')
    require(run['status'] == 'completed' and run['conclusion'] == 'success', 'Hosted run result')
    require(len(jobs) == 1 and jobs[0]['id'] == JOB and jobs[0]['run_id'] == RUN, 'Hosted job inventory')
    job = jobs[0]
    require(job['name'] == 'conformance' and job['head_sha'] == APP, 'Hosted job source')
    require(job['status'] == 'completed' and job['conclusion'] == 'success', 'Hosted job result')
    require(len(job['steps']) == 15 and all(step['status'] == 'completed' and step['conclusion'] == 'success'
                                         for step in job['steps']), 'Hosted step result')
    log = records['provider-job.log'].decode('utf-8-sig')
    require(COMMAND in log and APP in log and '6c1f351dbe0cb9efe2ecf19b009603907bf5cf2e' in log, 'Hosted log/source command')
    require('131 cases; 363 cross-decryptions; 0 failures; 10 reviewed gaps' in log, 'Hosted result marker')
    artifacts = load('provider-artifacts.json')
    require(artifacts['total_count'] == 1 and len(artifacts['artifacts']) == 1, 'Artifact inventory')
    artifact = artifacts['artifacts'][0]
    require(artifact['id'] == ARTIFACT and artifact['name'] == 'provider-conformance', 'Artifact identity')
    require(artifact['workflow_run']['id'] == RUN and artifact['workflow_run']['head_sha'] == APP, 'Artifact source')
    require(artifact['size_in_bytes'] == 54108309 and artifact['digest'] == 'sha256:' + ARTIFACT_SHA, 'Artifact ZIP seal')
    inventory, retention = load('provider-artifact-inventory.json'), load('provider-retention.json')
    require(inventory['artifact'] == artifact and inventory['archiveSha256'] == ARTIFACT_SHA, 'Downloaded artifact identity')
    require(inventory['archiveBytes'] == artifact['size_in_bytes'], 'Downloaded artifact size')
    require(inventory['fileCount'] == len(inventory['files']) == 27 and inventory['uncompressedBytes'] == 125772046, 'Original artifact inventory')
    require(set(retention['omitted']) == OMITTED and retention['retainedMembers'] == sorted(provider), 'Retention inventory')
    require(set(provider) | OMITTED == set(inventory['files']) and not (set(provider) & OMITTED), 'Missing artifact output')
    require(retention['sourceArtifactId'] == ARTIFACT and retention['sourceArtifactSha256'] == ARTIFACT_SHA, 'Retention source')
    require(retention['retainedMemberCount'] == len(provider) == 25 and retention['retainedBytes'] == 40388702, 'Retained output totals')
    for name, data in provider.items():
        expected = inventory['files'][name]
        require(len(data) == expected['bytes'] and sha(data) == expected['sha256'], 'Retained output bytes: ' + name)
    for name in OMITTED:
        expected = retention['omitted'][name]
        require(all(expected[key] == value for key, value in inventory['files'][name].items()), 'Omitted binary identity')
        require(expected['reason'].startswith('Reproducible compiled ELF probe'), 'Omitted binary rationale')
    source = load('source.json')
    require(source['commit'] == APP and source['tree'] == TREE and source['status'] == '' and len(source['files']) == 7579, 'Source snapshot')
    for name, data in records.items():
        if not name.startswith('source/'):
            continue
        expected = source['files'][name.removeprefix('source/')]
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        require(len(data) == expected['bytes'] and sha(data) == expected['sha256'] and blob == expected['gitBlob'], 'Captured source bytes')
    require(COMMAND in records['source/.github/workflows/provider-conformance.yml'].decode(), 'Captured workflow command')
    transition = load('app-final-official-transition.json')
    require(transition['newHead'] == APP and transition['expectedPreviousHead'] == '6f2e3245b7971d620410a65e75bf54b04132319a'
            and transition['force'] is False and transition['observedRef']['object']['sha'] == APP, 'Official transition')
    checkout = load('app-final-original-checkout.json')
    require(checkout['head'] == APP and checkout['tree'] == TREE and checkout['status'] == '', 'Original checkout')
    require(checkout['protectedBefore'] == checkout['protectedAfter'] and checkout['protectedUnchanged'], 'Protected checkout inputs')
    native = load('parser-native-evidence-source.json')
    data = records['parser-native-evidence-README.md']
    require(native['evidenceCommit'] == '822fdc533b9412ab5fdfd2ea1427357cc8d0ca0b'
            and native['measuredParserCommit'] == 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289', 'Native proof source')
    require(len(data) == native['bytes'] and sha(data) == native['sha256'] and
            hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == native['blob'], 'Native proof bytes')
    queue = load('queue/diagnosis.json')
    queued_run = load('queue/office-queued-run.json')
    queued_jobs = load('queue/office-jobs.json')['jobs']
    require(queue['runId'] == queued_run['id'] == 43390627156 and queue['head'] == queued_run['head_sha'] == APP, 'Queue source')
    require(queue['runStatus'] == queued_run['status'] == 'queued' and queued_run['conclusion'] is None, 'Queue observation status')
    require(len(queued_jobs) == 1 and queued_jobs[0]['id'] == queue['jobId'] == 131769379446, 'Queue job inventory')
    queued_job = queued_jobs[0]
    require(queued_job['status'] == queue['jobStatus'] == 'queued' and queued_job['steps'] == [] and queue['stepCount'] == 0, 'Queue steps')
    require(queued_job['labels'] == queue['labels'] == ['ubuntu-latest'], 'Queue runner labels')
    require(queued_job['runner_id'] == queue['runnerId'] == 0 and queued_job['runner_name'] == queue['runnerName'] == '', 'Queue runner assignment')
    require(load('queue/branch-running.json')['total_count'] == queue['sameBranchInProgressCount'] == 0, 'Same-branch running observation')
    require(load('queue/branch-pending.json')['total_count'] == queue['sameBranchPendingCount'] == 0, 'Same-branch pending observation')
    require(load('queue/branch-queued.json')['total_count'] == queue['sameBranchQueuedCount'] == 1, 'Same-branch queued observation')
    require(queue['firstJobHasNeeds'] is False and queue['externalSchemaNeeds'] == 'host-roundtrip', 'Queue dependency diagnosis')
    workflow = records['source/.github/workflows/office-fidelity.yml'].decode()
    first_job = workflow.split('  host-roundtrip:', 1)[1].split('  external-schema:', 1)[0]
    require('needs:' not in first_job and '    needs: host-roundtrip' in workflow, 'Queue workflow dependency')
    require('group: office-host-fidelity-${{ github.event.pull_request.number || github.ref }}' in workflow, 'Queue workflow concurrency')
    if repository is not None:
        git = lambda *args: subprocess.check_output(['git', '-C', str(repository), *args])
        require(git('rev-parse', APP + '^{tree}').decode().strip() == TREE, 'Git source tree')
        expected = {}
        for entry in git('ls-tree', '-rlz', APP).split(b'\0'):
            if not entry:
                continue
            metadata, name = entry.decode().split('\t')
            mode, kind, blob, size = metadata.split()
            require(kind == 'blob', 'Unexpected Git entry')
            expected[name] = (mode, blob, int(size))
        require(expected == {name: (item['gitMode'], item['gitBlob'], item['bytes']) for name, item in source['files'].items()}, 'Complete Git source inventory')


def verify(directory, repository=None):
    receipt = json.loads((directory / 'receipt.json').read_bytes())
    require(receipt['schemaVersion'] == 1 and receipt['measuredAppCommit'] == APP and receipt['measuredAppTree'] == TREE, 'Receipt source')
    for name in ['README.md', 'verify.py', 'test_verifier.py', 'manifest.json']:
        require(sha((directory / name).read_bytes()) == receipt['files'][name]['sha256'], 'Sealed helper: ' + name)
    raw = (directory / 'records.tar.xz').read_bytes()
    require(len(raw) == receipt['files']['records.tar.xz']['bytes'] and sha(raw) == receipt['files']['records.tar.xz']['sha256'], 'Metadata archive')
    records = unpack(raw)
    manifest = json.loads((directory / 'manifest.json').read_bytes())['files']
    require(set(records) == set(manifest), 'Metadata inventory')
    for name, data in records.items():
        require({'bytes': len(data), 'sha256': sha(data)} == manifest[name], 'Metadata bytes: ' + name)
    pieces = []
    for index, item in enumerate(receipt['providerParts'], 1):
        require(item['path'] == f'provider-outputs.part{index:02d}', 'Part ordering')
        data = (directory / item['path']).read_bytes()
        require(len(data) == item['bytes'] and sha(data) == item['sha256'], 'Provider part bytes')
        pieces.append(data)
    raw = b''.join(pieces)
    retention = json.loads(records['provider-retention.json'])
    require(len(raw) == retention['archiveBytes'] and sha(raw) == retention['archiveSha256'], 'Provider archive seal')
    provider = unpack(raw)
    verify_metadata(records, provider, repository)
    report = verify_provider(provider)
    print(f"Verified {len(records)} metadata records and 25 provider outputs: 131 cases, "
          f"363 cross-decryptions, 10 retained known gaps, promotion_ready={report['promotion_ready']}; app {APP}.")
    return records, provider


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--repository', type=Path)
    args = parser.parse_args()
    verify(args.directory, args.repository)
