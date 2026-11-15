# Zotero host validation setup

The final local run passed all **15 host tests** and the focused analyzer
reported **No issues found**. The tests ran on Flutter **3.47.8** / Dart
**3.13.7**, using framework commit
`737ba8f885dc774b53b442759999a312c9461e4e`.

## Source identity

- Combined CrispCloud commit: `803537e0c1e5dc3acf4c3659a37515dfb78224d7`.
- Incorporated CrispCloud main: `50b459323fe798c3638b8b8ce499ea91b89f98c0`.
- Shared Quds source pin: `9da9c638bfe3bf932a70b2268dc16ef783fc009a`.
- Incorporated Quds main: `c210315bee537776b556ae9885e907483b6df7bd`.

The receipt records hashes for all seven host implementation/test files. It
also records an aggregate hash covering all 177 manifested shared library
source files. Those source hashes were unchanged before and after the final
test and analyzer runs. The main merge was saved while validation was running;
the receipt therefore retains both the previous HEAD at test start and the
combined commit present at completion. Subsequent documentation-only commits
can retain the same tested code identity.

## Exact dependency evidence

`focused-pubspec.yaml` and `focused-pubspec.lock` are exact copies of the
resolved test harness manifests. `analysis-pubspec.yaml` and
`analysis-pubspec.lock` are exact copies of the analyzer harness manifests.
Their recorded absolute package paths refer to this validation workspace;
rebase those two direct Quds paths when reproducing elsewhere.

The direct hosted dependencies in the test harness are:

| Dependency | Version |
| --- | --- |
| file_picker | 10.3.10 |
| flutter_riverpod | 2.6.1 |
| flutter_secure_storage | 9.2.4 |
| http | 1.6.0 |
| image | 4.12.0 |
| intl | 0.20.3 |
| shared_preferences | 2.5.6 |

Flutter, Flutter localizations, and Flutter test come from the pinned SDK.
The editor and engine are the actual vendored path packages, including their
actual transitive dependencies. The analyzer additionally uses the production
`flutter_lints` version **3.0.2** and the unchanged production lint settings.
Full transitive versions and archive hashes are in the accompanying locks.

## Reproduce the focused host tests

Start with the source commit above and Flutter 3.47.8. Use a fresh writable
scratch directory. This recipe uses the checked-in production lock as Pub's
input, then lets genuine Pub resolution retain the required dependency subset.
It does not modify the application's manifest, patch dependencies, or install
fake native assets.

```bash
export CRISP_SOURCE=/absolute/path/to/CrispCloud
export CHECK_DIR=/absolute/path/to/host-zotero-validation
export EVIDENCE_DIR="$CRISP_SOURCE/docs/validation/zotero-20261115"
export FLUTTER_ROOT=/absolute/path/to/flutter-3.47.8
export TMPDIR="$CHECK_DIR/tmp"
export PUB_CACHE=/absolute/path/to/pub-cache
export XDG_CONFIG_HOME="$CHECK_DIR/xdg-config"
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true

mkdir -p "$CHECK_DIR/test" "$TMPDIR" "$XDG_CONFIG_HOME"

python3 - "$CRISP_SOURCE" "$CHECK_DIR" "$EVIDENCE_DIR" <<'PY'
from pathlib import Path
import shutil
import sys

source, check, evidence = map(Path, sys.argv[1:])
recorded_source = '/workspace/scratch/fa00e2a9ca6c/CrispCloud'
manifest = (evidence / 'focused-pubspec.yaml').read_text()
manifest = manifest.replace(recorded_source, str(source.resolve()))
(check / 'pubspec.yaml').write_text(manifest)
shutil.copy2(source / 'pubspec.lock', check / 'pubspec.lock')
(check / 'lib').symlink_to(source / 'lib', target_is_directory=True)
for name in ['office_zotero_test.dart', 'office_zotero_ribbon_test.dart']:
    (check / 'test' / name).symlink_to(source / 'test' / name)
PY

cd "$CHECK_DIR"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get
"$FLUTTER_ROOT/bin/flutter" test --no-pub --concurrency=1 \
  --reporter expanded \
  test/office_zotero_test.dart test/office_zotero_ribbon_test.dart
```

The two test files and the entire host `lib` directory are symlinks to the
actual source. The final run contained 13 service/target tests and two real
ribbon widget tests. Concurrency 1 keeps temporary compiler output within the
available disk budget.

## Reproduce focused analysis

The Dart analyzer resolves file symlinks to their physical project location.
That original application directory has a much broader dependency graph than
this focused harness. Use fresh byte-identical source copies in a separate
context for analysis:

```bash
export ANALYSIS_DIR="$CHECK_DIR/analysis"
mkdir -p "$ANALYSIS_DIR/test"

python3 - "$CRISP_SOURCE" "$ANALYSIS_DIR" "$EVIDENCE_DIR" <<'PY'
from pathlib import Path
import shutil
import sys

source, check, evidence = map(Path, sys.argv[1:])
recorded_source = '/workspace/scratch/fa00e2a9ca6c/CrispCloud'
manifest = (evidence / 'analysis-pubspec.yaml').read_text()
manifest = manifest.replace(recorded_source, str(source.resolve()))
(check / 'pubspec.yaml').write_text(manifest)
shutil.copy2(source / 'pubspec.lock', check / 'pubspec.lock')
shutil.copy2(source / 'analysis_options.yaml', check / 'analysis_options.yaml')
shutil.copytree(source / 'lib', check / 'lib')
for name in ['office_zotero_test.dart', 'office_zotero_ribbon_test.dart']:
    shutil.copy2(source / 'test' / name, check / 'test' / name)
PY

cd "$ANALYSIS_DIR"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" analyze \
  lib/services/office_zotero.dart \
  lib/l10n/office_zotero_strings.dart \
  lib/l10n/office_editor_strings.dart \
  lib/widgets/office_editor_ribbon.dart \
  test/office_zotero_test.dart test/office_zotero_ribbon_test.dart
```

## Actual runtime entry point used for the recorded run

The constrained workspace lacked a system `/tmp`; a writable `TMPDIR` was
necessary. The installed SDK's prebuilt tool snapshot was invoked directly:

```bash
/workspace/scratch/fa00e2a9ca6c/flutter/bin/cache/dart-sdk/bin/dart \
  /workspace/scratch/fa00e2a9ca6c/flutter-zotero-sdk/bin/cache/flutter_tools.snapshot \
  test --no-pub --concurrency=1 --reporter expanded \
  test/office_zotero_test.dart test/office_zotero_ribbon_test.dart
```

`FLUTTER_ROOT` pointed to `flutter-zotero-sdk`, an isolated tool-cache/lock
directory sharing the exact installed SDK source and binaries. Actual
Flutter-tools dependencies were resolved normally. Missing locked archives
were downloaded from official pub.dev URLs, checked against the SDK lockfile
SHA-256 values, and imported with Dart's official `pub cache preload` command.
No SDK tool code or production dependency constraints were changed to bypass
validation.

## Scope and limits

This validates the Zotero host transport, credential adapter, insertion-target
capture, and actual menu/ribbon widgets with real shared editor code. It does
not claim a complete native CrispCloud build. The full application includes
unrelated Rust/Cargo native hooks unavailable in this workspace, so its broader
provider/native dependency graph was outside this harness. The complete
`office_editor_dialog.dart` graph was consequently not analyzed here; its
extracted insertion-target helper is compiled and covered by the host tests.

Credential persistence was tested with injected stores, not a live OS
keychain. Existing application startup checks govern OS-store availability.
No private Zotero account or user API key was used. GitHub Actions were not
awaited.
