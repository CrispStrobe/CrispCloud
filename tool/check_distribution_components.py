#!/usr/bin/env python3
"""Guard prohibited bundled backends, plus explicit optional FUSE builds."""
import argparse
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def check_sources(root=ROOT):
    for name in ['pubspec.lock', 'cli/pubspec.lock', 'packages/crisp_storage/pubspec.yaml']:
        text = (root / name).read_text()
        if re.search(r'^\s*dart_smb2:', text, re.M):
            raise ValueError(f'Bundled LGPL SMB dependency reintroduced: {name}')
    if (root / 'packages/dart_smb2').exists():
        raise ValueError('Removed SMB native downloader/source package reintroduced')
    for name in ['packages/crisp_ios_shell/LICENSE',
                 'packages/crisp_ios_shell/ios/Resources/NativeNotices.txt']:
        text = (root / name).read_text()
        if 'GNU Bison' in text and 'As a special exception, you may create a larger work' not in text:
            raise ValueError(f'Bison notice is missing its larger-work exception: {name}')
    return True


def check_artifact(path, *, fuse_opt_in=False):
    # Inspect app/CLI bundles and ZIP/APK/IPA member names without extracting.
    def inspect_name(name):
        basename = name.replace('\\', '/').rsplit('/', 1)[-1].lower()
        if re.search(r'(?:lib)?smb2(?:[._-]|$)', basename) or 'dart_smb2' in basename:
            raise ValueError(f'Prohibited libsmb2 native artifact: {name}')
        if basename == 'crispcloud_fuse_bridge' and not fuse_opt_in:
            raise ValueError(f'Optional FUSE helper in a default build: {name}')
    if path.is_dir():
        for file in path.rglob('*'):
            inspect_name(str(file))
            if file.is_file() and file.suffix in {'.json', '.yaml'} and file.stat().st_size <= 4 * 1024 * 1024:
                if b'package:dart_smb2' in file.read_bytes():
                    raise ValueError(f'Prohibited libsmb2 native-asset declaration: {file}')
    elif path.is_file() and zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                inspect_name(member.filename)
                if member.filename.endswith(('.json', '.yaml')) and member.file_size <= 4 * 1024 * 1024:
                    if b'package:dart_smb2' in archive.read(member):
                        raise ValueError(f'Prohibited libsmb2 native-asset declaration: {member.filename}')
    else:
        raise ValueError('Pass an app/CLI directory or ZIP/APK/IPA artifact')

    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', type=Path)
    parser.add_argument('--fuse-opt-in', action='store_true')
    args = parser.parse_args()
    check_sources()
    if args.artifact:
        check_artifact(args.artifact, fuse_opt_in=args.fuse_opt_in)
    print('Distribution dependency and optional-component guards passed')
