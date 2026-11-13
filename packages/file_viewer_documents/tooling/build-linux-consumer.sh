#!/usr/bin/env bash
# Compile-only consumer check. Uses the real Flutter SDK and native WebKit host.
set -euo pipefail

document_tooling_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
document_package_dir="$(cd -- "$document_tooling_dir/.." && pwd)"

pkg-config --print-errors --atleast-version=2.48.4 webkit2gtk-4.1
pkg-config --print-errors --exists gtk+-3.0 gmodule-2.0 epoxy
python3 - "$document_package_dir" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

package = Path(sys.argv[1])
cmake = subprocess.check_output(['cmake', '--version'], text=True).splitlines()[0]
match = re.match(r'^cmake version (\d+)\.(\d+)', cmake)
if not match or tuple(map(int, match.groups())) < (3, 19):
    raise SystemExit('The document host requires CMake 3.19 or newer: ' + cmake)
sdk = json.loads(subprocess.check_output(['flutter', '--version', '--machine'], text=True))
if sdk.get('frameworkVersion') != '3.47.8':
    raise SystemExit('This consumer check requires the unmodified Flutter 3.47.8 SDK.')
print(f"Flutter {sdk['frameworkVersion']} ({sdk.get('frameworkRevision', 'unknown revision')}); {cmake}")
manifest = json.loads((package / 'RUNTIME_MANIFEST.json').read_text())
if manifest['upstream']['commit'] != 'd264009ca6efb3daed79a39d1ae63133e0f25558':
    raise SystemExit('The downloaded document runtime has an unexpected upstream pin.')
for relative in ['assets/index.html', 'assets/runtime/host.js',
                 'assets/runtime/libwpd.wasm', 'assets/runtime/chm_wasm_bg.wasm']:
    if not (package / relative).is_file():
        raise SystemExit('Download the selected-document-runtime artifact first: missing ' + relative)
PY

document_consumer_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/document-linux-consumer.XXXXXX")"
trap 'rm -rf -- "$document_consumer_root"' EXIT
document_consumer_app="$document_consumer_root/app"
flutter config --enable-linux-desktop
flutter create --platforms=linux --project-name=document_host_consumer \
  --org=cloud.crisp.validation --no-pub "$document_consumer_app"

python3 - "$document_package_dir" "$document_consumer_app" <<'PY'
import json
from pathlib import Path
import sys

package, app = map(Path, sys.argv[1:])
# JSON is a YAML subset and safely represents absolute paths, including spaces.
(app / 'pubspec.yaml').write_text(json.dumps({
    'name': 'document_host_consumer',
    'publish_to': 'none',
    'environment': {'sdk': '>=3.13.0 <4.0.0'},
    'dependencies': {
        'flutter': {'sdk': 'flutter'},
        'file_viewer_documents': {'path': str(package)},
    },
    'flutter': {'uses-material-design': True},
}, indent=2) + '\n')
(app / 'lib/main.dart').write_text('''
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_viewer_documents/file_viewer_documents.dart';

// Compile the actual Dart host as well as the generated native registrant.
// This check never launches the application or claims document rendering.
void main() => runApp(MaterialApp(home: Scaffold(body: DocumentPreview(
  bytes: Uint8List(0),
  filename: 'compile-only.wpd',
  kind: DocumentPreviewKind.wordperfect,
))));
''')
cmake_file = app / 'linux/CMakeLists.txt'
cmake = cmake_file.read_text()
marker = 'include(flutter/generated_plugins.cmake)'
if cmake.count(marker) != 1:
    raise SystemExit('Unexpected pinned Flutter Linux template; plugin gate was not inserted.')
checks = '''
get_target_property(document_host_definitions file_viewer_documents_plugin COMPILE_DEFINITIONS)
if(NOT "FILE_VIEWER_DOCUMENTS_HAS_WEBKITGTK=1" IN_LIST document_host_definitions)
  message(FATAL_ERROR "The real WebKitGTK document host must compile; a stub is not accepted.")
endif()
if(NOT TARGET file_viewer_documents_webkit_probe)
  message(FATAL_ERROR "The real WebKitGTK document startup probe target is missing.")
endif()
'''
cmake_file.write_text(cmake.replace(marker,
    'set(FILE_VIEWER_DOCUMENTS_WEBKITGTK ON CACHE BOOL "Compile the real document host" FORCE)\n'
    + marker + checks))
PY

(
  cd -- "$document_consumer_app"
  flutter pub get
  flutter build linux --release
)

document_bundle="$document_consumer_app/build/linux/x64/release/bundle"
test -x "$document_bundle/document_host_consumer"
test -s "$document_bundle/lib/libfile_viewer_documents_plugin.so"
test -x "$document_bundle/lib/file_viewer_documents_webkit_probe"
printf '%s\n' 'Compiled a Linux release consumer and verified the enabled document plugin and executable WebKit probe. Desktop rendering was not launched.'
