import datetime
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'CrispCloud'
PROJECT = ROOT / 'full-crisp-app'
BUILD = PROJECT / '.dart_tool/flutter_build/ad833f6fe41764e7ef07a4dacd9211b1'
DEST = SOURCE / 'docs/validation/zotero-fidelity-20261116/full-app-build'
DEST.mkdir(parents=True, exist_ok=True)

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def copy(source, relative):
    target = DEST / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return digest(target)

receipt = json.loads((ROOT / 'full-crisp-build-receipt.json').read_text())
for name in ['warm-crisp-locked-cache.py', 'prepare-full-crisp.py',
             'run-full-crisp.py', 'package-full-crisp.py']:
    copy(ROOT / name, 'scripts/' + name)
for name in ['full-crisp-attempt.log', 'full-crisp-bundle.log',
             'full-crisp-locked-restore.log', 'full-crisp-cache-warm.log']:
    copy(ROOT / name, 'logs/' + name)
for command in receipt['commands']:
    command['log'] = 'logs/' + command['log']

initial_logs = []
for name in ['full-crisp-app-pub-get.log', 'full-crisp-app-pub-get-diagnostic.log',
             'full-crisp-app-offline-diagnostic.log', 'full-crisp-cache-target.log']:
    sha = copy(ROOT / 'logs' / name, 'initial-attempts/' + name)
    initial_logs.append({'path': 'initial-attempts/' + name, 'sha256': sha})
copy(ROOT / 'full-crisp-app-setup.json', 'initial-attempts/setup.json')
receipt['initial_attempts'] = {
    'setup': 'initial-attempts/setup.json', 'logs': initial_logs,
    'note': 'The initial online restore and diagnostic were bounded at 240s and 60s respectively. The offline diagnostic identified an uncached exact dependency. These attempts are retained, not counted as successful restore.',
}

copy(ROOT / 'full-crisp-cache-receipt.json', 'cache/receipt.json')
for path in sorted((ROOT / 'full-crisp-cache-logs').glob('*.log')):
    copy(path, 'cache/full-crisp-cache-logs/' + path.name)
receipt['cache_restore'] = 'cache/receipt.json'

before = json.loads((ROOT / 'full-crisp-source-before.json').read_text())
after = json.loads((ROOT / 'full-crisp-source-after.json').read_text())
receipt['source_before'] = 'source-before.json'
receipt['source_after'] = 'source-after.json'
receipt['source_before_sha256'] = copy(ROOT / 'full-crisp-source-before.json', 'source-before.json')
receipt['source_after_sha256'] = copy(ROOT / 'full-crisp-source-after.json', 'source-after.json')

for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml',
             'LICENSE.txt', '.dart_tool/package_config.json',
             '.dart_tool/flutter_build/dart_plugin_registrant.dart']:
    copy(PROJECT / name, 'inputs/' + name.lstrip('.').replace('.dart_tool/', 'dart_tool/'))

stamp = json.loads((BUILD / 'kernel_snapshot_program.stamp').read_text())
inputs = {name: digest(Path(name)) for name in sorted(set(stamp['inputs']))}
assert str(PROJECT / 'lib/main.dart') in inputs
(DEST / 'compiler').mkdir(exist_ok=True)
(DEST / 'compiler/input-sha256.json').write_text(json.dumps(inputs, indent=2) + '\n')
localizations = json.loads((BUILD / 'gen_l10n_inputs_and_outputs.json').read_text())
generated = {name: digest(Path(name)) for name in localizations['outputs']}
generated_inputs = {name: digest(Path(name)) for name in localizations['inputs']}
(DEST / 'compiler/generated-localizations.json').write_text(json.dumps({
    'inputs': generated_inputs, 'outputs': generated,
    'canonical_input_hashes': {
        str(Path(name).relative_to(PROJECT)): before[str(Path(name).relative_to(PROJECT))]
        for name in localizations['inputs']
    },
}, indent=2) + '\n')
generated_rel = [str(Path(name).relative_to(PROJECT)) for name in generated]
lib_mismatches = [name for name, sha in before.items()
    if name.startswith('lib/') and name not in generated_rel
    and digest(PROJECT / name) != sha]
assert not lib_mismatches, lib_mismatches

kernel = BUILD / 'app.dill'
assert kernel.read_bytes()[:4].hex() == '90abcdef'
receipt['kernel_compilation'] = {
    'status': 'passed', 'target': 'kernel_snapshot_program',
    'entrypoint': 'lib/main.dart',
    'basis': 'The actual Flutter bundle invocation completed its independent kernel target. The fresh target stamp is written only after KernelCompiler returns a non-null result with errorCount == 0; Flutter clears it if that target throws. The separate required native-assets hook failed.',
    'kernel_path': str(kernel), 'kernel_sha256': digest(kernel),
    'kernel_bytes': kernel.stat().st_size, 'kernel_magic': '90abcdef',
    'kernel_modified_utc': datetime.datetime.fromtimestamp(kernel.stat().st_mtime, datetime.timezone.utc).isoformat(),
    'stamp_modified_utc': datetime.datetime.fromtimestamp((BUILD / 'kernel_snapshot_program.stamp').stat().st_mtime, datetime.timezone.utc).isoformat(),
    'stamp': 'compiler/kernel_snapshot_program.stamp',
    'stamp_sha256': copy(BUILD / 'kernel_snapshot_program.stamp', 'compiler/kernel_snapshot_program.stamp'),
    'depfile': 'compiler/kernel_snapshot_program.d',
    'depfile_sha256': copy(BUILD / 'kernel_snapshot_program.d', 'compiler/kernel_snapshot_program.d'),
    'compiler_inputs': 'compiler/input-sha256.json',
    'compiler_inputs_sha256': digest(DEST / 'compiler/input-sha256.json'),
    'compiler_inputs_count': len(inputs),
    'generated_localizations': 'compiler/generated-localizations.json',
    'kernel_archived': False,
    'reason_binary_not_archived': 'Large reproducible build output; source, exact dependencies, commands, target evidence and content hash retained.',
}
copy(BUILD / 'gen_l10n_inputs_and_outputs.json', 'compiler/gen_l10n_inputs_and_outputs.json')
receipt['copied_lib_source'] = {
    'source_root': str(SOURCE / 'lib'), 'isolated_root': str(PROJECT / 'lib'),
    'pre_generation_copy_match': True,
    'post_generation_matches_except_declared_outputs': True,
    'generated_outputs': generated_rel,
    'generated_hashes': 'compiler/generated-localizations.json',
}
receipt['native_assets'] = {
    'status': 'failed', 'package': 'crisp_catalog', 'missing_executable': 'cargo',
    'command': ['cargo', 'build', '--release', '--locked', '--manifest-path',
        str(PROJECT / 'packages/crisp_catalog/native/Cargo.toml'),
        '--target', 'x86_64-unknown-linux-gnu'],
    'hooks_disabled': False, 'production_configuration_modified': False,
    'native_toolchain_installed': False,
}
receipt['flutter_runtime'] = json.loads((ROOT / 'flutter-sdk/bin/cache/flutter.version.json').read_text())
framework = ROOT / 'flutter-sdk/packages/flutter_tools/lib/src/build_system'
receipt['flutter_target_sources'] = {
    'common.dart': copy(framework / 'targets/common.dart', 'environment/flutter-kernel-target.dart'),
    'build_system.dart': copy(framework / 'build_system.dart', 'environment/flutter-build-system.dart'),
    'LICENSE': copy(ROOT / 'flutter-sdk/LICENSE', 'environment/flutter-LICENSE'),
}
receipt['packaged_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(DEST / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'receipt': str(DEST / 'receipt.json'),
    'source_files': len(before), 'compiler_inputs': len(inputs),
    'generated_localizations': len(generated), 'kernel_bytes': kernel.stat().st_size,
    'kernel_sha256': receipt['kernel_compilation']['kernel_sha256'],
    'bundle_passed': receipt['bundle_passed']}, indent=2))
