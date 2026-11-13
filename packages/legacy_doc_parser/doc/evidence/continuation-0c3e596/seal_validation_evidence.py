#!/usr/bin/env python3
"""Seal or independently verify the recorded portable and schema artifacts.

This checks retained bytes and receipts; it does not rerun the compiler or SDK.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def verify(directory):
    manifest = json.loads((directory / 'validation-artifacts.manifest.json').read_text())
    archive = directory / manifest['archive']['path']
    assert archive.stat().st_size == manifest['archive']['size']
    assert digest(archive.read_bytes()) == manifest['archive']['sha256']
    expected = {item['path']: item for item in manifest['files']}
    assert len(expected) == len(manifest['files'])
    payloads = {}
    with tarfile.open(archive, 'r:xz') as packed:
        for member in packed:
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute() and '..' not in path.parts
            assert member.name in expected and member.name not in payloads
            data = packed.extractfile(member).read()
            item = expected[member.name]
            assert len(data) == item['size'] == member.size
            assert digest(data) == item['sha256']
            payloads[member.name] = data
    assert set(payloads) == set(expected)
    portable = json.loads(payloads['portable/receipt.json'])
    schema = json.loads(payloads['schema/report.json'])
    extra = json.loads(payloads['extra-table-schema/receipt.json'])
    source = manifest['parserCommit']
    assert source == portable['commit'] == schema['gitHead'] == extra['parserCommit']
    assert portable['success'] and portable['inputsUnchanged']
    assert portable['inputsBefore'] == portable['inputsAfter']
    assert portable['dirtyBefore'] == portable['dirtyAfter'] == ''
    for stage in portable['stages']:
        assert stage['exitCode'] == 0
        assert digest(payloads['portable/' + stage['log']]) == stage['logSha256']
    assert schema['passed'] and not schema['gitWorktreeDirty']
    assert schema['source'] == schema['sourceAfter']
    assert schema['validation']['hashesVerified'] and schema['validation']['errors'] == 0
    assert schema['validation']['files'] == len(schema['corpus']['cases']) == 228
    assert digest(payloads['schema/schema-validation.json']) == schema['validation']['reportSha256']
    sdk = json.loads(payloads['schema/schema-validation.json'])
    assert sdk['Files'] == len(sdk['Reports']) == 228 and sdk['Failures'] == 0
    seen = set()
    for item in sdk['Reports']:
        original = item['File']
        assert original in schema['corpus']['outputs'] and original not in seen
        seen.add(original)
        assert not item['Errors'] and 'Exception' not in item
        assert item['Sha256'] == schema['corpus']['outputs'][original]
        relative = original.split('/corpus/', 1)[1]
        assert digest(payloads['schema/corpus/' + relative]) == item['Sha256']
        assert payloads['schema/corpus/' + relative] == payloads['schema/corpus-repeat/' + relative]
    assert set(schema['corpus']['outputs']) == seen
    assert extra['passed'] and extra['sourceUnchanged']
    assert extra['sourceBefore'] == extra['sourceAfter'] == schema['sourceAfter']
    assert extra['validation'] == {'files': 21, 'errors': 0, 'hashesVerified': True}
    assert len(extra['cases']) == 21
    for item in extra['cases']:
        for key in ('source', 'output', 'log'):
            assert digest(payloads['extra-table-schema/' + item[key]]) == item[key + 'Sha256']
        assert item['opcPartsIdentical']
    assert digest(payloads['extra-table-schema/schema-validation.json']) == extra['sdkReportSha256']
    extra_sdk = json.loads(payloads['extra-table-schema/schema-validation.json'])
    assert extra_sdk['Files'] == len(extra_sdk['Reports']) == 21 and extra_sdk['Failures'] == 0
    extra_outputs = {item['output']: item['outputSha256'] for item in extra['cases']}
    extra_seen = set()
    for item in extra_sdk['Reports']:
        relative = 'corpus/' + item['File'].split('/corpus/', 1)[1]
        assert relative in extra_outputs and relative not in extra_seen
        extra_seen.add(relative)
        assert not item['Errors'] and 'Exception' not in item
        assert item['Sha256'] == extra_outputs[relative]
    assert set(extra_outputs) == extra_seen
    return {'verified': True, 'parserCommit': source, 'files': len(expected),
            'requiredSchemaOutputs': 228, 'extraTableSchemaOutputs': 21,
            'archiveSha256': manifest['archive']['sha256']}


def seal(validation, directory):
    directory.mkdir(parents=True, exist_ok=False)
    files, excluded = {}, []
    for source_name, prefix in [('portable-0c3e596', 'portable'),
                                ('schema-0c3e596', 'schema'),
                                ('table-schema-0c3e596', 'extra-table-schema')]:
        root = validation / source_name
        for source in sorted(root.rglob('*')):
            if not source.is_file():
                continue
            relative = source.relative_to(root)
            data = source.read_bytes()
            name = prefix + '/' + relative.as_posix()
            record = {'path': name, 'size': len(data), 'sha256': digest(data)}
            if relative.parts[0] == 'validator' or relative.as_posix() == 'convert':
                excluded.append(record)
            else:
                files[name] = data
    archive = directory / 'validation-artifacts.tar.xz'
    with tarfile.open(archive, 'w:xz', preset=6) as packed:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            packed.addfile(info, io.BytesIO(data))
    source = json.loads(files['portable/receipt.json'])['commit']
    manifest = {'version': 1, 'parserCommit': source,
                'archive': {'path': archive.name, 'size': archive.stat().st_size,
                            'sha256': digest(archive.read_bytes())},
                'files': [{'path': name, 'size': len(data), 'sha256': digest(data)}
                          for name, data in sorted(files.items())],
                'omittedReproducibleExecutables': excluded,
                'scope': 'Complete portable logs/receipt; primary SDK inputs, both generated corpora, build/validation logs and receipts; 21 independently authored table inputs and actual final outputs. Derived validator/converter executables omitted with hashes retained.'}
    write_json(directory / 'validation-artifacts.manifest.json', manifest)
    return verify(directory)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--seal-from', type=Path)
    args = parser.parse_args()
    result = seal(args.seal_from, args.directory) if args.seal_from else verify(args.directory)
    print(json.dumps(result, sort_keys=True))
