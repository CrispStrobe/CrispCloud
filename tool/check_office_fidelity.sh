#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/verify_office_fidelity.py
(cd packages/quds_office_engine && dart pub get && bash tool/fidelity/check.sh)
flutter test test/office_fidelity_workflow_test.dart test/office_formatting_preservation_test.dart test/office_roundtrip_preservation_test.dart test/office_editor_fixes_test.dart
python3 packages/quds_office_engine/tool/fidelity/corpus.py verify build/fidelity
