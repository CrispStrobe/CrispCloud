import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'CrispCloud'
TARGET = ROOT / 'full-crisp-app'
SCOPES = ['lib', 'assets', 'packages', 'pubspec.yaml', 'pubspec.lock',
          'analysis_options.yaml', 'l10n.yaml', 'LICENSE.txt',
          'macos/vendor/fuse/COPYING.LIB', 'docs/USER_GUIDE.md',
          'docs/help/USER_GUIDE.de.md', 'docs/help/USER_GUIDE.fr.md',
          'docs/help/manifest.json', 'tool/office_fidelity_manifest.json']

def snapshot():
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--', *SCOPES], cwd=SOURCE).decode().split('\0')
    names += subprocess.check_output(
        ['git', 'ls-files', '--others', '--exclude-standard', '-z', '--', *SCOPES],
        cwd=SOURCE).decode().split('\0')
    return {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
            for name in sorted(set(names)) if name and (SOURCE / name).is_file()}

if __name__ == '__main__':
    hashes = snapshot()
    for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']:
        if (TARGET / name).read_bytes() != (SOURCE / name).read_bytes():
            raise RuntimeError(f'{name}: isolated input differs from source')
    lib = TARGET / 'lib'
    if not lib.is_symlink() or lib.resolve() != SOURCE / 'lib':
        raise RuntimeError('Expected the original source lib symlink')
    lib.unlink()
    shutil.copytree(SOURCE / 'lib', lib)
    for name in ['l10n.yaml', 'LICENSE.txt']:
        shutil.copy2(SOURCE / name, TARGET / name)
    for name in ['macos/vendor/fuse/COPYING.LIB', 'docs/USER_GUIDE.md',
                 'docs/help/USER_GUIDE.de.md', 'docs/help/USER_GUIDE.fr.md',
                 'docs/help/manifest.json']:
        dest = TARGET / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / name, dest)
    mismatched = [name for name, digest in hashes.items()
        if name.startswith('lib/')
        and hashlib.sha256((TARGET / name).read_bytes()).hexdigest() != digest]
    if mismatched:
        raise RuntimeError(f'Library copy mismatch: {mismatched}')
    (ROOT / 'full-crisp-source-before.json').write_text(
        json.dumps(hashes, indent=2) + '\n')
    receipt = {
        'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_commit': subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=SOURCE, text=True).strip(),
        'source': str(SOURCE), 'isolated_project': str(TARGET),
        'source_files': len(hashes), 'source_scopes': SCOPES,
        'source_before_sha256': hashlib.sha256(
            (ROOT / 'full-crisp-source-before.json').read_bytes()).hexdigest(),
        'lib_copied_before_gen_l10n': True,
        'dependency_manifests_unchanged': True,
        'assets_packages_are_readonly_inputs_by_symlink': True,
        'intended_command': ['dart', 'flutter_tools.snapshot', 'build', 'bundle',
            '--debug', '--target-platform', 'linux-x64', '--no-pub'],
        'full_native_executable': False, 'gui_runtime_acceptance': False,
        'uses_github_actions': False,
    }
    (ROOT / 'full-crisp-build-receipt.json').write_text(
        json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
