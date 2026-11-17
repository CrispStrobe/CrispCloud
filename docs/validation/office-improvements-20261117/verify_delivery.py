#!/usr/bin/env python3
"""Verify published non-documentation source and every archived evidence member."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import subprocess
import tarfile

PREFIX = 'docs/validation/office-improvements-20261117/'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--qualified-source', required=True)
    parser.add_argument('--candidate', default='HEAD')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    def git(*a):
        return subprocess.check_output(['git', '-C', str(args.repo), *a])
    def tree(ref):
        result = {}
        for row in git('ls-tree', '-r', '-z', ref).split(b'\0'):
            if row:
                meta, name = row.split(b'\t', 1)
                if not name.startswith(b'docs/'):
                    result[name.decode()] = meta.decode()
        return result
    expected = tree(args.qualified_source)
    actual = tree(args.candidate)
    assert expected == actual, 'Published program blobs or modes differ from qualified source'
    index = json.loads(git('show', args.candidate + ':' + PREFIX + 'evidence-index.json'))
    data = git('show', args.candidate + ':' + PREFIX + index['archive'])
    sha = hashlib.sha256(data).hexdigest()
    assert (len(data), sha) == (index['bytes'], index['sha256'])
    seen = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
        for item in archive:
            assert item.isfile() and item.name not in seen
            content = archive.extractfile(item).read()
            seen[item.name] = {'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()}
    assert seen == index['members'] and len(seen) == index['member_count']
    result = {'passed': True, 'qualified_source': git('rev-parse', args.qualified_source).decode().strip(),
              'candidate': git('rev-parse', args.candidate).decode().strip(),
              'source_entries_identical': len(expected), 'verified_archive_members': len(seen),
              'archive_bytes': len(data), 'archive_sha256': sha}
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
