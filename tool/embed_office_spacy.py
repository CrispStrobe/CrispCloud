#!/usr/bin/env python3
"""Embed an authenticated local spaCy build and model before app signing."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def embed(app, library, bundle, notices, expected):
    if digest(library) != expected:
        raise ValueError('Native library does not match the compiled identity')
    subprocess.run(['codesign', '--verify', '--strict', str(library)], check=True)
    manifest = json.loads((bundle / 'manifest.json').read_text())
    if digest(bundle / 'manifest.json') != 'd599768375de3dc56abcca5cf1d49da0015857f9d3a10640aebb5317ef5d427e':
        raise ValueError('Unexpected model manifest')
    for name, record in manifest['files'].items():
        if Path(name).name != name or digest(bundle / name) != record['sha256']:
            raise ValueError('Changed model payload: ' + name)
    destination = app / 'Contents/Resources/spacy-w7'
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    shutil.copytree(bundle, destination / 'bundle')
    native = destination / expected
    native.mkdir()
    shutil.copy2(library, native / 'libcrispembed-spacy.dylib')
    shutil.copytree(notices, destination / 'licenses')
    (destination / 'build.json').write_text(json.dumps({
        'native_sha256': expected,
        'model_sha256': digest(bundle / 'model.gguf'),
        'provider_default': 'OFF',
        'manual_grammar_qualified': False,
    }, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['app', 'library', 'bundle', 'notices']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    embed(args.app, args.library, args.bundle, args.notices, args.sha256)
