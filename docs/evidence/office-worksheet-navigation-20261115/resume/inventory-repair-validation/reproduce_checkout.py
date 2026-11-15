#!/usr/bin/env python3
"""Reproduce historical output collisions without modifying a checkout.

The recorded execution used source cb23bdadffb95532d513cbc3bbc62d8bafa978fd,
the recovered run 43681914471 bundle, and the helper from 1a86e790.
Pass a fresh --replay directory so earlier evidence cannot be overwritten.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--original-helper', type=Path, required=True)
    parser.add_argument('--replay', type=Path, required=True)
    parser.add_argument('--reports', type=Path, required=True)
    args = parser.parse_args()
    args.replay.mkdir(parents=True, exist_ok=False)
    args.reports.mkdir(parents=True, exist_ok=False)
    shutil.copytree(args.bundle / 'build', args.replay / 'build')
    current = load('current', args.repo / 'tool/office_host_evidence.py')
    original = load('original', args.original_helper)
    original.MANIFEST = current.MANIFEST
    anchors = ['/'.join(parts) + '/'
               for parts in (*current.RENDERED_ROOTS, *current.SCHEMA_ONLY_ROOTS)]
    tracked = subprocess.check_output(
        ['git', 'ls-files', '-z', 'docs/evidence'], cwd=args.repo, text=True)
    copied = []
    for name in tracked.split('\0'):
        if name and any('/' + anchor in name for anchor in anchors):
            target = args.replay / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(args.repo / name, target)
            copied.append(name)
    (args.reports / 'historical-files.txt').write_text('\n'.join(copied) + '\n')
    reports = {
        'checkout-original': original.inspect(args.replay),
        'checkout-positive': current.inspect(args.replay, layout='checkout'),
        'checkout-wrong-artifact-layout': current.inspect(args.replay, layout='artifact'),
    }
    for name, report in reports.items():
        (args.reports / f'{name}.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f"{name}: {report['verified']}/{report['expected']}; "
              f"{len(report['failures'])} failures")


if __name__ == '__main__':
    main()
