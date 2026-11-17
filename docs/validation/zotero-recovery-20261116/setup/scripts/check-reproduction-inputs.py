#!/usr/bin/env python3
"""Read-only setup preflight before creating isolated qualification wrappers.

Run after the explicit Flutter-managed, enforced-lockfile resolution in the
README. This check never adds metadata, resolves packages or runs tests.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

FRAMEWORK = '737ba8f885dc774b53b442759999a312c9461e4e'
ENGINE = 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
ASSETS = [
    'packages/quds_office_engine/third_party/hyphenation/LICENSE',
    'packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE',
    'packages/quds_office_engine/third_party/proofing/QUDS_WORDS_LICENSE',
    'packages/quds_office_engine/third_party/fonttools/LICENSE',
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    args = parser.parse_args()
    root = args.workspace.resolve()
    toolchain = root / 'zotero-toolchain'
    sdk = toolchain / 'flutter-sdk'
    version = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
    assert subprocess.check_output(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], text=True).strip() == FRAMEWORK
    assert version['frameworkRevision'] == FRAMEWORK
    assert version['engineRevision'] == ENGINE
    assert version['frameworkVersion'] == '3.47.8'
    assert version['dartSdkVersion'] == '3.13.7'
    expected_artifacts = {
        'bin/cache/dart-sdk/bin/dart': '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',
        'bin/cache/artifacts/engine/linux-x64/flutter_tester': '800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f',
    }
    for name, expected in expected_artifacts.items():
        assert digest(sdk / name) == expected, name
    original = json.loads((toolchain / 'reconstruction-inputs.json').read_text())['inputs_sha256']
    for name, expected in original.items():
        if name != 'crisp-host-harness/pubspec.yaml':  # Explicit four-asset overlay only.
            assert digest(toolchain / name) == expected, f'Reconstructed manifest/lock changed: {name}'
    metadata = {}
    for name in ['harness/quds_office_engine', 'harness/quds_office_editor',
                 'harness/quds_office_studio', 'crisp-host-harness']:
        path = toolchain / name / '.dart_tool/package_config.json'
        graph = json.loads(path.read_text())
        assert graph.get('generator') == 'pub', name
        assert graph.get('flutterRoot') == sdk.as_uri(), (
            f'{name}: Flutter metadata is not initialized. Run the README\'s explicit '
            'Flutter-managed pub get --enforce-lockfile before establishing a fingerprint.')
        assert graph.get('flutterVersion') == version['frameworkVersion'], name
        metadata[name] = {'package_count': len(graph['packages']), 'sha256': digest(path),
                          'flutterRoot': graph['flutterRoot'], 'flutterVersion': graph['flutterVersion']}
    engine_example = toolchain / 'harness/quds_office_engine/example'
    assert not engine_example.exists() and not engine_example.is_symlink(), (
        'The original engine wrapper must not expose the workspace-only example project. '
        'Use fresh reconstructed wrappers; the three exact examples are linked only after isolation.')
    host = toolchain / 'crisp-host-harness'
    pubspec = (host / 'pubspec.yaml').read_text()
    for asset in ASSETS:
        assert f'    - {asset}\n' in pubspec, asset
        assert (host / asset).is_file(), asset
        assert (host / asset).resolve() == (root / 'CrispCloud' / asset).resolve(), asset
    print(json.dumps({'ready_for_isolation': True, 'runtime_metadata_verified': metadata,
                      'all_recorded_lockfiles_unchanged': True,
                      'full_engine_example_project_absent': True,
                      'four_real_notice_assets_present': True,
                      'writes_pub_get_downloads_or_tests_performed': False}, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
