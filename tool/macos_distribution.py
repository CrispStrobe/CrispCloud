#!/usr/bin/env python3
"""Build and verify explicit macOS distribution profiles (safe default: App Store)."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
METADATA = 'CrispDistribution.json'
ENTITLEMENTS = {'appstore': 'Runner/Release.entitlements',
                'github': 'Runner/Direct.entitlements'}


def defines(encoded):
    values = {}
    for item in encoded.split(','):
        if item:
            key, separator, value = base64.b64decode(item, validate=True).decode().partition('=')
            if separator:
                values[key] = value
    return values


def validate(profile, values):
    if profile not in ENTITLEMENTS:
        raise ValueError(f'Unknown macOS distribution profile: {profile}')
    if values.get('CRISP_DISTRIBUTION', 'appstore') != profile:
        raise ValueError('Native and Dart distribution profiles disagree; use tool/macos_distribution.py build')
    fuse = values.get('CRISP_ENABLE_FUSE', 'false')
    if fuse not in ('true', 'false'):
        raise ValueError('CRISP_ENABLE_FUSE must be true or false')
    if profile == 'appstore' and fuse == 'true':
        raise ValueError('App Store builds exclude FUSE; use build --profile github --fuse for the optional helper')
    return fuse == 'true'


def stage(profile, output, encoded):
    enabled = validate(profile, defines(encoded))
    output.mkdir(parents=True, exist_ok=True)
    (output / METADATA).write_text(json.dumps({'profile': profile, 'fuse': enabled}, indent=2) + '\n')
    return enabled


def app_profile(app):
    file = app / 'Contents/Resources' / METADATA
    profile = json.loads(file.read_text())['profile'] if file.exists() else 'appstore'
    if profile not in ENTITLEMENTS:
        raise ValueError('Unknown recorded distribution profile')
    return profile


def check_entitlements(profile, entitlements):
    sandbox = entitlements.get('com.apple.security.app-sandbox', False)
    if profile == 'appstore' and sandbox is not True:
        raise ValueError('App Store app must be sandboxed')
    if profile == 'appstore' and any(entitlements.get(key) for key in (
            'com.apple.security.cs.disable-library-validation', 'get-task-allow',
            'com.apple.security.get-task-allow')):
        raise ValueError('App Store app contains direct/debug signing capabilities')
    if profile == 'github' and sandbox is not False:
        raise ValueError('GitHub app must use direct-distribution entitlements')


def verify(profile, app):
    import check_distribution_components as components
    metadata = json.loads((app / 'Contents/Resources' / METADATA).read_text())
    if metadata.get('profile') != profile or type(metadata.get('fuse')) is not bool:
        raise ValueError('Missing or mismatched signed distribution metadata')
    enabled = metadata['fuse']
    validate(profile, {'CRISP_DISTRIBUTION': profile, 'CRISP_ENABLE_FUSE': str(enabled).lower()})
    components.check_artifact(app, fuse_opt_in=enabled)
    helper = app / 'Contents/Resources/crispcloud_fuse_bridge'
    if helper.exists() != enabled:
        raise ValueError('FUSE helper disagrees with distribution metadata')
    subprocess.run(['codesign', '--verify', '--deep', '--all-architectures', '--strict', str(app)], check=True)
    data = subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', str(app)], stderr=subprocess.DEVNULL)
    check_entitlements(profile, plistlib.loads(data))
    if enabled:
        subprocess.run(['codesign', '--verify', '--all-architectures', '--strict', str(helper)], check=True)
        data = subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', str(helper)], stderr=subprocess.DEVNULL)
        entitlements = plistlib.loads(data)
        if entitlements.get('com.apple.security.app-sandbox') or entitlements.get('com.apple.security.inherit'):
            raise ValueError('Direct FUSE helper must not inherit a sandbox')
    print(f'Verified signed {profile} macOS app (FUSE: {enabled})')


def build(profile, fuse, flutter, arguments):
    if any(arg in ('--debug', '--profile') or arg.startswith('--flavor') for arg in arguments):
        raise ValueError('Distribution profiles require the release Runner configuration')
    validate(profile, {'CRISP_DISTRIBUTION': profile, 'CRISP_ENABLE_FUSE': str(fuse).lower()})
    # Do not let subsequent default builds inherit the direct profile.
    config = ROOT / 'macos/Flutter/ephemeral/Distribution.xcconfig'
    config.parent.mkdir(parents=True, exist_ok=True)
    previous = config.read_bytes() if config.exists() else None
    config.write_text(f'CRISP_BUILD_PROFILE = {profile}\nCRISP_APP_ENTITLEMENTS = {ENTITLEMENTS[profile]}\n')
    try:
        return subprocess.run([flutter, 'build', 'macos', '--release',
            f'--dart-define=CRISP_DISTRIBUTION={profile}',
            f'--dart-define=CRISP_ENABLE_FUSE={str(fuse).lower()}', *arguments], cwd=ROOT).returncode
    finally:
        if previous is None:
            config.unlink(missing_ok=True)
        else:
            config.write_bytes(previous)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    builder = commands.add_parser('build')
    builder.add_argument('--profile', choices=ENTITLEMENTS, required=True)
    builder.add_argument('--fuse', action='store_true')
    builder.add_argument('--flutter', default='flutter')
    builder.add_argument('arguments', nargs=argparse.REMAINDER)
    checker = commands.add_parser('verify')
    checker.add_argument('--profile', choices=ENTITLEMENTS, required=True)
    checker.add_argument('--app', type=Path, required=True)
    reader = commands.add_parser('profile')
    reader.add_argument('--app', type=Path, required=True)
    commands.add_parser('stage')
    args = parser.parse_args()
    try:
        if args.command == 'build':
            arguments = args.arguments[1:] if args.arguments[:1] == ['--'] else args.arguments
            return build(args.profile, args.fuse, args.flutter, arguments)
        if args.command == 'stage':
            output = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']
            print(str(stage(os.environ.get('CRISP_BUILD_PROFILE', 'appstore'), output,
                            os.environ.get('DART_DEFINES', ''))).lower())
        elif args.command == 'profile':
            print(app_profile(args.app))
        else:
            verify(args.profile, args.app)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'macOS distribution check failed: {error}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
