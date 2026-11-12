"""Independently read native large TAR/CBT creation fixtures in bounded chunks.

The producer is archive_large_tar_creation_test.dart with
CRISP_LARGE_TAR_REFERENCE_DIR set to a new, empty output directory. No large
payload or archive is committed to the repository. Python tarfile and GNU tar
are validation tools, not CrispCloud runtime dependencies.
"""

import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import tarfile


CHUNK = 1024 * 1024


def digest_stream(stream):
    digest = hashlib.sha256()
    length = 0
    while chunk := stream.read(CHUNK):
        digest.update(chunk)
        length += len(chunk)
    return length, digest.hexdigest()


def pattern_digest(size, seed):
    block = bytes((index + seed) % 251 for index in range(65536))
    digest = hashlib.sha256()
    full, tail = divmod(size, len(block))
    for _ in range(full):
        digest.update(block)
    digest.update(block[:tail])
    return digest.hexdigest()


def gnu_payload(path, member):
    process = subprocess.Popen(
        ['tar', '--extract', '--to-stdout', '--file', str(path), '--', member],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        result = digest_stream(process.stdout)
        error = process.stderr.read().decode(errors='replace')
        assert process.wait() == 0, (path, member, error)
        return result
    finally:
        process.stdout.close()
        process.stderr.close()
        if process.poll() is None:
            process.kill()
            process.wait()


def check_case(directory, case):
    name = case['archive']
    assert Path(name).name == name and name.endswith(('.tar', '.cbt')), name
    path = directory / name
    assert path.stat().st_size == case['bytes'] <= 2 * 1024**3
    with path.open('rb') as stream:
        assert digest_stream(stream) == (case['bytes'], case['sha256'])
    expected = {entry['path']: entry for entry in case['members']}
    assert len(expected) == len(case['members'])
    payload = sum(entry['size'] for entry in expected.values())
    assert max(entry['size'] for entry in expected.values()) > 64 * 1024**2
    if name.endswith('.tar'):
        assert payload > 256 * 1024**2
    seen = set()
    with tarfile.open(path, 'r:') as archive:
        for member in archive:
            name = member.name.rstrip('/')
            assert name in expected and name not in seen, (path, name)
            seen.add(name)
            wanted = expected[name]
            assert member.isfile() or member.isdir(), (path, name, member.type)
            assert member.isdir() == wanted['directory'], (path, name, 'type')
            assert member.size == wanted['size'], (path, name, 'size')
            assert member.mode == wanted['mode'], (path, name, 'mode')
            assert member.mtime == wanted['mtime'], (path, name, 'mtime')
            if member.isfile():
                digest = pattern_digest(wanted['size'], wanted['pattern_seed'])
                assert digest == wanted['sha256'], (path, name, 'source pattern')
                with archive.extractfile(member) as stream:
                    assert digest_stream(stream) == (wanted['size'], digest), (path, name, 'tarfile payload')
                assert gnu_payload(path, name) == (wanted['size'], digest), (path, name, 'GNU payload')
    assert seen == expected.keys(), (path, 'namespace')
    subprocess.run(['tar', '--list', '--file', str(path)], check=True, capture_output=True)

    assert case['source_read_passes'] == 3
    assert case['max_source_or_staged_chunk'] <= 65536
    assert case['max_output_chunk'] <= 256 * 1024
    phases = case['progress']['phases']
    for phase, total in (
        ('packing', payload),
        ('verifying', 2 * payload + case['bytes']),
        ('saving', 2 * case['bytes'] + payload),
    ):
        assert phases[phase]['total'] == phases[phase]['completed'] == total
        assert phases[phase]['events'] > 5 and phases[phase]['timer_ticks'] > 0
    memory = case['progress']
    assert memory['peak_sampled_rss'] >= memory['baseline_rss']
    assert memory['peak_rss_increase'] == memory['peak_sampled_rss'] - memory['baseline_rss']
    print(f"PASS {path.name}: {case['bytes']} archive bytes, {payload} payload bytes, "
          f"{len(seen)} members; Python/GNU SHA-256 and metadata; "
          f"sampled RSS increase {memory['peak_rss_increase']} bytes")


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Supply the native large TAR reference directory.')
    directory = Path(sys.argv[1]).resolve()
    manifest = json.loads((directory / 'manifest.json').read_text())
    assert manifest['version'] == 1
    cases = manifest['cases']
    assert {case['archive'] for case in cases} == {'native-large.tar', 'native-large.cbt'}
    print(f'Python {platform.python_version()} tarfile')
    print(subprocess.run(['tar', '--version'], check=True, capture_output=True, text=True).stdout.splitlines()[0])
    for case in cases:
        check_case(directory, case)
    print(f'All {len(cases)} independent native large TAR/CBT checks passed.')


if __name__ == '__main__':
    main()
