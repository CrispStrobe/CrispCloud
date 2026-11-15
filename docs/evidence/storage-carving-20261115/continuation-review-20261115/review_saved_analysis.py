#!/usr/bin/env python3
"""Verify retained analysis receipts against their hashes and this source tree.

The comparison covers tracked non-evidence inputs. Recorded package graphs are
checked for within-run stability, not relabeled as this workspace's resolution.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo = args.repo.resolve()
    git = lambda *argv: subprocess.check_output(['git', '-C', str(repo), *argv])
    head = git('rev-parse', 'HEAD').decode().strip()
    tracked = {p.decode() for p in git('ls-files', '-z').split(b'\0')
               if p and not p.startswith(b'docs/evidence/')}
    base = repo/'docs/evidence/storage-carving-20261115/local-resume-20261115T1010'
    rows = []
    for name, count in [('analysis-app-final-2', 53),
                        ('analysis-engine-final-2', 5), ('analysis-cli-final', 1)]:
        directory = base/name
        metadata = json.loads((directory/'metadata.json').read_text())
        artifacts = json.loads((directory/'artifacts-sha256.json').read_text())
        invalid = []
        for relative, expected in artifacts.items():
            path = directory/relative
            if not path.is_file() or sha(path.read_bytes()) != expected['sha256'] or path.stat().st_size != expected['size']:
                invalid.append(relative)
        before = json.loads(gzip.decompress((directory/'inputs-before.json.gz').read_bytes()))
        after = json.loads(gzip.decompress((directory/'inputs-after.json.gz').read_bytes()))
        source_mismatches = []
        for relative in sorted(tracked):
            path = repo/relative
            data = str(path.readlink()).encode() if path.is_symlink() else path.read_bytes()
            if before['entries'].get(relative, {}).get('sha256') != sha(data):
                source_mismatches.append(relative)
        entries_digest = sha((json.dumps(before['entries'], sort_keys=True, indent=2)+'\n').encode())
        stability = (before['entries'] == after['entries']
                     and entries_digest == before['entries_sha256'] == after['entries_sha256']
                     == metadata['before_entries_sha256'] == metadata['after_entries_sha256']
                     and metadata['before_tools'] == metadata['after_tools']
                     and metadata['before_git']['head'] == metadata['after_git']['head']
                     and metadata['before_git']['tree'] == metadata['after_git']['tree'])
        command = metadata['command']
        analyzed = [arg for arg in command[2:] if not arg.startswith('--')]
        command_valid = command[:2] == ['dart', 'analyze'] and '--fatal-infos' in command and '--fatal-warnings' in command and len(analyzed) == count
        cli_inputs = name != 'analysis-cli-final' or all(
            any(path.endswith('cli/.dart_tool/'+suffix) for path in metadata['before_tools'])
            for suffix in ('package_config.json', 'package_graph.json'))
        success = (not invalid and not source_mismatches and stability and command_valid
                   and cli_inputs and metadata['returncode'] == 0
                   and metadata['qualification_success'] and metadata['inputs_and_commit_stable'])
        rows.append({'gate': name, 'tested_head': metadata['before_git']['head'],
                     'analyzed_files': len(analyzed), 'artifact_count': len(artifacts),
                     'invalid_artifacts': invalid, 'recomputed_run_stability': stability,
                     'strict_command_valid': command_valid, 'cli_resolution_covered': cli_inputs,
                     'tracked_non_evidence_inputs_compared': len(tracked),
                     'source_mismatches': source_mismatches, 'success': success})
    result = {'schema': 1, 'at': datetime.now(timezone.utc).isoformat(),
              'review_head': head, 'reviews': rows, 'success': all(row['success'] for row in rows),
              'scope': 'Integrity of saved analysis receipts and equality of every current tracked non-evidence input. The original recorded dependency graphs are stable within each run; this does not claim current-workspace execution.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
    return 0 if result['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
