"""Apply the genuine Dart formatter under the locked host language graph."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

base = Path(__file__).resolve().parent.parent
runner = base / 'integration-validation/run-integrated-host.py'
spec = importlib.util.spec_from_file_location('host_runner', runner)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
repo = base / 'CrispCloud'
harness = base / 'validation-runtime/runtime/service-setup/service-harness'
config = harness / '.dart_tool/package_config.json'
graph = json.loads(config.read_text())
target = repo / '.dart_tool/package_config.json'
previous = target.read_bytes() if target.exists() else None
files = ['lib/l10n/office_recovery_strings.dart', 'lib/widgets/office_editor_ribbon.dart']
before = {name: hashlib.sha256((repo / name).read_bytes()).hexdigest() for name in files}
for entry in graph['packages']:
    name = entry['name']
    root = repo if name == 'crisp_cloud' else repo / 'packages' / name if name in module.PACKAGES else module.resolve(config, entry['rootUri'])
    entry['rootUri'] = root.as_uri() + '/'
target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(graph, indent=2) + '\n')
try:
    dart = base / 'validation-runtime/runtime/flutter-sdk/bin/cache/dart-sdk/bin/dart'
    command = [str(dart), 'format', *files]
    result = subprocess.run(command, cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout)
    (base / 'integration-validation/host-formatter-application.log').write_text(result.stdout)
    if result.returncode:
        raise RuntimeError('Formatter failed')
finally:
    if previous is None:
        target.unlink()
    else:
        target.write_bytes(previous)
restored = (target.read_bytes() if target.exists() else None) == previous
assert restored
after = {name: hashlib.sha256((repo / name).read_bytes()).hexdigest() for name in files}
receipt = {'source_before': 'd93ca912fc99b9fe521f78734e31902a785e605e',
           'reason': 'The two incoming main host files failed strict formatting under the resolved production-locked graph.',
           'command': command, 'exit_code': result.returncode,
           'before_sha256': before, 'after_sha256': after,
           'config_restored': restored,
           'unresolved_preflight': 'The earlier no-config diagnostic proposed changes to 14 files. Repeating with the real language graph reduced this to two. No vendored source was changed.'}
(base / 'integration-validation/host-format-correction.json').write_text(json.dumps(receipt, indent=2) + '\n')
