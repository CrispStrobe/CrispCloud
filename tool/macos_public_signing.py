#!/usr/bin/env python3
"""Developer ID signing/notarization using existing identities; never creates keys/certificates.

Uses the same inside-out signing and staple-before-packaging approach as
CrispSorter's scripts/sign_macos_release.sh, with CrispCloud's scoped entitlements.
"""
import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'com.CrispStrobe.cloud'
EXTENSION = BUNDLE + '.FinderExtension'
FILE_PROVIDER = BUNDLE + '.FileProvider'
SHARE_EXTENSION = BUNDLE + '.ShareExtension'
# Optional app extensions: (bundle dir, identifier, entitlements, profile env)
OPTIONAL_EXTENSIONS = [
    ('CrispCloudFileProvider.appex', FILE_PROVIDER,
     'macos/CrispCloudFileProvider/CrispCloudFileProvider.entitlements', 'FP_DEVID_PROFILE'),
    ('ShareExtension.appex', SHARE_EXTENSION,
     'macos/ShareExtension/ShareExtension.entitlements', 'SHARE_DEVID_PROFILE'),
]


def run(*args, **kwargs):
    try:
        return subprocess.run([str(a) for a in args], check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        # security import arguments include passwords: never render the command.
        raise ValueError(f'{Path(str(args[0])).name} operation failed (exit {error.returncode})') from None


def required(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError(f'Missing required signing configuration: {name}')
    return value


def profile_payload(path):
    return plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)], stderr=subprocess.DEVNULL))


def validate_profile(payload, identifier, fingerprint, team):
    expected = team + '.' + identifier
    if payload.get('ProvisionsAllDevices') is not True or payload.get('ProvisionedDevices'):
        raise ValueError('Public macOS releases require a Developer ID profile, not an App Store/development profile')
    if payload.get('Entitlements', {}).get('com.apple.application-identifier') != expected:
        raise ValueError('Developer ID profile has the wrong application identifier')
    if fingerprint.upper() not in {hashlib.sha1(c).hexdigest().upper() for c in payload.get('DeveloperCertificates', [])}:
        raise ValueError('Developer ID profile does not authorize the selected certificate')
    expires = payload.get('ExpirationDate')
    if not isinstance(expires, dt.datetime):
        raise ValueError('Developer ID profile has no valid expiration')
    expires = expires.astimezone(dt.timezone.utc) if expires.tzinfo else expires.replace(tzinfo=dt.timezone.utc)
    if expires <= dt.datetime.now(dt.timezone.utc):
        raise ValueError('Developer ID profile has expired')


def update_search_list(keychain, *, add):
    current = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
    filtered = [path for path in current if Path(path).resolve() != keychain.resolve()]
    desired = filtered + [str(keychain)] if add else filtered
    if desired != current:
        run('security', 'list-keychains', '-d', 'user', '-s', *desired)


def prepare():
    names = ['MACOS_DEVELOPER_ID_P12_BASE64', 'MACOS_DEVELOPER_ID_P12_PASSWORD',
             'MACOS_DEVELOPER_ID_SHA1', 'MACOS_DEVELOPER_ID_PROFILE_BASE64',
             'MACOS_DEVELOPER_ID_FINDEREXT_PROFILE_BASE64', 'ASC_API_KEY_P8_BASE64',
             'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_TEAM_ID']
    values = {name: required(name) for name in names}
    fingerprint = values['MACOS_DEVELOPER_ID_SHA1'].upper()
    team = values['ASC_TEAM_ID']
    if not re.fullmatch(r'[0-9A-F]{40}', fingerprint) or not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Invalid signing fingerprint/team identifier')
    folder = Path(required('RUNNER_TEMP')) / 'crispcloud-public-signing'
    folder.mkdir(mode=0o700)
    try:
        files = {'identity.p12': 'MACOS_DEVELOPER_ID_P12_BASE64',
                 'app.provisionprofile': 'MACOS_DEVELOPER_ID_PROFILE_BASE64',
                 'extension.provisionprofile': 'MACOS_DEVELOPER_ID_FINDEREXT_PROFILE_BASE64',
                 'notary.p8': 'ASC_API_KEY_P8_BASE64'}
        for file, name in files.items():
            path = folder / file
            with path.open('xb') as output:
                os.chmod(path, 0o600)
                output.write(base64.b64decode(values[name], validate=True))
        for file, identifier in [('app.provisionprofile', BUNDLE), ('extension.provisionprofile', EXTENSION)]:
            validate_profile(profile_payload(folder / file), identifier, fingerprint, team)
        password = os.urandom(32).hex()
        keychain = folder / 'developer-id.keychain-db'
        run('security', 'create-keychain', '-p', password, keychain, stdout=subprocess.DEVNULL)
        run('security', 'set-keychain-settings', '-lut', '21600', keychain)
        run('security', 'unlock-keychain', '-p', password, keychain)
        run('security', 'import', folder / 'identity.p12', '-k', keychain,
            '-P', values['MACOS_DEVELOPER_ID_P12_PASSWORD'], '-T', '/usr/bin/codesign', stdout=subprocess.DEVNULL)
        run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s',
            '-k', password, keychain, stdout=subprocess.DEVNULL)
        (folder / 'identity.p12').unlink()
        # codesign requires the identity's keychain on the search list even with --keychain.
        update_search_list(keychain, add=True)
        identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)], text=True)
        if not any(fingerprint in line and 'Developer ID Application:' in line and f'({team})' in line for line in identities.splitlines()):
            raise ValueError('Expected valid Developer ID Application identity/private key not found')
        # Authenticate before spending time on a full native build. Output contains no secrets.
        run('xcrun', 'notarytool', 'history', '--key', folder / 'notary.p8', '--key-id', values['ASC_KEY_ID'],
            '--issuer', values['ASC_ISSUER_ID'], '--output-format', 'json', stdout=subprocess.DEVNULL)
        entries = {'DEVELOPER_ID_SHA1': fingerprint, 'APPLE_TEAM_ID': team,
                   'CRISP_SIGNING_KEYCHAIN': str(keychain), 'APPLE_NOTARY_KEY_PATH': str(folder / 'notary.p8'),
                   'APPLE_NOTARY_KEY_ID': values['ASC_KEY_ID'], 'APPLE_NOTARY_ISSUER_ID': values['ASC_ISSUER_ID'],
                   'APP_DEVID_PROFILE': str(folder / 'app.provisionprofile'),
                   'EXT_DEVID_PROFILE': str(folder / 'extension.provisionprofile')}
        if any('\n' in value or '\r' in value for value in entries.values()):
            raise ValueError('Invalid multiline signing configuration')
        with Path(required('GITHUB_ENV')).open('a') as output:
            for name, value in entries.items():
                output.write(f'{name}={value}\n')
        print('Existing Developer ID identity, both profiles and notarization credentials verified')
    except BaseException:
        cleanup()
        raise


def cleanup():
    folder = Path(required('RUNNER_TEMP')) / 'crispcloud-public-signing'
    if folder.is_symlink():
        raise ValueError('Refusing redirected signing directory')
    update_search_list(folder / 'developer-id.keychain-db', add=False)
    if (folder / 'developer-id.keychain-db').exists():
        subprocess.run(['security', 'delete-keychain', str(folder / 'developer-id.keychain-db')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if folder.exists():
        shutil.rmtree(folder)


def entitlements(source, identifier, team, target, keychain_group=None):
    # Xcode expands $(TeamIdentifierPrefix)/$(AppIdentifierPrefix) (App Group
    # and keychain group IDs); so must re-signing.
    prefix = team.encode() + b'.'
    raw = source.read_bytes().replace(b'$(TeamIdentifierPrefix)', prefix).replace(b'$(AppIdentifierPrefix)', prefix)
    values = plistlib.loads(raw)
    values['com.apple.application-identifier'] = team + '.' + identifier
    values['com.apple.developer.team-identifier'] = team
    if keychain_group:
        values['keychain-access-groups'] = [keychain_group]
    target.write_bytes(plistlib.dumps(values))


def vault_keychain_group(team):
    """Data-protection keychain group for the Touch ID vault-unlock item."""
    return team + '.' + BUNDLE


def profile_allows_keychain_group(payload, group):
    # keychain-access-groups is restricted on macOS: an ad-hoc or unprovisioned
    # signature carrying it is killed at launch (see 2e823d73). It is therefore
    # never in the committed .entitlements files (the unsigned pre-signing smoke
    # launch would fail), only added here when the embedded profile allows it.
    allowed = payload.get('Entitlements', {}).get('keychain-access-groups', [])
    if not isinstance(allowed, list):
        return False
    team = group.split('.', 1)[0]
    return group in allowed or team + '.*' in allowed


def add_keychain_group(entitlements_file, profile, team):
    """Add the vault keychain group to signing entitlements if the profile allows it.

    Returns True when added. Without it, Touch ID vault unlock stays hidden
    (the app probes errSecMissingEntitlement) rather than the app being killed.
    """
    group = vault_keychain_group(team)
    if not profile_allows_keychain_group(profile_payload(profile), group):
        print(f'warning: provisioning profile does not authorize keychain group {group}; '
              'Touch ID vault unlock will be unavailable', file=sys.stderr)
        return False
    values = plistlib.loads(entitlements_file.read_bytes())
    values['keychain-access-groups'] = [group]
    entitlements_file.write_bytes(plistlib.dumps(values))
    return True


def notarize(artifact, receipt):
    credentials = ['--key', required('APPLE_NOTARY_KEY_PATH'), '--key-id', required('APPLE_NOTARY_KEY_ID'),
                   '--issuer', required('APPLE_NOTARY_ISSUER_ID')]
    result = subprocess.check_output(['xcrun', 'notarytool', 'submit', str(artifact), *credentials,
                                     '--wait', '--timeout', '20m', '--output-format', 'json'])
    receipt.write_bytes(result)
    data = json.loads(result)
    if data.get('status') != 'Accepted' or not data.get('id'):
        if data.get('id'):
            run('xcrun', 'notarytool', 'log', data['id'], *credentials)
        raise ValueError(f'Notarization not accepted: {data.get("status")}')


def app_requirement(team):
    """Keep the app's trusted identity stable across Apple signing families."""
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Expected an exact Apple team identifier')
    return f'=designated => anchor apple generic and identifier "{BUNDLE}" and certificate leaf[subject.OU] = "{team}"'


def sign(app, output):
    import macos_distribution
    fingerprint = required('DEVELOPER_ID_SHA1')
    team = required('APPLE_TEAM_ID')
    keychain = required('CRISP_SIGNING_KEYCHAIN')
    if macos_distribution.app_profile(app) != 'github':
        raise ValueError('Developer ID pipeline accepts only the GitHub distribution profile')
    for variable, identifier in [('APP_DEVID_PROFILE', BUNDLE), ('EXT_DEVID_PROFILE', EXTENSION)]:
        validate_profile(profile_payload(Path(required(variable))), identifier, fingerprint, team)
    if plistlib.loads((app / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != BUNDLE:
        raise ValueError('Unexpected app bundle identifier')
    extension = app / 'Contents/PlugIns/FinderExtension.appex'
    if not extension.is_dir():
        raise ValueError('Expected Finder extension missing from the built app')
    if plistlib.loads((extension / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != EXTENSION:
        raise ValueError('Unexpected Finder extension bundle identifier')
    shutil.copyfile(required('APP_DEVID_PROFILE'), app / 'Contents/embedded.provisionprofile')
    shutil.copyfile(required('EXT_DEVID_PROFILE'), extension / 'Contents/embedded.provisionprofile')
    # Finder locations (File Provider). Its team-prefixed App Group needs no
    # profile for Developer ID; FP_DEVID_PROFILE embeds one when provided.
    optional = {}
    for bundle_name, identifier, source, profile_env in OPTIONAL_EXTENSIONS:
        bundle = app / 'Contents/PlugIns' / bundle_name
        if not bundle.is_dir():
            continue
        if plistlib.loads((bundle / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier') != identifier:
            raise ValueError(f'Unexpected {bundle_name} bundle identifier')
        if os.environ.get(profile_env):
            validate_profile(profile_payload(Path(os.environ[profile_env])), identifier, fingerprint, team)
            shutil.copyfile(os.environ[profile_env], bundle / 'Contents/embedded.provisionprofile')
        optional[bundle] = (identifier, source)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='crispcloud-notary-', dir=required('RUNNER_TEMP')) as temporary:
        work = Path(temporary)
        def codesign(target, entitlement=None):
            args = ['codesign', '--force', '--timestamp', '--options', 'runtime', '--keychain', keychain, '--sign', fingerprint]
            if entitlement:
                args += ['--entitlements', str(entitlement)]
            else:
                args += ['--preserve-metadata=entitlements']
            if target == app:
                args += ['--requirements', app_requirement(team)]
            run(*args, target)
        # Preserve scoped helper/extension entitlements while signing all native leaves.
        # Scan the actual code, including native Dart assets, rather than guessing dylib names.
        for file in sorted((app / 'Contents').rglob('*')):
            if file.is_file() and not file.is_symlink():
                kind = subprocess.check_output(['file', '-b', str(file)], text=True)
                if 'Mach-O' in kind:
                    codesign(file)
        bundles = [p for p in (app / 'Contents').rglob('*') if p.is_dir() and not p.is_symlink()
                   and p.suffix in ('.framework', '.app', '.xpc', '.appex')]
        for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
            if bundle == extension:
                target = work / 'extension-entitlements.plist'
                entitlements(ROOT / 'macos/FinderExtension/FinderExtension.entitlements', EXTENSION, team, target)
                codesign(bundle, target)
            elif bundle in optional:
                identifier, source = optional[bundle]
                target = work / f'{bundle.stem}-entitlements.plist'
                entitlements(ROOT / source, identifier, team, target)
                codesign(bundle, target)
            else:
                codesign(bundle)
        target = work / 'app-entitlements.plist'
        app_profile = profile_payload(Path(required('APP_DEVID_PROFILE')))
        group = vault_keychain_group(team)
        if not profile_allows_keychain_group(app_profile, group):
            print(f'warning: Developer ID profile does not authorize keychain group {group}; '
                  'Touch ID vault unlock will be unavailable', file=sys.stderr)
            group = None
        entitlements(ROOT / 'macos/Runner/Direct.entitlements', BUNDLE, team, target, keychain_group=group)
        codesign(app, target)
        macos_distribution.verify('github', app)
        if group:
            signed = plistlib.loads(subprocess.check_output(
                ['codesign', '-d', '--entitlements', '-', '--xml', str(app)], stderr=subprocess.DEVNULL))
            if signed.get('keychain-access-groups') != [group]:
                raise ValueError('Touch ID vault keychain group missing from the signed app')
        details = subprocess.check_output(['codesign', '-dv', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
        if not all(part in details for part in ('Authority=Developer ID Application:', f'TeamIdentifier={team}', 'Timestamp=', 'runtime')):
            raise ValueError('Final signature lacks Developer ID, team, secure timestamp or hardened runtime')
        run('ditto', '-c', '-k', '--keepParent', app, work / 'app.zip')
        notarize(work / 'app.zip', output / 'macos-app-notarization.json')
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        run('codesign', '--verify', '--deep', '--all-architectures', '--strict', app)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        # Package only the stapled app. DMG and ZIP now carry the same accepted bytes.
        run('ditto', '-c', '-k', '--keepParent', app, output / 'crispcloud-macos.zip')
        contents = work / 'dmg'; contents.mkdir()
        run('ditto', app, contents / app.name)
        (contents / 'Applications').symlink_to('/Applications')
        dmg = output / 'crispcloud-macos.dmg'
        run('hdiutil', 'create', '-volname', 'CrispCloud', '-srcfolder', contents, '-ov', '-format', 'UDZO', dmg)
        run('codesign', '--force', '--timestamp', '--keychain', keychain, '--sign', fingerprint, dmg)
        run('codesign', '--verify', '--strict', dmg)
        notarize(dmg, output / 'macos-dmg-notarization.json')
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)
    print('Developer ID signing, app/DMG notarization and stapled packaging completed')


def sign_cli(bundle, archive):
    fingerprint = required('DEVELOPER_ID_SHA1')
    team = required('APPLE_TEAM_ID')
    keychain = required('CRISP_SIGNING_KEYCHAIN')
    code = []
    for file in sorted(bundle.rglob('*')):
        if file.is_file() and not file.is_symlink():
            kind = subprocess.check_output(['file', '-b', str(file)], text=True)
            if 'Mach-O' in kind:
                options = []
                if file.parent == bundle / 'bin' and file.name in ('crispcloud', 'crisp'):
                    # The standalone Dart AOT runtime maps snapshot code outside signed Mach-O pages.
                    options = ['--entitlements', str(ROOT / 'macos/Runner/Cli.entitlements')]
                run('codesign', '--force', '--timestamp', '--options', 'runtime',
                    '--keychain', keychain, '--sign', fingerprint, *options, file)
                run('codesign', '--verify', '--all-architectures', '--strict', file)
                details = subprocess.check_output(['codesign', '-dv', '--verbose=4', str(file)], stderr=subprocess.STDOUT, text=True)
                if not all(value in details for value in ('Authority=Developer ID Application:', f'TeamIdentifier={team}', 'Timestamp=', 'runtime')):
                    raise ValueError('CLI code has an invalid distribution identity or missing timestamp/runtime')
                code.append(file)
    if not code or not (bundle / 'bin/crispcloud').is_file():
        raise ValueError('Native CLI bundle is incomplete')
    archive.parent.mkdir(parents=True, exist_ok=True)
    shutil.make_archive(str(archive.with_suffix('')), 'zip', bundle)
    # Exercise the final archive on a fresh inode, including its executable permissions.
    with tempfile.TemporaryDirectory(prefix='crisp-cli-smoke-', dir=required('RUNNER_TEMP')) as temporary:
        run('ditto', '-x', '-k', archive, temporary)
        run(Path(temporary) / 'bin/crispcloud', '--version')
    # ZIPs and standalone tools cannot be stapled; Apple's online ticket covers the signed code.
    notarize(archive, archive.with_suffix('.notarization.json'))
    print('Developer ID signed and notarized standalone CLI archive')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('prepare'); commands.add_parser('cleanup')
    signer = commands.add_parser('sign')
    signer.add_argument('--app', type=Path, required=True)
    signer.add_argument('--output', type=Path, required=True)
    cli = commands.add_parser('sign-cli')
    cli.add_argument('--bundle', type=Path, required=True)
    cli.add_argument('--archive', type=Path, required=True)
    group = commands.add_parser('keychain-group', help='add the vault keychain group if the profile allows it')
    group.add_argument('--entitlements', type=Path, required=True)
    group.add_argument('--profile', type=Path, required=True)
    group.add_argument('--team', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare': prepare()
        elif args.command == 'keychain-group': add_keychain_group(args.entitlements, args.profile, args.team)
        elif args.command == 'cleanup': cleanup()
        elif args.command == 'sign-cli': sign_cli(args.bundle.resolve(), args.archive.resolve())
        else: sign(args.app.resolve(), args.output.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Public macOS signing failed: {error}\n')


if __name__ == '__main__':
    main()
