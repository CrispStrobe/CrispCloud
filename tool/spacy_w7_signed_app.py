#!/usr/bin/env python3
"""Qualify an actual signed ARM64 CrispCloud Runner with its owned native worker.

No store upload, notarization submission, release, default flip or W6 replay.
The explicit diagnostic define enters the real app's main before user storage
initialization. Normal builds leave this path out and optional grammar OFF.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request

import macos_public_signing as signing

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'cstr/crispembed-spacy-de-core-news-sm-3.8.0'
MAC_REVISION = 'a0455e70740688161b3a494e553f09bbc783ecc9'
MAC_PREFIX = 'macos-candidates/1d4f433a90e4f372253fcb600d012bad5f5594d4'
MAC_ARCHIVE_SHA = 'f2b7cbc9d9d127459964fcefb510378c390c0991ad3e0595876034355eca149f'
UNSIGNED_LIBRARY_SHA = '5cb67f0092f3659653773b8687fe7448dc3c235144b01c80a6fae54c103ca4e5'
MODEL_REVISION = '659dae33997d00296ae12b76510fa4dfe26540e0'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    assert os.environ.get('GITHUB_ACTIONS') == 'true'
    assert os.environ.get('GITHUB_REPOSITORY') == 'CrispStrobe/CrispCloud'
    assert platform.system() == 'Darwin' and platform.machine() == 'arm64'
    out = Path(os.environ['RUNNER_TEMP']) / 'w7-signed-app-evidence'
    out.mkdir()
    scratch = Path(os.environ['RUNNER_TEMP']) / 'w7-signed-app-scratch'
    scratch.mkdir()
    report = {'schema': 'crispcloud.spacy.w7.signed-app-execution.v1', 'passed': False,
        'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'quds_source': '2e013f26c7d4db54ecabe2c955117cbce5379408',
        'quds_PR153_merged': False, 'provider_default': 'OFF', 'native_probe_started': False,
        'release_or_notary_submission': False, 'grammar_quality_qualified': False,
        'consumed_W6_or_W7_grammar_panel_replayed': False, 'stage': 'fresh-input-downloads'}

    def save():
        (out / 'signed-app-execution.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(label, command, **kwargs):
        report['stage'] = label
        save()
        with (out / (label + '.log')).open('w') as log:
            subprocess.run([str(x) for x in command], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                           check=True, **kwargs)

    def download(url, path, sha, size):
        with urllib.request.urlopen(urllib.request.Request(url, headers={'Cache-Control': 'no-cache'}), timeout=180) as response:
            assert response.status == 200
            with path.open('xb') as output:
                shutil.copyfileobj(response, output)
        assert path.stat().st_size == size and digest(path) == sha
        return {'url': url, 'bytes': size, 'sha256': sha, 'fresh_empty_cache': True}

    try:
        archive = scratch / 'native.tar.gz'
        report['fresh_unsigned_native'] = download(
            f'https://huggingface.co/{REPOSITORY}/resolve/{MAC_REVISION}/{MAC_PREFIX}/spacy-native-macos-arm64-f32-unsigned.tar.gz',
            archive, MAC_ARCHIVE_SHA, 827200)
        native = scratch / 'native'
        native.mkdir()
        with tarfile.open(archive) as source:
            # Python's data filter refuses traversal/unsafe links. The exact
            # archived bytes were authenticated before extraction.
            source.extractall(native, filter='data')
        library = native / 'lib/libcrispembed-spacy.dylib'
        assert digest(library) == UNSIGNED_LIBRARY_SHA
        run('sign-native', ['codesign', '--force', '--timestamp', '--options', 'runtime',
            '--keychain', signing.required('CRISP_SIGNING_KEYCHAIN'), '--sign', signing.required('DEVELOPER_ID_SHA1'), library])
        signed_sha = digest(library)
        report['signed_library_sha256'] = signed_sha
        report['signed_library_bytes'] = library.stat().st_size
        run('verify-native-signature', ['codesign', '--verify', '--strict', '--all-architectures', library])
        report['native_codesign'] = subprocess.check_output(['codesign', '-dvvv', str(library)], stderr=subprocess.STDOUT, text=True)
        base_url = f'https://huggingface.co/{REPOSITORY}/resolve/{MODEL_REVISION}/bundle/'
        manifest_path = scratch / 'manifest.json'
        report['fresh_model_manifest'] = download(base_url + 'manifest.json', manifest_path,
            'd599768375de3dc56abcca5cf1d49da0015857f9d3a10640aebb5317ef5d427e', 23762)
        manifest = json.loads(manifest_path.read_text())
        bundle = scratch / 'bundle'
        bundle.mkdir()
        shutil.copyfile(manifest_path, bundle / 'manifest.json')
        report['fresh_model_files'] = {}
        for name, pin in manifest['files'].items():
            report['fresh_model_files'][name] = download(base_url + name, bundle / name,
                pin['sha256'], pin['size_bytes'])
        run('pub-get', ['flutter', 'pub', 'get'])
        shutil.copyfile(ROOT / 'pubspec.lock', out / 'resolved-pubspec.lock')
        report['resolved_lock_sha256'] = digest(ROOT / 'pubspec.lock')
        run('focused-analyze', ['dart', 'analyze', 'lib/services/office_spacy_preferences.dart',
            'lib/services/office_spacy_native.dart', 'lib/services/office_spacy_unsupported.dart',
            'lib/widgets/office_spacy_settings.dart', 'packages/quds_proofing_spacy/lib'])
        run('default-off-controls', ['flutter', 'test', '--no-pub', 'test/office_spacy_preferences_test.dart'])
        # Use the existing real Runner configuration and sandbox entitlement
        # selection, not an alternate tiny fixture app or substitute entrypoint.
        run('build-actual-app', [sys.executable, ROOT / 'tool/with_ci_apple_sqlite.py', '--',
            sys.executable, ROOT / 'tool/macos_distribution.py', 'build', '--profile', 'appstore', '--',
            '--no-pub', '--dart-define=CRISP_W7_NATIVE_PROBE=true',
            '--dart-define=CRISP_SPACY_SIGNED_LIBRARY_SHA256=' + signed_sha])
        apps = list((ROOT / 'build/macos/Build/Products/Release').glob('*.app'))
        assert len(apps) == 1
        app = apps[0]
        executable = app / 'Contents/MacOS' / plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleExecutable']
        assert 'arm64' in subprocess.check_output(['file', str(executable)], text=True)
        resources = app / 'Contents/Resources/spacy-w7'
        (resources / signed_sha).mkdir(parents=True)
        shutil.copyfile(library, resources / signed_sha / library.name)
        shutil.copytree(bundle, resources / 'bundle')
        shutil.copytree(native / 'share/licenses', resources / 'licenses')
        shutil.copyfile(signing.required('APP_DEVID_PROFILE'), app / 'Contents/embedded.provisionprofile')
        extension = app / 'Contents/PlugIns/FinderExtension.appex'
        assert extension.is_dir()
        shutil.copyfile(signing.required('EXT_DEVID_PROFILE'), extension / 'Contents/embedded.provisionprofile')
        work_ent = scratch / 'app-entitlements.plist'
        extension_ent = scratch / 'extension-entitlements.plist'
        signing.entitlements(ROOT / 'macos/Runner/Release.entitlements', signing.BUNDLE,
                             signing.required('APPLE_TEAM_ID'), work_ent)
        signing.entitlements(ROOT / 'macos/FinderExtension/FinderExtension.entitlements', signing.EXTENSION,
                             signing.required('APPLE_TEAM_ID'), extension_ent)
        def sign(target, entitlements=None):
            args = ['codesign', '--force', '--timestamp', '--options', 'runtime', '--keychain',
                signing.required('CRISP_SIGNING_KEYCHAIN'), '--sign', signing.required('DEVELOPER_ID_SHA1')]
            if entitlements:
                args += ['--entitlements', str(entitlements)]
            signing.run(*args, target, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Sign nested Mach-O objects inside-out; retain the already authenticated
        # signed spaCy dylib bytes so the compiled Dart identity remains exact.
        embedded = resources / signed_sha / library.name
        for file in sorted(app.rglob('*'), key=lambda x: len(x.parts), reverse=True):
            if file.is_file() and not file.is_symlink() and file != embedded and file != executable:
                kind = subprocess.check_output(['file', '-b', str(file)], text=True)
                if 'Mach-O' in kind:
                    sign(file)
        for framework in sorted(app.rglob('*.framework'), key=lambda x: len(x.parts), reverse=True):
            sign(framework)
        sign(extension, extension_ent)
        sign(app, work_ent)
        assert digest(embedded) == signed_sha
        run('verify-app-signature', ['codesign', '--verify', '--deep', '--strict', '--all-architectures', app])
        entitlements = subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', str(app)], stderr=subprocess.DEVNULL)
        ent = plistlib.loads(entitlements)
        assert ent.get('com.apple.security.app-sandbox') is True
        assert not ent.get('com.apple.security.cs.disable-library-validation', False)
        report['actual_app_entitlements'] = ent
        report['actual_app_codesign'] = subprocess.check_output(['codesign', '-dvvv', str(app)], stderr=subprocess.STDOUT, text=True)
        report['executable_sha256'] = digest(executable)
        report['executable_file'] = subprocess.check_output(['file', str(executable)], text=True)
        report['native_probe_started'] = True
        run('actual-signed-app-native-worker', [executable], timeout=180)
        lines = (out / 'actual-signed-app-native-worker.log').read_text().splitlines()
        rows = [json.loads(line.split('CRISP_SPACY_W7_RESULT=', 1)[1]) for line in lines if 'CRISP_SPACY_W7_RESULT=' in line]
        assert len(rows) == 1 and rows[0]['passed'] is True
        report['actual_native_worker'] = rows[0]
        report['tested_runtime_sources_sha256'] = {str(p.relative_to(ROOT)): digest(p)
            for prefix in ('lib', 'packages/quds_proofing_spacy/lib') for p in (ROOT / prefix).rglob('*.dart')}
        report['passed'] = True
    except Exception as exc:
        report['failure'] = {'type': type(exc).__name__, 'message': str(exc)[:1500]}
        raise
    finally:
        save()
        (out / 'summary.md').write_text('# Actual signed W7 app/native worker\n\n' + json.dumps({key: report.get(key)
            for key in ('source', 'stage', 'passed', 'native_probe_started', 'failure')}, indent=2) +
            '\n\nDiagnostic actual Runner only. Default provider OFF; Quds merge/pin and Mac grammar qualification remain separate. No store or release upload.\n')


if __name__ == '__main__':
    main()
